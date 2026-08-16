#include "BizTransferService.h"

#ifdef FREEINK_DEVICE_LILYGO_EPD47

#include <ArduinoJson.h>
#include <ESPmDNS.h>
#include <HalStorage.h>
#include <Logging.h>
#include <Memory.h>
#include <NimBLEDevice.h>
#include <WebServer.h>
#include <WiFi.h>
#include <esp_system.h>
#include <esp_task_wdt.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <memory>
#include <mutex>
#include <new>
#include <unordered_set>
#include <vector>

#include "BizBookUploadHandler.h"
#include "BizContentStore.h"
#include "BizReadingProgressStore.h"
#include "CrossPointSettings.h"
#include "JsonSettingsIO.h"
#include "WifiCredentialStore.h"
#include "activities/RenderLock.h"
#include "components/UITheme.h"

namespace {
constexpr uint16_t HTTP_PORT = 80;
constexpr unsigned long WIFI_CONNECT_TIMEOUT_MS = 20000;
constexpr unsigned long TRANSFER_IDLE_TIMEOUT_MS = 5UL * 60UL * 1000UL;
constexpr size_t COMMAND_BUFFER_SIZE = 256;
// Status JSON worst case with every field present (keys + separators + values):
// protocol 12 + state 24 ("sync_receiving") + device 34 (23 chars) + message
// 107 (95 bytes, firmware literals) + request 36 (24 chars) + ip 22 + port 9
// + token 42 (32 hex) + received 21 + total 18 (10 digits each) + filename 109
// (96 bytes, sanitized so JSON escaping cannot expand it) + syncChunks 18
// + syncSize 16 + scan 9 ("scan":15) + 13 commas + 2 braces
// = 492 bytes + NUL <= 500.
// Must stay within NimBLE's BLE_ATT_ATTR_MAX_LEN (512): NimBLEAttValue
// rejects larger payloads outright, leaving the attribute value empty.
constexpr size_t STATUS_BUFFER_SIZE = 512;
// Max UTF-8 bytes of lastFilename serialized into the status JSON.
constexpr size_t STATUS_FILENAME_MAX = 96;
constexpr size_t TOKEN_BYTES = 16;
constexpr size_t SYNC_MAX_JSON_SIZE = 48UL * 1024UL;
// Refuse to start a BLE session below this free-heap floor (NimBLE ~55KB plus
// working headroom for fonts/JSON); see begin().
constexpr uint32_t MIN_HEAP_FOR_BLE = 70UL * 1024UL;
constexpr size_t SYNC_FRAME_SIZE = 240;
constexpr size_t SYNC_FRAME_HEADER_SIZE = 4;
constexpr size_t SYNC_FRAME_PAYLOAD_SIZE = SYNC_FRAME_SIZE - SYNC_FRAME_HEADER_SIZE;
constexpr unsigned long SYNC_READ_WINDOW_MS = 30UL * 1000UL;
constexpr unsigned long SYNC_RECEIVE_IDLE_TIMEOUT_MS = 30UL * 1000UL;
constexpr size_t WIFI_SCAN_MAX_RESULTS = 15;

using TransferState = BizTransferService::State;

// One BLE-triggered scan result. Fixed pool (15 x 36 B = 540 B inside the
// heap-allocated Impl) instead of a per-scan vector: allocated once with the
// service, so scans never fragment DRAM.
struct WifiScanEntry {
  char ssid[33];
  int16_t rssi;
  bool secured;
};

const char* stateName(const TransferState state) {
  switch (state) {
    case TransferState::Connecting:
      return "connecting";
    case TransferState::Ready:
      return "ready";
    case TransferState::Uploading:
      return "uploading";
    case TransferState::Complete:
      return "complete";
    case TransferState::SyncReceiving:
      return "sync_receiving";
    case TransferState::SyncReady:
      return "sync_ready";
    case TransferState::Error:
      return "error";
    case TransferState::Idle:
    default:
      return "idle";
  }
}

// Copy `input` into `output`, clamped to outputSize - 1 bytes cut at a UTF-8
// codepoint boundary, with '"', '\\' and control bytes replaced by '_' so
// ArduinoJson escaping cannot expand the serialized value past its byte budget.
void copySanitizedFilename(const char* input, char* output, const size_t outputSize) {
  size_t length = strlen(input);
  if (length >= outputSize) {
    length = outputSize - 1;
    while (length > 0 && (static_cast<uint8_t>(input[length]) & 0xC0) == 0x80) --length;
  }
  for (size_t i = 0; i < length; ++i) {
    const uint8_t byte = static_cast<uint8_t>(input[i]);
    output[i] = (byte < 0x20 || byte == '"' || byte == '\\') ? '_' : input[i];
  }
  output[length] = '\0';
}

bool constantTimeEquals(const String& left, const char* right) {
  if (!right) return false;
  const size_t rightLength = strlen(right);
  if (left.length() != rightLength) return false;
  uint8_t difference = 0;
  for (size_t i = 0; i < rightLength; ++i) {
    difference |= static_cast<uint8_t>(left[i]) ^ static_cast<uint8_t>(right[i]);
  }
  return difference == 0;
}
}  // namespace

class BizTransferService::Impl {
 public:
  explicit Impl(BizTransferService& owner)
      : owner(owner), serverCallbacks(*this), commandCallbacks(*this), syncRxCallbacks(*this), syncTxCallbacks(*this) {}

  class ServerCallbacks final : public NimBLEServerCallbacks {
   public:
    explicit ServerCallbacks(Impl& impl) : impl(impl) {}

    void onConnect(NimBLEServer* server, NimBLEConnInfo& connection) override {
      impl.bleConnected.store(true);
      server->updateConnParams(connection.getConnHandle(), 12, 24, 0, 180);
      LOG_INF("BIZ", "BLE client connected");
    }

    void onDisconnect(NimBLEServer*, NimBLEConnInfo&, int reason) override {
      impl.bleConnected.store(false);
      impl.bleDisconnectedPending.store(true);
      LOG_INF("BIZ", "BLE client disconnected (reason=%d)", reason);
      if (!impl.bleStopping.load()) NimBLEDevice::startAdvertising();
    }

   private:
    Impl& impl;
  };

  class CommandCallbacks final : public NimBLECharacteristicCallbacks {
   public:
    explicit CommandCallbacks(Impl& impl) : impl(impl) {}

    void onWrite(NimBLECharacteristic* characteristic, NimBLEConnInfo&) override {
      const std::string value = characteristic->getValue();
      if (value.empty() || value.size() >= COMMAND_BUFFER_SIZE) return;

      portENTER_CRITICAL(&impl.commandMux);
      memcpy(impl.pendingCommand, value.data(), value.size());
      impl.pendingCommand[value.size()] = '\0';
      impl.commandPending = true;
      portEXIT_CRITICAL(&impl.commandMux);
    }

   private:
    Impl& impl;
  };

  class SyncRxCallbacks final : public NimBLECharacteristicCallbacks {
   public:
    explicit SyncRxCallbacks(Impl& impl) : impl(impl) {}

    void onWrite(NimBLECharacteristic* characteristic, NimBLEConnInfo&) override {
      const std::string value = characteristic->getValue();
      impl.acceptSyncFrame(value);
    }

   private:
    Impl& impl;
  };

  class SyncTxCallbacks final : public NimBLECharacteristicCallbacks {
   public:
    explicit SyncTxCallbacks(Impl& impl) : impl(impl) {}

    void onRead(NimBLECharacteristic* characteristic, NimBLEConnInfo&) override { impl.readSyncFrame(characteristic); }

   private:
    Impl& impl;
  };

  void clearIncomingLocked() {
    if (syncIncoming) memset(syncIncoming.get(), 0, syncIncomingSize);
    syncIncoming.reset();
    syncIncomingSize = 0;
    syncIncomingReceived = 0;
    syncIncomingChunks = 0;
    syncExpectedSequence = 0;
    syncIncomingError = false;
  }

