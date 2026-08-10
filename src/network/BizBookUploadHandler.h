#pragma once

#include <HalStorage.h>
#include <WebServer.h>
#include <mbedtls/sha256.h>

class BizTransferService;

class BizBookUploadHandler final : public RequestHandler {
 public:
  explicit BizBookUploadHandler(BizTransferService& transferService) : transferService(transferService) {}
  ~BizBookUploadHandler() override;

  bool canHandle(WebServer& server, HTTPMethod method, const String& uri) override;
  bool canRaw(WebServer& server, const String& uri) override;
  void raw(WebServer& server, const String& uri, HTTPRaw& raw) override;
  bool handle(WebServer& server, HTTPMethod method, const String& uri) override;

 private:
  static constexpr size_t MAX_BOOK_SIZE = 128UL * 1024UL * 1024UL;
  static constexpr size_t MAX_WALLPAPER_SIZE = 8UL * 1024UL * 1024UL;

  BizTransferService& transferService;
  HalFile uploadFile;
  String targetPath;
  String temporaryPath;
  String filename;
  String expectedSha256;
  String actualSha256;
  size_t expectedSize = 0;
  size_t receivedSize = 0;
  size_t lastProgressSize = 0;
  int responseCode = 500;
  const char* responseMessage = "Upload failed";
  bool uploadOk = false;
  bool shaStarted = false;
  mbedtls_sha256_context shaContext{};

  bool isAuthorized(WebServer& server) const;
  bool preparePath(const String& uri);
  bool isAllowedExtension(const String& path) const;
  void abortUpload();
  void finishUpload();
};
