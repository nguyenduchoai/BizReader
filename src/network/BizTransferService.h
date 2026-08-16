#pragma once

#include <Arduino.h>

#include <cstddef>
#include <cstdint>

class BizTransferService {
 public:
  static constexpr const char* SERVICE_UUID = "7d2f1000-8d4f-4f5b-a8d0-53b495a9b001";
  static constexpr const char* COMMAND_UUID = "7d2f1001-8d4f-4f5b-a8d0-53b495a9b001";
  static constexpr const char* STATUS_UUID = "7d2f1002-8d4f-4f5b-a8d0-53b495a9b001";
  static constexpr const char* INFO_UUID = "7d2f1003-8d4f-4f5b-a8d0-53b495a9b001";
  static constexpr const char* SYNC_RX_UUID = "7d2f1004-8d4f-4f5b-a8d0-53b495a9b001";
  static constexpr const char* SYNC_TX_UUID = "7d2f1005-8d4f-4f5b-a8d0-53b495a9b001";

  static BizTransferService& getInstance();

  // Transfer state machine, mirrored 1:1 by the "state" strings in the BLE
  // status JSON ("idle", "connecting", ...). Public so the Connect-App screen
  // can render a live status line per state.
  enum class State : uint8_t { Idle, Connecting, Ready, Uploading, Complete, SyncReceiving, SyncReady, Error };

  // Snapshot for on-screen display. Fill via getStatus() from the main task
  // (the activity loop), which is the same task that mutates the underlying
  // fields (service loop / handleClient), so plain copies are race-free.
  struct Status {
    State state = State::Idle;
    bool bleConnected = false;
    bool wifiScanning = false;
    size_t received = 0;
    size_t total = 0;
    char filename[192] = {};
    // Vietnamese status/error text as published to the app; shown verbatim.
    char message[96] = {};
  };

  void begin();
  void loop();
  void stop();

  void getStatus(Status& out) const;
  bool isBusy() const;
  bool isBleConnected() const;
  bool shouldSkipLoopDelay() const;

  bool authorize(const String& token) const;
  void onUploadStarted(const String& filename, size_t total);
  void onUploadProgress(size_t received, size_t total);
  void onUploadFinished(const String& filename, size_t size, const char* sha256);
  void onUploadFailed(const char* message);
  void touchSession();

 private:
  BizTransferService() = default;
  BizTransferService(const BizTransferService&) = delete;
  BizTransferService& operator=(const BizTransferService&) = delete;

  class Impl;
  Impl* impl = nullptr;
};

#define BIZ_TRANSFER BizTransferService::getInstance()