  void clearOutgoingLocked() {
    if (syncOutgoing) memset(syncOutgoing.get(), 0, syncOutgoingSize);
    syncOutgoing.reset();
    syncOutgoingSize = 0;
    syncOutgoingOffset = 0;
    syncOutgoingSequence = 0;
    syncOutgoingChunks = 0;
  }

  void resetSyncSession() {
    std::lock_guard<std::mutex> lock(syncMutex);
    clearIncomingLocked();
    clearOutgoingLocked();
    syncLastActivityAt.store(0);
  }

  void setSyncError(const char* errorMessage) {
    resetSyncSession();
    setStatus(TransferState::Error, errorMessage);
  }

  bool beginSyncReceive(const size_t size, const uint16_t chunks) {
    // makeUniqueNoThrow value-initializes, so the buffer starts zero-filled.
    auto incoming = makeUniqueNoThrow<uint8_t[]>(size);
    if (!incoming) {
      LOG_ERR("BIZ", "OOM: %u byte sync receive buffer", static_cast<unsigned>(size));
      return false;
    }
    std::lock_guard<std::mutex> lock(syncMutex);
    clearIncomingLocked();
    clearOutgoingLocked();
    syncIncoming = std::move(incoming);
    syncIncomingSize = size;
    syncIncomingChunks = chunks;
    syncLastActivityAt.store(millis());
    return true;
  }

  void acceptSyncFrame(const std::string& value) {
    if (value.size() <= SYNC_FRAME_HEADER_SIZE || state.load() != TransferState::SyncReceiving) return;

    const uint16_t sequence =
        static_cast<uint8_t>(value[0]) | (static_cast<uint16_t>(static_cast<uint8_t>(value[1])) << 8);
    const uint16_t total =
        static_cast<uint8_t>(value[2]) | (static_cast<uint16_t>(static_cast<uint8_t>(value[3])) << 8);
    const size_t payloadSize = value.size() - SYNC_FRAME_HEADER_SIZE;
    std::lock_guard<std::mutex> lock(syncMutex);
    if (state.load() != TransferState::SyncReceiving || !syncIncoming || sequence != syncExpectedSequence ||
        total != syncIncomingChunks || syncIncomingReceived + payloadSize > syncIncomingSize) {
      syncIncomingError = true;
      syncLastActivityAt.store(millis());
      return;
    }
    memcpy(syncIncoming.get() + syncIncomingReceived, value.data() + SYNC_FRAME_HEADER_SIZE, payloadSize);
    syncIncomingReceived += payloadSize;
    ++syncExpectedSequence;
    syncLastActivityAt.store(millis());
  }

  void readSyncFrame(NimBLECharacteristic* characteristic) {
    std::lock_guard<std::mutex> lock(syncMutex);
    if (state.load() != TransferState::SyncReady || !syncOutgoing || syncOutgoingSize == 0 ||
        syncOutgoingSequence >= syncOutgoingChunks) {
      characteristic->setValue(static_cast<const uint8_t*>(nullptr), 0);
      return;
    }
    const size_t remaining = syncOutgoingSize - syncOutgoingOffset;
    const size_t payloadSize = std::min(remaining, syncOutgoingPayloadSize);
    uint8_t frame[SYNC_FRAME_SIZE];
    frame[0] = syncOutgoingSequence & 0xff;
    frame[1] = (syncOutgoingSequence >> 8) & 0xff;
    frame[2] = syncOutgoingChunks & 0xff;
    frame[3] = (syncOutgoingChunks >> 8) & 0xff;
    memcpy(frame + SYNC_FRAME_HEADER_SIZE, syncOutgoing.get() + syncOutgoingOffset, payloadSize);
    characteristic->setValue(frame, payloadSize + SYNC_FRAME_HEADER_SIZE);
    syncOutgoingOffset += payloadSize;
    ++syncOutgoingSequence;
    syncLastActivityAt.store(millis());
  }

  bool takeCompletedIncoming(std::unique_ptr<uint8_t[]>& incoming, size_t& incomingSize, std::string& error) {
    std::lock_guard<std::mutex> lock(syncMutex);
    if (syncIncomingError || !syncIncoming || syncIncomingSize == 0 || syncIncomingReceived != syncIncomingSize ||
        syncExpectedSequence != syncIncomingChunks) {
      error = "Dữ liệu BLE chưa đầy đủ";
      return false;
    }
    incoming = std::move(syncIncoming);
    incomingSize = syncIncomingSize;
    syncIncomingSize = 0;
    syncIncomingReceived = 0;
    syncIncomingChunks = 0;
    syncExpectedSequence = 0;
    syncIncomingError = false;
    return true;
  }

  void begin() {
    if (bleStarted) return;

    // NimBLE plus the render font cache need this much contiguous-ish headroom;
    // half-starting on a starved heap ends as a blank screen. The Connect App
    // activity restarts the device on exit, which reclaims the heap.
    if (ESP.getFreeHeap() < MIN_HEAP_FOR_BLE) {
      LOG_ERR("BIZ", "Not enough heap for BLE session: %u bytes", ESP.getFreeHeap());
      setStatus(TransferState::Error, "Không đủ bộ nhớ — thoát màn hình này rồi thử lại");
      return;
    }

    bleStopping.store(false);
    bleDisconnectedPending.store(false);

    // "scan" status field is session-scoped: cleared on every service start.
    scanInProgress = false;
    scanCompleted = false;
    scanResultCount = 0;

    WIFI_STORE.loadFromFile();

    if (!orphanSweepDone) {
      orphanSweepDone = true;
      BizBookUploadHandler::sweepOrphans();
    }

    uint8_t mac[6];
    WiFi.macAddress(mac);
    snprintf(deviceName, sizeof(deviceName), "BizReader-%02X%02X", mac[4], mac[5]);
    NimBLEDevice::init(deviceName);
    NimBLEDevice::setPower(3);
    // "Just Works" pairing: bond + LE Secure Connections, no MITM (no passkey UI).
    // Command/status/sync characteristics below require an encrypted link, so
    // the HTTP token is never exposed over plaintext BLE.
    NimBLEDevice::setSecurityAuth(true /*bond*/, false /*mitm*/, true /*sc*/);

    bleServer = NimBLEDevice::createServer();
    if (!bleServer) {
      LOG_ERR("BIZ", "Cannot create BLE server");
      NimBLEDevice::deinit(true);
      // publishStatus is a no-op without a status characteristic, but the
      // stored state/message reach the Connect App screen via getStatus().
      setStatus(TransferState::Error, "Không khởi động được BLE");
      return;
    }
    bleServer->setCallbacks(&serverCallbacks);

    NimBLEService* service = bleServer->createService(BizTransferService::SERVICE_UUID);
    if (!service) {
      LOG_ERR("BIZ", "Cannot create BLE service");
      NimBLEDevice::deinit(true);
      bleServer = nullptr;
      setStatus(TransferState::Error, "Không khởi động được BLE");
      return;
    }

    commandCharacteristic = service->createCharacteristic(
        BizTransferService::COMMAND_UUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_ENC, COMMAND_BUFFER_SIZE - 1);
    statusCharacteristic = service->createCharacteristic(
        BizTransferService::STATUS_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY | NIMBLE_PROPERTY::READ_ENC,
        STATUS_BUFFER_SIZE - 1);
    // INFO is deliberately plaintext (no READ_ENC): its value is a static,
    // secret-free protocol descriptor, and pre-pairing readability restores
    // service discovery and diagnostics before the app initiates bonding.
    NimBLECharacteristic* infoCharacteristic =
        service->createCharacteristic(BizTransferService::INFO_UUID, NIMBLE_PROPERTY::READ, 96);
    syncRxCharacteristic = service->createCharacteristic(
        BizTransferService::SYNC_RX_UUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_ENC, SYNC_FRAME_SIZE);
    syncTxCharacteristic = service->createCharacteristic(
        BizTransferService::SYNC_TX_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::READ_ENC, SYNC_FRAME_SIZE);

    if (!commandCharacteristic || !statusCharacteristic || !infoCharacteristic || !syncRxCharacteristic ||
        !syncTxCharacteristic) {
      LOG_ERR("BIZ", "Cannot create BLE characteristics");
      NimBLEDevice::deinit(true);
      bleServer = nullptr;
      commandCharacteristic = nullptr;
      statusCharacteristic = nullptr;
      setStatus(TransferState::Error, "Không khởi động được BLE");
      return;
    }

    commandCharacteristic->setCallbacks(&commandCallbacks);
    syncRxCharacteristic->setCallbacks(&syncRxCallbacks);
    syncTxCharacteristic->setCallbacks(&syncTxCallbacks);
    infoCharacteristic->setValue("{\"protocol\":2,\"transport\":\"ble-sync+wifi-http\",\"folder\":\"/Ebook\"}");
    service->start();

    NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
    advertising->setName(deviceName);
    advertising->addServiceUUID(BizTransferService::SERVICE_UUID);
    advertising->enableScanResponse(true);
    advertising->start();

    bleStarted = true;
    setStatus(TransferState::Idle, "Sẵn sàng kết nối");
    LOG_INF("BIZ", "BLE advertising as %s", deviceName);
  }

