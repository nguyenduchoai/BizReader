#include "BizTransferService.h"

#ifdef FREEINK_DEVICE_LILYGO_EPD47

#include <ArduinoJson.h>
#include <ESPmDNS.h>
#include <HalStorage.h>
#include <Logging.h>
#include <NimBLEDevice.h>
#include <WebServer.h>
#include <WiFi.h>
#include <esp_system.h>
#include <esp_task_wdt.h>

#include <atomic>
#include <cstring>
#include <memory>
#include <new>

#include "BizBookUploadHandler.h"
#include "BizContentStore.h"
#include "BizReadingProgressStore.h"
#include "WifiCredentialStore.h"

namespace {
constexpr uint16_t HTTP_PORT = 80;
constexpr unsigned long WIFI_CONNECT_TIMEOUT_MS = 20000;
constexpr unsigned long TRANSFER_IDLE_TIMEOUT_MS = 5UL * 60UL * 1000UL;
constexpr size_t COMMAND_BUFFER_SIZE = 256;
constexpr size_t STATUS_BUFFER_SIZE = 512;
constexpr size_t TOKEN_BYTES = 16;

enum class TransferState : uint8_t { Idle, Connecting, Ready, Uploading, Complete, Error };

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
    case TransferState::Error:
      return "error";
    case TransferState::Idle:
    default:
      return "idle";
  }
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
  explicit Impl(BizTransferService& owner) : owner(owner), serverCallbacks(*this), commandCallbacks(*this) {}

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
      LOG_INF("BIZ", "BLE client disconnected (reason=%d)", reason);
      NimBLEDevice::startAdvertising();
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

  void begin() {
    if (bleStarted) return;

    WIFI_STORE.loadFromFile();

    uint8_t mac[6];
    WiFi.macAddress(mac);
    snprintf(deviceName, sizeof(deviceName), "BizReader-%02X%02X", mac[4], mac[5]);
    NimBLEDevice::init(deviceName);
    NimBLEDevice::setPower(3);

    bleServer = NimBLEDevice::createServer();
    if (!bleServer) {
      LOG_ERR("BIZ", "Cannot create BLE server");
      NimBLEDevice::deinit();
      return;
    }
    bleServer->setCallbacks(&serverCallbacks);

    NimBLEService* service = bleServer->createService(BizTransferService::SERVICE_UUID);
    if (!service) {
      LOG_ERR("BIZ", "Cannot create BLE service");
      NimBLEDevice::deinit();
      bleServer = nullptr;
      return;
    }

    commandCharacteristic = service->createCharacteristic(BizTransferService::COMMAND_UUID, NIMBLE_PROPERTY::WRITE,
                                                          COMMAND_BUFFER_SIZE - 1);
    statusCharacteristic = service->createCharacteristic(
        BizTransferService::STATUS_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY, STATUS_BUFFER_SIZE - 1);
    NimBLECharacteristic* infoCharacteristic =
        service->createCharacteristic(BizTransferService::INFO_UUID, NIMBLE_PROPERTY::READ, 96);

    if (!commandCharacteristic || !statusCharacteristic || !infoCharacteristic) {
      LOG_ERR("BIZ", "Cannot create BLE characteristics");
      NimBLEDevice::deinit();
      bleServer = nullptr;
      commandCharacteristic = nullptr;
      statusCharacteristic = nullptr;
      return;
    }

    commandCharacteristic->setCallbacks(&commandCallbacks);
    infoCharacteristic->setValue("{\"protocol\":1,\"transport\":\"wifi-http\",\"folder\":\"/Ebook\"}");
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
    stopTransfer();
    if (bleStarted) {
      NimBLEDevice::deinit();
      bleStarted = false;
      bleServer = nullptr;
      commandCharacteristic = nullptr;
      statusCharacteristic = nullptr;
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
    setStatus(TransferState::Idle, "Đã tắt truyền sách");
  }

  void loop() {
    char command[COMMAND_BUFFER_SIZE] = {};
    portENTER_CRITICAL(&commandMux);
    if (commandPending) {
      strlcpy(command, pendingCommand, sizeof(command));
      commandPending = false;
    }
    portEXIT_CRITICAL(&commandMux);
    if (command[0] != '\0') processCommand(command);

    if (state == TransferState::Connecting) {
      if (WiFi.status() == WL_CONNECTED) {
        onWifiConnected();
      } else if (millis() - connectionStartedAt >= WIFI_CONNECT_TIMEOUT_MS) {
        WiFi.disconnect(true, true);
        WiFi.mode(WIFI_OFF);
        setStatus(TransferState::Error, "Không kết nối được Wi-Fi");
      }
    }

    if (httpServer) {
      for (int i = 0; i < 32; ++i) {
        httpServer->handleClient();
        if ((i & 0x07) == 0x07) {
          esp_task_wdt_reset();
          yield();
        }
      }

      if (state != TransferState::Uploading && millis() - lastSessionActivityAt >= TRANSFER_IDLE_TIMEOUT_MS) {
        LOG_INF("BIZ", "Transfer window expired");
        stopTransfer();
      }
    }
  }

  void processCommand(const char* command) {
    JsonDocument document;
    const DeserializationError error = deserializeJson(document, command);
    if (error) {
      requestId[0] = '\0';
      setStatus(TransferState::Error, "Lệnh BLE không hợp lệ");
      return;
    }

    const char* incomingRequestId = document["request"] | "";
    if (strlen(incomingRequestId) > 24) {
      requestId[0] = '\0';
      setStatus(TransferState::Error, "Mã yêu cầu không hợp lệ");
      return;
    }
    strlcpy(requestId, incomingRequestId, sizeof(requestId));

    const char* operation = document["op"] | "";
    if (strcmp(operation, "ping") == 0) {
      publishStatus();
      return;
    }
    if (strcmp(operation, "stop") == 0) {
      stopTransfer();
      return;
    }
    if (strcmp(operation, "start") == 0) {
      const std::string& lastSsid = WIFI_STORE.getLastConnectedSsid();
      const WifiCredential* credential = WIFI_STORE.findCredential(lastSsid);
      if (lastSsid.empty() || !credential) {
        setStatus(TransferState::Error, "Hãy lưu Wi-Fi trên BizReader trước");
        return;
      }
      connectWifi(credential->ssid.c_str(), credential->password.c_str());
      return;
    }

    setStatus(TransferState::Error, "Lệnh BLE không được hỗ trợ");
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
    LOG_INF("BIZ", "Connecting to Wi-Fi: %s", pendingSsid);
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
    state = newState;
    strlcpy(message, newMessage ? newMessage : "", sizeof(message));
    publishStatus();
  }

  void buildStatusJson(char* output, size_t outputSize, bool includeToken) const {
    JsonDocument document;
    document["protocol"] = 1;
    document["state"] = stateName(state);
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
    if (lastFilename[0] != '\0') document["filename"] = lastFilename;
    if (lastSha256[0] != '\0') document["sha256"] = lastSha256;
    serializeJson(document, output, outputSize);
  }

  void publishStatus() {
    if (!statusCharacteristic) return;
    char json[STATUS_BUFFER_SIZE];
    buildStatusJson(json, sizeof(json), true);
    statusCharacteristic->setValue(json);
    if (bleConnected.load()) statusCharacteristic->notify();
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

  BizTransferService& owner;
  ServerCallbacks serverCallbacks;
  CommandCallbacks commandCallbacks;
  NimBLEServer* bleServer = nullptr;
  NimBLECharacteristic* commandCharacteristic = nullptr;
  NimBLECharacteristic* statusCharacteristic = nullptr;
  std::unique_ptr<WebServer> httpServer;
  std::atomic<bool> bleConnected{false};
  bool bleStarted = false;
  TransferState state = TransferState::Idle;
  unsigned long connectionStartedAt = 0;
  unsigned long lastSessionActivityAt = 0;
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
};

#endif  // FREEINK_DEVICE_LILYGO_EPD47

BizTransferService& BizTransferService::getInstance() {
  static BizTransferService instance;
  return instance;
}

void BizTransferService::begin() {
#ifdef FREEINK_DEVICE_LILYGO_EPD47
  if (!impl) impl = new (std::nothrow) Impl(*this);
  if (impl) impl->begin();
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

bool BizTransferService::isBusy() const {
#ifdef FREEINK_DEVICE_LILYGO_EPD47
  return impl && (impl->state == TransferState::Connecting || impl->state == TransferState::Ready ||
                  impl->state == TransferState::Uploading || impl->state == TransferState::Complete);
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
