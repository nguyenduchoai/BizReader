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

  static BizTransferService& getInstance();

  void begin();
  void loop();
  void stop();
  void pauseForManualTransfer();
  void resumeAfterManualTransfer();

  bool isBusy() const;
  bool shouldSkipLoopDelay() const;
  bool takePairingPasskey(uint32_t& passkey);
  bool takePairingFinished();

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