  void stop() {
    bleStopping.store(true);
    stopTransfer();
    // Scan results do not outlive the service session.
    scanInProgress = false;
    scanCompleted = false;
    scanResultCount = 0;
    if (bleStarted) {
      // begin() constructs a fresh GATT graph, so clearAll=false would retain
      // duplicate services and heap on every App Connect open/Back cycle.
      NimBLEDevice::deinit(true);
      bleStarted = false;
      bleServer = nullptr;
      commandCharacteristic = nullptr;
      statusCharacteristic = nullptr;
      syncRxCharacteristic = nullptr;
      syncTxCharacteristic = nullptr;
      bleConnected.store(false);
    }
  }

  void stopTransfer() {
    if (httpServer) {
      httpServer->stop();
      httpServer.reset();
    }
    MDNS.end();
    if (WiFi.getMode() != WIFI_MODE_NULL) {
      WiFi.disconnect(true, true);
      WiFi.mode(WIFI_OFF);
    }
    token[0] = '\0';
    uploadReceived = 0;
    uploadTotal = 0;
    requestId[0] = '\0';
    lastFilename[0] = '\0';
    lastSha256[0] = '\0';
    resetSyncSession();
    setStatus(TransferState::Idle, "Đã tắt truyền sách");
  }

  void loop() {
    if (bleDisconnectedPending.exchange(false)) {
      portENTER_CRITICAL(&commandMux);
      commandPending = false;
      portEXIT_CRITICAL(&commandMux);
      const TransferState disconnectedState = state.load();
      if (disconnectedState == TransferState::SyncReceiving || disconnectedState == TransferState::SyncReady) {
        requestId[0] = '\0';
        resetSyncSession();
        setStatus(TransferState::Idle, "Đã hủy phiên đồng bộ BLE");
      }
    }

    char command[COMMAND_BUFFER_SIZE] = {};
    portENTER_CRITICAL(&commandMux);
    if (commandPending) {
      strlcpy(command, pendingCommand, sizeof(command));
      commandPending = false;
    }
    portEXIT_CRITICAL(&commandMux);
    if (command[0] != '\0') processCommand(command);

    const TransferState currentState = state.load();
    if (currentState == TransferState::Connecting) {
      if (WiFi.status() == WL_CONNECTED) {
        onWifiConnected();
      } else if (millis() - connectionStartedAt >= WIFI_CONNECT_TIMEOUT_MS) {
        WiFi.disconnect(true, true);
        WiFi.mode(WIFI_OFF);
        setStatus(TransferState::Error, "Không kết nối được Wi-Fi");
      }
    }

    pollWifiScan();

    if (httpServer) {
      for (int i = 0; i < 32; ++i) {
        httpServer->handleClient();
        if ((i & 0x07) == 0x07) {
          esp_task_wdt_reset();
          yield();
        }
      }

      if (state.load() != TransferState::Uploading && millis() - lastSessionActivityAt >= TRANSFER_IDLE_TIMEOUT_MS) {
        LOG_INF("BIZ", "Transfer window expired");
        stopTransfer();
      }
    }

    const unsigned long syncActivityAt = syncLastActivityAt.load();
    const TransferState syncState = state.load();
    bool receiveError = false;
    if (syncState == TransferState::SyncReceiving) {
      std::lock_guard<std::mutex> lock(syncMutex);
      receiveError = syncIncomingError;
    }
    if (receiveError) {
      setSyncError("Khung dữ liệu BLE không hợp lệ");
    } else if (syncState == TransferState::SyncReceiving && syncActivityAt > 0 &&
               millis() - syncActivityAt >= SYNC_RECEIVE_IDLE_TIMEOUT_MS) {
      setSyncError("Phiên nhận BLE đã hết thời gian");
    } else if (syncState == TransferState::SyncReady && syncActivityAt > 0 &&
               millis() - syncActivityAt >= SYNC_READ_WINDOW_MS) {
      requestId[0] = '\0';
      resetSyncSession();
      setStatus(TransferState::Idle, "Phiên đồng bộ BLE đã đóng");
    }
  }

  void processCommand(const char* command) {
    JsonDocument document;
    const DeserializationError error = deserializeJson(document, command);
    if (error) {
      requestId[0] = '\0';
      setSyncError("Lệnh BLE không hợp lệ");
      return;
    }

    const char* incomingRequestId = document["request"] | "";
    if (strlen(incomingRequestId) > 24) {
      requestId[0] = '\0';
      setSyncError("Mã yêu cầu không hợp lệ");
      return;
    }
    // Optional wall clock from the app (ms since epoch). Adopted only while the
    // device clock is unset, so newest-wins progress merges get real timestamps.
    const uint64_t appNowMs = document["now"].as<uint64_t>();
    if (appNowMs > 0) BizReadingProgressStore::maybeAdoptExternalEpochMs(appNowMs);
    const char* operation = document["op"] | "";
    if (strcmp(operation, "ping") == 0) {
      strlcpy(requestId, incomingRequestId, sizeof(requestId));
      publishStatus();
      return;
    }
    if (strcmp(operation, "stop") == 0) {
      strlcpy(requestId, incomingRequestId, sizeof(requestId));
      stopTransfer();
      return;
    }
    if (strcmp(operation, "wifi_scan") == 0) {
      strlcpy(requestId, incomingRequestId, sizeof(requestId));
      const TransferState currentState = state.load();
      if (currentState != TransferState::Idle) {
        // Busy — Ready included: sync_pull is refused while the HTTP session
        // lingers, so a scan started there could only dead-end the app's
        // follow-up pull. Never disturb the session; adopt the request id and
        // re-notify (same reconnect pattern as start/sync_pull).
        LOG_INF("BIZ", "Ignoring wifi_scan while transfer state is %s", stateName(currentState));
        publishStatus();
        return;
      }
      if (scanInProgress) {
        publishStatus();  // scan already running; status message already says so
        return;
      }
      startWifiScan();
      return;
    }
    if (strcmp(operation, "start") == 0) {
      const TransferState currentState = state.load();
      if (currentState != TransferState::Idle && currentState != TransferState::Error) {
        // A relaunched app sends a fresh request id; adopt it so the re-notified
        // status (which already carries ip/port/token when Ready/Complete) is
        // not discarded as stale. Never restart Wi-Fi mid-session.
        strlcpy(requestId, incomingRequestId, sizeof(requestId));
        LOG_INF("BIZ", "Re-notifying status for start while transfer state is %s", stateName(currentState));
        publishStatus();
        return;
      }
      strlcpy(requestId, incomingRequestId, sizeof(requestId));
      // Prefer the last successfully connected network. When it is unset or no
      // longer stored (networks provisioned only via app wifiAdd never set it,
      // and removing the current network clears it), fall back to the first
      // stored credential — store order is insertion order. A successful
      // connect records the fallback via setLastConnectedSsid (onWifiConnected),
      // so the next start uses it directly.
      const WifiCredential* credential = WIFI_STORE.findCredential(WIFI_STORE.getLastConnectedSsid());
      if (!credential && !WIFI_STORE.getCredentials().empty()) {
        credential = &WIFI_STORE.getCredentials().front();
      }
      if (!credential) {
        setStatus(TransferState::Error, "Hãy lưu Wi-Fi trên BizReader trước");
        return;
      }
      connectWifi(credential->ssid.c_str(), credential->password.c_str());
      return;
    }
    if (strcmp(operation, "sync_pull") == 0) {
      const TransferState currentState = state.load();
      if (currentState == TransferState::SyncReceiving || currentState == TransferState::SyncReady) {
        // Stale session from a previous app run; drop it and serve the new pull.
        LOG_INF("BIZ", "Restarting sync session for new sync_pull");
        resetSyncSession();
      } else if (currentState != TransferState::Idle && currentState != TransferState::Error) {
        // Busy (e.g. Uploading): never interrupt, but adopt the request id so
        // the relaunched app sees a coherent busy status instead of a stale id.
        strlcpy(requestId, incomingRequestId, sizeof(requestId));
        LOG_INF("BIZ", "Ignoring sync pull while transfer state is %s", stateName(currentState));
        publishStatus();
        return;
      }
      strlcpy(requestId, incomingRequestId, sizeof(requestId));
      const size_t frameSize = document["frameSize"] | SYNC_FRAME_SIZE;
      {
        std::lock_guard<std::mutex> lock(syncMutex);
        syncOutgoingPayloadSize =
            std::clamp(frameSize, SYNC_FRAME_HEADER_SIZE + 16, SYNC_FRAME_SIZE) - SYNC_FRAME_HEADER_SIZE;
      }
      if (!prepareSyncSnapshot()) {
        setSyncError("Không tạo được dữ liệu đồng bộ");
        return;
      }
      setStatus(TransferState::SyncReady, "Sẵn sàng gửi dữ liệu BLE");
      return;
    }
    if (strcmp(operation, "sync_begin") == 0) {
      strlcpy(requestId, incomingRequestId, sizeof(requestId));
      if (state.load() != TransferState::SyncReady) {
        setSyncError("Hãy đọc snapshot trước khi gửi dữ liệu");
        return;
      }
      const size_t size = document["size"] | 0;
      const uint16_t chunks = document["chunks"] | 0;
      if (size == 0 || size > SYNC_MAX_JSON_SIZE || chunks == 0 || chunks > size) {
        setSyncError("Kích thước đồng bộ không hợp lệ");
        return;
      }
      if (!beginSyncReceive(size, chunks)) {
        setSyncError("Không đủ bộ nhớ nhận dữ liệu BLE");
        return;
      }
      setStatus(TransferState::SyncReceiving, "Đang nhận dữ liệu BLE");
      return;
    }
    if (strcmp(operation, "sync_commit") == 0) {
      strlcpy(requestId, incomingRequestId, sizeof(requestId));
      if (state.load() != TransferState::SyncReceiving) {
        setSyncError("Không có phiên nhận BLE để hoàn tất");
        return;
      }
      std::unique_ptr<uint8_t[]> incoming;
      size_t incomingSize = 0;
      std::string error;
      const bool complete = takeCompletedIncoming(incoming, incomingSize, error);
      const bool applied = complete && applySyncSnapshot(incoming.get(), incomingSize, error);
      if (incoming) memset(incoming.get(), 0, incomingSize);
      if (!applied) {
        setSyncError(error.c_str());
        return;
      }
      if (!prepareSyncSnapshot()) {
        setSyncError("Không đọc lại được dữ liệu đồng bộ");
        return;
      }
      setStatus(TransferState::SyncReady, "Đồng bộ BLE hoàn tất");
      return;
    }

    strlcpy(requestId, incomingRequestId, sizeof(requestId));
    setSyncError("Lệnh BLE không được hỗ trợ");
  }

  bool prepareSyncSnapshot() {
    JsonDocument snapshot;
    snapshot["protocol"] = 2;
    std::string contentJson;
    JsonDocument content;
    if (BizContentStore::loadJson(contentJson) && !deserializeJson(content, contentJson)) {
      snapshot["content"] = content.as<JsonVariantConst>();
    } else {
      JsonObject empty = snapshot["content"].to<JsonObject>();
      empty["version"] = 2;
      empty["updatedAt"] = 0;
      empty["notes"].to<JsonArray>();
      empty["todos"].to<JsonArray>();
      empty["events"].to<JsonArray>();
      empty["weather"].to<JsonObject>();
      JsonObject sleep = empty["sleep"].to<JsonObject>();
      sleep["mode"] = "calendar";
      JsonObject deleted = empty["deleted"].to<JsonObject>();
      deleted["notes"].to<JsonArray>();
      deleted["todos"].to<JsonArray>();
    }
    JsonObject device = snapshot["device"].to<JsonObject>();
    {
      // Same JSON shape as settings.json (JsonSettingsIO is the single source
      // of the settings format). Contains no secrets.
      JsonDocument settingsDoc;
      JsonSettingsIO::settingsToJson(SETTINGS, settingsDoc);
      device["settings"] = settingsDoc.as<JsonVariantConst>();
    }
    // SSIDs only — Wi-Fi passwords never leave the device.
    JsonArray wifiSsids = device["wifiSsids"].to<JsonArray>();
    for (const WifiCredential& credential : WIFI_STORE.getCredentials()) {
      wifiSsids.add(credential.ssid);
    }
    // Latest completed BLE-triggered scan (best-effort, session-scoped).
    // <=15 entries at ~60 B each -> <=~1 KB against the 48 KB snapshot cap,
    // and this lands before the measureJson guard below.
    if (scanCompleted && scanResultCount > 0) {
      JsonArray wifiScan = device["wifiScan"].to<JsonArray>();
      for (size_t i = 0; i < scanResultCount; ++i) {
        JsonObject network = wifiScan.add<JsonObject>();
        network["ssid"] = wifiScanResults[i].ssid;
        network["rssi"] = wifiScanResults[i].rssi;
        network["sec"] = wifiScanResults[i].secured;
      }
    }
    JsonArray progressItems = snapshot["progress"].to<JsonArray>();
    if (measureJson(snapshot) > SYNC_MAX_JSON_SIZE) {
      LOG_ERR("BIZ", "Sync snapshot content+device exceed %u bytes", static_cast<unsigned>(SYNC_MAX_JSON_SIZE));
      return false;
    }
    for (const BizReadingProgress& progress : BizReadingProgressStore::list()) {
      JsonObject item = progressItems.add<JsonObject>();
      item["filename"] = progress.filename;
      item["percentage"] = progress.percentage;
      item["spineIndex"] = progress.spineIndex;
      item["pageNumber"] = progress.pageNumber;
      item["pageCount"] = progress.pageCount;
      item["pending"] = progress.pending;
      item["updatedAt"] = progress.updatedAt;
      if (measureJson(snapshot) > SYNC_MAX_JSON_SIZE) {
        progressItems.remove(progressItems.size() - 1);
        break;
      }
    }
    const size_t outgoingSize = measureJson(snapshot);
    if (outgoingSize == 0 || outgoingSize > SYNC_MAX_JSON_SIZE) {
      LOG_ERR("BIZ", "Sync snapshot size %u out of range (max %u)", static_cast<unsigned>(outgoingSize),
              static_cast<unsigned>(SYNC_MAX_JSON_SIZE));
      return false;
    }
    // +1: serializeJson null-terminates char buffers within the given capacity.
    auto outgoing = makeUniqueNoThrow<uint8_t[]>(outgoingSize + 1);
    if (!outgoing) {
      LOG_ERR("BIZ", "OOM: %u byte sync snapshot buffer", static_cast<unsigned>(outgoingSize + 1));
      return false;
    }
    const size_t serializedSize = serializeJson(snapshot, reinterpret_cast<char*>(outgoing.get()), outgoingSize + 1);
    if (serializedSize != outgoingSize) {
      LOG_ERR("BIZ", "Sync snapshot serialize mismatch: %u != %u", static_cast<unsigned>(serializedSize),
              static_cast<unsigned>(outgoingSize));
      return false;
    }

    std::lock_guard<std::mutex> lock(syncMutex);
    clearOutgoingLocked();
    syncOutgoing = std::move(outgoing);
    syncOutgoingSize = outgoingSize;
    syncOutgoingChunks =
        static_cast<uint16_t>((syncOutgoingSize + syncOutgoingPayloadSize - 1) / syncOutgoingPayloadSize);
    syncLastActivityAt.store(millis());
    return true;
  }

  bool applySyncSnapshot(const uint8_t* incoming, const size_t incomingSize, std::string& error) {
    JsonDocument snapshot;
    if (!incoming || deserializeJson(snapshot, incoming, incomingSize) || (snapshot["protocol"] | 0) != 2 ||
        !snapshot["content"].is<JsonObjectConst>() || !snapshot["progress"].is<JsonArrayConst>()) {
      error = "Dữ liệu đồng bộ không hợp lệ";
      return false;
    }

    const JsonObjectConst content = snapshot["content"].as<JsonObjectConst>();
    const int contentVersion = content["version"] | 0;
    if ((contentVersion != 1 && contentVersion != 2) || !content["notes"].is<JsonArrayConst>() ||
        !content["todos"].is<JsonArrayConst>() || !content["events"].is<JsonArrayConst>() ||
        !content["weather"].is<JsonObjectConst>() || !content["sleep"].is<JsonObjectConst>() ||
        content["notes"].size() > 40 || content["todos"].size() > 60 || content["events"].size() > 60) {
      error = "Nội dung đồng bộ không hợp lệ";
      return false;
    }
    const std::string sleepMode = content["sleep"]["mode"] | "calendar";
    if (sleepMode != "calendar" && sleepMode != "photo") {
      error = "Chế độ nền nghỉ không hợp lệ";
      return false;
    }
    if (contentVersion >= 2 &&
        (!content["deleted"].is<JsonObjectConst>() || !content["deleted"]["notes"].is<JsonArrayConst>() ||
         !content["deleted"]["todos"].is<JsonArrayConst>() || content["deleted"]["notes"].size() > 80 ||
         content["deleted"]["todos"].size() > 120)) {
      error = "Dữ liệu đã xóa không hợp lệ";
      return false;
    }

    String contentJson;
    serializeJson(content, contentJson);
    if (contentJson.isEmpty() || contentJson.length() > BizContentStore::MAX_JSON_SIZE) {
      error = "Nội dung đồng bộ quá lớn";
      return false;
    }

    std::vector<BizReadingProgress> progressItems;
    progressItems.reserve(std::min<size_t>(snapshot["progress"].size(), 100));
    std::unordered_set<std::string> progressFilenames;
    for (const JsonObjectConst item : snapshot["progress"].as<JsonArrayConst>()) {
      if (progressItems.size() >= 100) {
        LOG_ERR("BIZ", "Sync progress list over 100 entries; extras dropped");
        break;
      }
      BizReadingProgress progress;
      progress.filename = item["filename"] | std::string();
      progress.percentage = item["percentage"] | 0.0f;
      progress.spineIndex = item["spineIndex"] | 0;
      progress.pageNumber = item["pageNumber"] | 0;
      progress.pageCount = item["pageCount"] | 0;
      progress.pending = item["pending"] | false;
      progress.updatedAt = item["updatedAt"] | uint64_t{0};
      if (progress.filename.empty() || progress.filename.size() > 191 ||
          progress.filename.find('/') != std::string::npos || progress.filename.find('\\') != std::string::npos ||
          !std::isfinite(progress.percentage) || progress.percentage < 0.0f || progress.percentage > 1.0f ||
          progress.spineIndex < 0 || progress.pageNumber < 0 || progress.pageCount < 0 ||
          !progressFilenames.insert(progress.filename).second) {
        // Per-entry policy, mirroring BizReadingProgressStore::save: one bad
        // legacy record (e.g. an over-long filename) must not permanently
        // brick the whole snapshot (content + every other progress entry).
        LOG_ERR("BIZ", "Skipping invalid sync progress entry '%.48s'", progress.filename.c_str());
        continue;
      }
      progressItems.push_back(std::move(progress));
    }

    // A v1 progress file has no timestamp. Preserve an actual device reading
    // position over a freshly imported 0% App record during the first v2 sync.
    for (BizReadingProgress& progress : progressItems) {
      BizReadingProgress existing;
      if (!BizReadingProgressStore::load(progress.filename, existing)) continue;
      const bool existingHasPosition =
          existing.percentage > 0.0f || existing.spineIndex > 0 || existing.pageNumber > 0 || existing.pageCount > 0;
      const bool incomingIsUnopened = progress.percentage == 0.0f && progress.spineIndex == 0 &&
                                      progress.pageNumber == 0 && progress.pageCount == 0;
      if (existing.updatedAt == 0 && existingHasPosition && incomingIsUnopened) progress = existing;
    }

    if (!BizContentStore::saveJson(std::string(contentJson.c_str(), contentJson.length()), error)) return false;
    for (const BizReadingProgress& progress : progressItems) {
      if (!BizReadingProgressStore::save(progress)) {
        error = "Không lưu được tiến độ đọc";
        return false;
      }
    }
    applyDeviceConfig(snapshot["device"]);
    return true;
  }

  // App-pushed device configuration: optional top-level "device" object in the
  // pushed snapshot. Absent object = no change (older apps). Unknown keys are
  // ignored. Per-entry policy mirrors progress: a bad Wi-Fi entry is skipped
  // with a log and never fails the already-committed snapshot.
  void applyDeviceConfig(JsonVariantConst deviceVariant) {
    const JsonObjectConst device = deviceVariant.as<JsonObjectConst>();
    if (device.isNull()) return;

    const JsonObjectConst settingsObject = device["settings"].as<JsonObjectConst>();
    if (!settingsObject.isNull()) {
      const uint8_t previousTheme = SETTINGS.uiTheme;
      // Same key list, clamping and validation as the settings.json loader.
      // Absent keys keep their current values, so partial objects are fine.
      JsonSettingsIO::settingsFromJson(SETTINGS, settingsObject);
      if (!SETTINGS.saveToFile()) LOG_ERR("BIZ", "Failed to persist synced settings");
      if (SETTINGS.uiTheme != previousTheme) {
        // reload() destroys the current theme object, but rendering happens on
        // the render task ("ActivityManagerRender"), which may be mid-draw
        // through the GUI reference — this code runs on the main loop task,
        // NOT the rendering context. SettingsActivity's reload is only safe
        // because activity swaps hold the RenderLock, so do the same here.
        // No deadlock risk: this path (main.cpp loop -> BIZ_TRANSFER.loop ->
        // processCommand) never already holds the RenderLock, and the same
        // main task takes it elsewhere (screenshots, manual refresh).
        RenderLock lock;
        UITheme::getInstance().reload();
      }
      LOG_INF("BIZ", "Applied synced device settings");
    }

    size_t addedNetworks = 0;
    size_t removedNetworks = 0;
    size_t rejectedNetworks = 0;
    for (const JsonObjectConst entry : device["wifiAdd"].as<JsonArrayConst>()) {
      const char* ssid = entry["ssid"] | "";
      const char* password = entry["password"] | "";
      const size_t ssidLength = strlen(ssid);
      if (ssidLength == 0 || ssidLength > 32 || strlen(password) > 63) {
        LOG_ERR("BIZ", "Skipping invalid wifiAdd entry '%.32s'", ssid);
        ++rejectedNetworks;
        continue;
      }
      // addCredential updates an existing SSID in place, rejects new SSIDs
      // beyond MAX_NETWORKS (no eviction) and persists the store itself.
      if (WIFI_STORE.addCredential(ssid, password)) {
        ++addedNetworks;
      } else {
        LOG_ERR("BIZ", "Rejected wifi network '%.32s' (store full or save failed)", ssid);
        ++rejectedNetworks;
      }
    }
    for (const JsonVariantConst entry : device["wifiRemove"].as<JsonArrayConst>()) {
      const char* ssid = entry.as<const char*>();
      if (!ssid || ssid[0] == '\0') continue;
      // removeCredential persists on success; unknown SSIDs are a no-op.
      if (WIFI_STORE.removeCredential(ssid)) ++removedNetworks;
    }
    if (addedNetworks + removedNetworks + rejectedNetworks > 0) {
      LOG_INF("BIZ", "Synced Wi-Fi networks: %u added/updated, %u removed, %u rejected",
              static_cast<unsigned>(addedNetworks), static_cast<unsigned>(removedNetworks),
              static_cast<unsigned>(rejectedNetworks));
    }
  }

  // BLE-triggered Wi-Fi scan (op "wifi_scan"). Best-effort: on any failure the
  // status is re-published without the "scan" field. All scan fields are only
  // touched from the main task (processCommand / loop / prepareSyncSnapshot /
  // buildStatusJson all run there), so they need no lock.
  void startWifiScan() {
    // A new scan clears the previous session result from the status JSON.
    scanCompleted = false;
    scanResultCount = 0;
    scanWifiWasOff = (WiFi.getMode() == WIFI_MODE_NULL);
    WiFi.persistent(false);
    // scanNetworks(true) enables STA itself (WiFiScan.cpp: WiFi.enableSTA).
    if (WiFi.scanNetworks(true /*async*/) == WIFI_SCAN_FAILED) {
      LOG_ERR("BIZ", "WiFi scan failed to start");
      restoreRadioAfterScan();
      setStatus(state.load(), "Quét Wi-Fi thất bại");
      return;
    }
    scanInProgress = true;
    setStatus(state.load(), "Đang quét Wi-Fi");
  }

  // Turn the radio back off only if this scan turned it on and nothing else
  // needs it (no HTTP session, not mid Wi-Fi connect).
  void restoreRadioAfterScan() {
    if (!scanWifiWasOff || httpServer || state.load() == TransferState::Connecting) return;
    WiFi.disconnect(true, true);
    WiFi.mode(WIFI_OFF);
  }

  // <=15 entries, deduped by SSID keeping the strongest RSSI, hidden/empty
  // SSIDs skipped, sorted strongest-first.
  void collectScanResults(const int16_t found) {
    scanResultCount = 0;
    for (int16_t i = 0; i < found; ++i) {
      char ssid[33];
      strlcpy(ssid, WiFi.SSID(i).c_str(), sizeof(ssid));
      if (ssid[0] == '\0') continue;
      const int16_t rssi = static_cast<int16_t>(WiFi.RSSI(i));
      const bool secured = WiFi.encryptionType(i) != WIFI_AUTH_OPEN;
      size_t slot = scanResultCount;
      for (size_t j = 0; j < scanResultCount; ++j) {
        if (strcmp(wifiScanResults[j].ssid, ssid) == 0) {
          slot = j;
          break;
        }
      }
      if (slot < scanResultCount) {  // duplicate SSID: keep the strongest
        if (rssi <= wifiScanResults[slot].rssi) continue;
      } else if (scanResultCount < WIFI_SCAN_MAX_RESULTS) {
        slot = scanResultCount++;
      } else {  // pool full: replace the weakest entry if this one is stronger
        size_t weakest = 0;
        for (size_t j = 1; j < WIFI_SCAN_MAX_RESULTS; ++j) {
          if (wifiScanResults[j].rssi < wifiScanResults[weakest].rssi) weakest = j;
        }
        if (rssi <= wifiScanResults[weakest].rssi) continue;
        slot = weakest;
      }
      strlcpy(wifiScanResults[slot].ssid, ssid, sizeof(wifiScanResults[slot].ssid));
      wifiScanResults[slot].rssi = rssi;
      wifiScanResults[slot].secured = secured;
    }
    std::sort(wifiScanResults, wifiScanResults + scanResultCount,
              [](const WifiScanEntry& a, const WifiScanEntry& b) { return a.rssi > b.rssi; });
  }

  void pollWifiScan() {
    if (!scanInProgress) return;
    const int16_t found = WiFi.scanComplete();
    if (found == WIFI_SCAN_RUNNING) return;
    scanInProgress = false;
    if (found >= 0) {
      collectScanResults(found);
      scanCompleted = true;
      LOG_INF("BIZ", "WiFi scan found %d networks (%u kept)", found, static_cast<unsigned>(scanResultCount));
    } else {
      LOG_ERR("BIZ", "WiFi scan failed (%d)", found);
    }
    WiFi.scanDelete();
    restoreRadioAfterScan();
    // Publish only while still Idle: a session started mid-scan (e.g. "start"
    // aborted the scan) must keep its own state/message, matching the
    // Idle-only wifi_scan gating and the Idle-only "scan" status field.
    const TransferState currentState = state.load();
    if (currentState == TransferState::Idle) {
      setStatus(currentState, found >= 0 ? "Đã quét xong Wi-Fi" : "Quét Wi-Fi thất bại");
    }
  }

  void connectWifi(const char* ssid, const char* password) {
    if (httpServer) {
      httpServer->stop();
      httpServer.reset();
    }
    MDNS.end();
    token[0] = '\0';
    strlcpy(pendingSsid, ssid, sizeof(pendingSsid));
    strlcpy(pendingPassword, password, sizeof(pendingPassword));

    WiFi.persistent(false);
    WiFi.mode(WIFI_STA);
    WiFi.disconnect(true, true);
    delay(50);
    WiFi.setHostname(deviceName);
    WiFi.begin(pendingSsid, pendingPassword[0] == '\0' ? nullptr : pendingPassword);
    connectionStartedAt = millis();
    setStatus(TransferState::Connecting, "Đang kết nối Wi-Fi");
    LOG_INF("BIZ", "Connecting to saved Wi-Fi network");
  }

  void onWifiConnected() {
    WIFI_STORE.setLastConnectedSsid(pendingSsid);

    uint8_t randomBytes[TOKEN_BYTES];
    esp_fill_random(randomBytes, sizeof(randomBytes));
    for (size_t i = 0; i < sizeof(randomBytes); ++i) {
      snprintf(token + i * 2, 3, "%02x", randomBytes[i]);
    }
    token[TOKEN_BYTES * 2] = '\0';

    httpServer.reset(new (std::nothrow) WebServer(HTTP_PORT));
    if (!httpServer) {
      setStatus(TransferState::Error, "Không đủ bộ nhớ mở máy chủ");
      return;
    }

    const char* headers[] = {"X-BizReader-Token", "X-Content-SHA256", "Content-Length"};
    httpServer->collectHeaders(headers, 3);
    httpServer->on("/api/bizreader/status", HTTP_GET, [this] { handleHttpStatus(); });
    httpServer->on("/api/bizreader/progress", HTTP_GET, [this] { handleGetReadingProgress(); });
    httpServer->on("/api/bizreader/progress", HTTP_POST, [this] { handleSetReadingProgress(); });
    httpServer->on("/api/bizreader/content", HTTP_POST, [this] { handleSetContent(); });
    BizBookUploadHandler* uploadHandler = new (std::nothrow) BizBookUploadHandler(owner);
    if (!uploadHandler) {
      httpServer.reset();
      setStatus(TransferState::Error, "Không đủ bộ nhớ nhận sách");
      return;
    }
    httpServer->addHandler(uploadHandler);
    httpServer->onNotFound([this] { httpServer->send(404, "application/json", "{\"error\":\"not_found\"}"); });
    httpServer->begin();

    String hostname = deviceName;
    hostname.toLowerCase();
    if (MDNS.begin(hostname.c_str())) {
      MDNS.addService("http", "tcp", HTTP_PORT);
    }

    lastSessionActivityAt = millis();
    setStatus(TransferState::Ready, "Sẵn sàng nhận sách");
    LOG_INF("BIZ", "Transfer ready at http://%s/", WiFi.localIP().toString().c_str());
  }

  void handleHttpStatus() {
    if (!owner.authorize(httpServer->header("X-BizReader-Token"))) {
      httpServer->send(401, "application/json", "{\"error\":\"invalid_token\"}");
      return;
    }
    touchSession();
    char json[STATUS_BUFFER_SIZE];
    buildStatusJson(json, sizeof(json), true);
    httpServer->send(200, "application/json", json);
  }

  bool authorizeProgressRequest() {
    if (!owner.authorize(httpServer->header("X-BizReader-Token"))) {
      httpServer->send(401, "application/json", "{\"error\":\"invalid_token\"}");
      return false;
    }
    touchSession();
    return true;
  }

  void handleGetReadingProgress() {
    if (!authorizeProgressRequest()) return;
    const String filename = httpServer->arg("filename");
    if (filename.isEmpty() || filename.length() > 191 || filename.indexOf('/') >= 0) {
      httpServer->send(400, "application/json", "{\"error\":\"invalid_filename\"}");
      return;
    }

    BizReadingProgress progress;
    if (!BizReadingProgressStore::load(filename.c_str(), progress)) {
      httpServer->send(404, "application/json", "{\"error\":\"progress_not_found\"}");
      return;
    }

    JsonDocument document;
    document["filename"] = progress.filename;
    document["percentage"] = progress.percentage;
    document["spineIndex"] = progress.spineIndex;
    document["pageNumber"] = progress.pageNumber;
    document["pageCount"] = progress.pageCount;
    document["pending"] = progress.pending;
    document["updatedAt"] = progress.updatedAt;
    String json;
    serializeJson(document, json);
    httpServer->send(200, "application/json", json);
  }

  void handleSetReadingProgress() {
    if (!authorizeProgressRequest()) return;
    JsonDocument document;
    if (deserializeJson(document, httpServer->arg("plain"))) {
      httpServer->send(400, "application/json", "{\"error\":\"invalid_json\"}");
      return;
    }

    const String filename = document["filename"] | "";
    const float percentage = document["percentage"] | -1.0f;
    if (filename.isEmpty() || filename.length() > 191 || filename.indexOf('/') >= 0 || percentage < 0.0f ||
        percentage > 1.0f) {
      httpServer->send(400, "application/json", "{\"error\":\"invalid_progress\"}");
      return;
    }

    BizReadingProgress progress;
    progress.filename = filename.c_str();
    progress.percentage = percentage;
    progress.pending = true;
    progress.updatedAt = document["updatedAt"] | BizReadingProgressStore::nextTimestamp();
    if (!BizReadingProgressStore::save(progress)) {
      httpServer->send(500, "application/json", "{\"error\":\"save_failed\"}");
      return;
    }
    httpServer->send(200, "application/json", "{\"ok\":true,\"pending\":true}");
  }

  void handleSetContent() {
    if (!authorizeProgressRequest()) return;
    const String body = httpServer->arg("plain");
    std::string error;
    if (!BizContentStore::saveJson(std::string(body.c_str(), body.length()), error)) {
      const bool storageError = error == "write_failed" || error == "backup_failed" || error == "rename_failed";
      const int status = error == "content_too_large" ? 413 : (storageError ? 500 : 400);
      String response = "{\"error\":\"";
      response += error.c_str();
      response += "\"}";
      httpServer->send(status, "application/json", response);
      return;
    }
    httpServer->send(200, "application/json", "{\"ok\":true,\"direction\":\"app_to_device\"}");
  }

  void setStatus(TransferState newState, const char* newMessage) {
    state.store(newState);
    if (newState == TransferState::SyncReady) syncReadyAt = millis();
    strlcpy(message, newMessage ? newMessage : "", sizeof(message));
    publishStatus();
  }

  void buildStatusJson(char* output, size_t outputSize, bool includeToken) const {
    char safeFilename[STATUS_FILENAME_MAX + 1];
    JsonDocument document;
    document["protocol"] = 2;
    const TransferState currentState = state.load();
    document["state"] = stateName(currentState);
    document["device"] = deviceName;
    document["message"] = message;
    if (requestId[0] != '\0') document["request"] = requestId;
    if (WiFi.status() == WL_CONNECTED) {
      document["ip"] = WiFi.localIP().toString();
      document["port"] = HTTP_PORT;
    }
    if (includeToken && token[0] != '\0') document["token"] = token;
    if (uploadTotal > 0) {
      document["received"] = uploadReceived;
      document["total"] = uploadTotal;
    }
    if (lastFilename[0] != '\0') {
      copySanitizedFilename(lastFilename, safeFilename, sizeof(safeFilename));
      document["filename"] = safeFilename;
    }
    // No "sha256" field: the app verifies uploads via the X-Content-SHA256
    // HTTP header and the PUT response body; dropping it keeps the status
    // payload within the 512-byte ATT value cap.
    if (currentState == TransferState::SyncReady) {
      document["syncChunks"] = syncOutgoingChunks;
      document["syncSize"] = syncOutgoingSize;
    }
    // Present only while Idle after a scan completed this session; suppressed
    // in busy states (wifi_scan and sync_pull are refused there, so a stale
    // count would only short-circuit the app into a refused pull). Cleared on
    // service start and when a new scan begins. Absent after a failed scan.
    if (scanCompleted && currentState == TransferState::Idle) document["scan"] = scanResultCount;
    const size_t written = serializeJson(document, output, outputSize);
    // Unreachable by the arithmetic at STATUS_BUFFER_SIZE; a hit means a
    // field outgrew its documented bound.
    if (written + 1 >= outputSize) {
      LOG_ERR("BIZ", "Status JSON truncated (%u/%u bytes)", static_cast<unsigned>(written),
              static_cast<unsigned>(outputSize));
    }
  }

  void publishStatus() {
    if (!statusCharacteristic) return;
    char json[STATUS_BUFFER_SIZE];
    buildStatusJson(json, sizeof(json), true);
    statusCharacteristic->setValue(json);
    if (!bleConnected.load() || !bleServer) return;
    // READ_ENC does not gate notifications (NimBLE's auto-created CCCD is
    // plain read/write; see ble_gatts.c perm_flags): notify only peers with
    // an encrypted link so the token never reaches an unbonded subscriber.
    for (uint8_t i = 0; i < bleServer->getConnectedCount(); ++i) {
      const NimBLEConnInfo peer = bleServer->getPeerInfo(i);
      if (peer.isEncrypted()) statusCharacteristic->notify(peer.getConnHandle());
    }
  }

  bool authorize(const String& suppliedToken) const {
    return token[0] != '\0' && constantTimeEquals(suppliedToken, token);
  }

  void onUploadStarted(const String& uploadFilename, size_t total) {
    strlcpy(lastFilename, uploadFilename.c_str(), sizeof(lastFilename));
    lastSha256[0] = '\0';
    uploadReceived = 0;
    uploadTotal = total;
    touchSession();
    setStatus(TransferState::Uploading, "Đang nhận sách");
  }

  void onUploadProgress(size_t received, size_t total) {
    uploadReceived = received;
    uploadTotal = total;
    touchSession();
    publishStatus();
  }

  void onUploadFinished(const String& uploadFilename, size_t size, const char* sha256) {
    strlcpy(lastFilename, uploadFilename.c_str(), sizeof(lastFilename));
    strlcpy(lastSha256, sha256 ? sha256 : "", sizeof(lastSha256));
    uploadReceived = size;
    uploadTotal = size;
    touchSession();
    setStatus(TransferState::Complete, "Đã nhận sách");
  }

  void onUploadFailed(const char* errorMessage) {
    touchSession();
    setStatus(TransferState::Error, errorMessage ? errorMessage : "Nhận sách thất bại");
  }

  void touchSession() { lastSessionActivityAt = millis(); }

  // Main-task only (activity loop), same task as every writer above; the
  // atomic loads cover the BLE-callback-written flags.
  void getStatus(BizTransferService::Status& out) const {
    out.state = state.load();
    out.bleConnected = bleConnected.load();
    out.wifiScanning = scanInProgress;
    out.received = uploadReceived;
    out.total = uploadTotal;
    strlcpy(out.filename, lastFilename, sizeof(out.filename));
    strlcpy(out.message, message, sizeof(out.message));
  }

  BizTransferService& owner;
  ServerCallbacks serverCallbacks;
  CommandCallbacks commandCallbacks;
  SyncRxCallbacks syncRxCallbacks;
  SyncTxCallbacks syncTxCallbacks;
  NimBLEServer* bleServer = nullptr;
  NimBLECharacteristic* commandCharacteristic = nullptr;
  NimBLECharacteristic* statusCharacteristic = nullptr;
  NimBLECharacteristic* syncRxCharacteristic = nullptr;
  NimBLECharacteristic* syncTxCharacteristic = nullptr;
  std::unique_ptr<WebServer> httpServer;
  std::atomic<bool> bleConnected{false};
  std::atomic<bool> bleDisconnectedPending{false};
  std::atomic<bool> bleStopping{false};
  bool bleStarted = false;
  std::atomic<TransferState> state{TransferState::Idle};
  unsigned long connectionStartedAt = 0;
  unsigned long lastSessionActivityAt = 0;
  unsigned long syncReadyAt = 0;
  char deviceName[24] = "BizReader";
  char token[TOKEN_BYTES * 2 + 1] = {};
  char pendingSsid[33] = {};
  char pendingPassword[65] = {};
  char message[96] = {};
  char requestId[25] = {};
  char lastFilename[192] = {};
  char lastSha256[65] = {};
  size_t uploadReceived = 0;
  size_t uploadTotal = 0;
  portMUX_TYPE commandMux = portMUX_INITIALIZER_UNLOCKED;
  volatile bool commandPending = false;
  char pendingCommand[COMMAND_BUFFER_SIZE] = {};
  bool orphanSweepDone = false;
  // BLE-triggered Wi-Fi scan state; main-task only (no lock needed).
  bool scanInProgress = false;
  bool scanCompleted = false;
  bool scanWifiWasOff = false;
  size_t scanResultCount = 0;
  WifiScanEntry wifiScanResults[WIFI_SCAN_MAX_RESULTS] = {};
  mutable std::mutex syncMutex;
  std::atomic<unsigned long> syncLastActivityAt{0};
  std::unique_ptr<uint8_t[]> syncIncoming;
  size_t syncIncomingSize = 0;
  size_t syncIncomingReceived = 0;
  uint16_t syncIncomingChunks = 0;
  uint16_t syncExpectedSequence = 0;
  bool syncIncomingError = false;
  std::unique_ptr<uint8_t[]> syncOutgoing;
  size_t syncOutgoingSize = 0;
  size_t syncOutgoingOffset = 0;
  uint16_t syncOutgoingSequence = 0;
  uint16_t syncOutgoingChunks = 0;
  size_t syncOutgoingPayloadSize = SYNC_FRAME_PAYLOAD_SIZE;
};

#endif  // FREEINK_DEVICE_LILYGO_EPD47

BizTransferService& BizTransferService::getInstance() {
  static BizTransferService instance;
  return instance;
}

void BizTransferService::begin() {
#ifdef FREEINK_DEVICE_LILYGO_EPD47
  if (!impl) impl = new (std::nothrow) Impl(*this);
  if (impl) {
    impl->begin();
  } else {
    // No Impl means no state/message storage: getStatus() keeps returning a
    // zeroed Idle status, so a log line is the only signal available here.
    LOG_ERR("BIZ", "OOM: BizTransferService impl");
  }
#endif
}

void BizTransferService::loop() {
#ifdef FREEINK_DEVICE_LILYGO_EPD47
  if (impl) impl->loop();
#endif
}

void BizTransferService::stop() {
#ifdef FREEINK_DEVICE_LILYGO_EPD47
  if (impl) impl->stop();
#endif
}

void BizTransferService::getStatus(Status& out) const {
#ifdef FREEINK_DEVICE_LILYGO_EPD47
  if (impl) {
    impl->getStatus(out);
    return;
  }
#endif
  out = Status{};
}

bool BizTransferService::isBusy() const {
#ifdef FREEINK_DEVICE_LILYGO_EPD47
  if (!impl) return false;
  const TransferState currentState = impl->state.load();
  return currentState == TransferState::Connecting || currentState == TransferState::Ready ||
         currentState == TransferState::Uploading || currentState == TransferState::Complete ||
         currentState == TransferState::SyncReceiving ||
         (currentState == TransferState::SyncReady && millis() - impl->syncReadyAt < SYNC_READ_WINDOW_MS);
#else
  return false;
#endif
}

bool BizTransferService::isBleConnected() const {
#ifdef FREEINK_DEVICE_LILYGO_EPD47
  return impl && impl->bleConnected.load();
#else
  return false;
#endif
}

bool BizTransferService::shouldSkipLoopDelay() const {
#ifdef FREEINK_DEVICE_LILYGO_EPD47
  return impl && impl->httpServer != nullptr;
#else
  return false;
#endif
}

bool BizTransferService::authorize(const String& token) const {
#ifdef FREEINK_DEVICE_LILYGO_EPD47
  return impl && impl->authorize(token);
#else
  (void)token;
  return false;
#endif
}

void BizTransferService::onUploadStarted(const String& filename, const size_t total) {
#ifdef FREEINK_DEVICE_LILYGO_EPD47
  if (impl) impl->onUploadStarted(filename, total);
#else
  (void)filename;
  (void)total;
#endif
}

void BizTransferService::onUploadProgress(const size_t received, const size_t total) {
#ifdef FREEINK_DEVICE_LILYGO_EPD47
  if (impl) impl->onUploadProgress(received, total);
#else
  (void)received;
  (void)total;
#endif
}

void BizTransferService::onUploadFinished(const String& filename, const size_t size, const char* sha256) {
#ifdef FREEINK_DEVICE_LILYGO_EPD47
  if (impl) impl->onUploadFinished(filename, size, sha256);
#else
  (void)filename;
  (void)size;
  (void)sha256;
#endif
}

void BizTransferService::onUploadFailed(const char* message) {
#ifdef FREEINK_DEVICE_LILYGO_EPD47
  if (impl) impl->onUploadFailed(message);
#else
  (void)message;
#endif
}

void BizTransferService::touchSession() {
#ifdef FREEINK_DEVICE_LILYGO_EPD47
  if (impl) impl->touchSession();
#endif
}
