#include "BizBookUploadHandler.h"

#include <Logging.h>
#include <esp_task_wdt.h>

#include <cctype>

#include "BizTransferService.h"

namespace {
constexpr size_t PROGRESS_INTERVAL = 64UL * 1024UL;

bool equalsIgnoreCase(const String& left, const String& right) {
  if (left.length() != right.length()) return false;
  for (size_t i = 0; i < left.length(); ++i) {
    if (std::tolower(static_cast<unsigned char>(left[i])) != std::tolower(static_cast<unsigned char>(right[i]))) {
      return false;
    }
  }
  return true;
}
}  // namespace

BizBookUploadHandler::~BizBookUploadHandler() { abortUpload(); }

bool BizBookUploadHandler::canHandle(WebServer& server, const HTTPMethod method, const String& uri) {
  (void)server;
  return (method == HTTP_PUT && uri.startsWith("/Ebook/")) || (method == HTTP_OPTIONS && uri == "/api/bizreader");
}

bool BizBookUploadHandler::canRaw(WebServer& server, const String& uri) {
  return server.method() == HTTP_PUT && uri.startsWith("/Ebook/");
}

bool BizBookUploadHandler::isAuthorized(WebServer& server) const {
  return transferService.authorize(server.header("X-BizReader-Token"));
}

bool BizBookUploadHandler::isAllowedExtension(const String& path) const {
  String lower = path;
  lower.toLowerCase();
  return lower.endsWith(".epub") || lower.endsWith(".txt") || lower.endsWith(".xtc") || lower.endsWith(".xtch") ||
         lower.endsWith(".bmp");
}

bool BizBookUploadHandler::preparePath(const String& uri) {
  targetPath = WebServer::urlDecode(uri);
  if (!targetPath.startsWith("/Ebook/") || targetPath.length() > 480 || targetPath.indexOf("..") >= 0 ||
      targetPath.indexOf('\\') >= 0 || !isAllowedExtension(targetPath)) {
    responseCode = 400;
    responseMessage = "Invalid book path";
    return false;
  }

  filename = targetPath.substring(targetPath.lastIndexOf('/') + 1);
  if (filename.isEmpty() || filename.startsWith(".")) {
    responseCode = 400;
    responseMessage = "Invalid filename";
    return false;
  }

  temporaryPath = targetPath + ".part";
  return true;
}

void BizBookUploadHandler::abortUpload() {
  if (uploadFile) uploadFile.close();
  if (!temporaryPath.isEmpty() && Storage.exists(temporaryPath.c_str())) {
    Storage.remove(temporaryPath.c_str());
  }
  if (shaStarted) {
    mbedtls_sha256_free(&shaContext);
    shaStarted = false;
  }
  uploadOk = false;
}

void BizBookUploadHandler::raw(WebServer& server, const String& uri, HTTPRaw& raw) {
  if (raw.status == RAW_START) {
    abortUpload();
    targetPath.clear();
    temporaryPath.clear();
    filename.clear();
    actualSha256.clear();
    expectedSha256 = server.header("X-Content-SHA256");
    expectedSize = static_cast<size_t>(server.header("Content-Length").toInt());
    receivedSize = 0;
    lastProgressSize = 0;
    responseCode = 500;
    responseMessage = "Upload failed";

    if (!isAuthorized(server)) {
      responseCode = 401;
      responseMessage = "Invalid transfer token";
      return;
    }
    if (expectedSize == 0 || expectedSize > MAX_BOOK_SIZE) {
      responseCode = 413;
      responseMessage = "Book is empty or too large";
      return;
    }
    if (!expectedSha256.isEmpty() && expectedSha256.length() != 64) {
      responseCode = 400;
      responseMessage = "Invalid SHA-256 header";
      return;
    }
    if (!preparePath(uri)) return;

    Storage.mkdir("/Ebook");
    Storage.remove(temporaryPath.c_str());
    if (!Storage.openFileForWrite("BIZ", temporaryPath, uploadFile)) {
      responseCode = 507;
      responseMessage = "Cannot write to SD card";
      return;
    }

    mbedtls_sha256_init(&shaContext);
    if (mbedtls_sha256_starts(&shaContext, 0) != 0) {
      responseCode = 500;
      responseMessage = "Cannot initialize SHA-256";
      abortUpload();
      return;
    }
    shaStarted = true;
    uploadOk = true;
    responseCode = 201;
    responseMessage = "Created";
    transferService.onUploadStarted(filename, expectedSize);
    LOG_INF("BIZ", "Upload start: %s (%u bytes)", filename.c_str(), static_cast<unsigned>(expectedSize));
    return;
  }

  if (raw.status == RAW_WRITE) {
    if (!uploadOk || !uploadFile) return;
    if (receivedSize + raw.currentSize > expectedSize || receivedSize + raw.currentSize > MAX_BOOK_SIZE) {
      responseCode = 413;
      responseMessage = "Upload exceeds declared size";
      abortUpload();
      transferService.onUploadFailed(responseMessage);
      return;
    }

    esp_task_wdt_reset();
    const size_t written = uploadFile.write(raw.buf, raw.currentSize);
    if (written != raw.currentSize || mbedtls_sha256_update(&shaContext, raw.buf, raw.currentSize) != 0) {
      responseCode = 507;
      responseMessage = "SD card write failed";
      abortUpload();
      transferService.onUploadFailed(responseMessage);
      return;
    }

    receivedSize += written;
    transferService.touchSession();
    if (receivedSize - lastProgressSize >= PROGRESS_INTERVAL || receivedSize == expectedSize) {
      lastProgressSize = receivedSize;
      transferService.onUploadProgress(receivedSize, expectedSize);
    }
    return;
  }

  if (raw.status == RAW_END) {
    finishUpload();
    return;
  }

  if (raw.status == RAW_ABORTED) {
    responseCode = 499;
    responseMessage = "Upload cancelled";
    abortUpload();
    transferService.onUploadFailed(responseMessage);
  }
}

void BizBookUploadHandler::finishUpload() {
  if (!uploadOk || !uploadFile || !shaStarted) return;

  uploadFile.flush();
  uploadFile.close();

  uint8_t digest[32];
  if (mbedtls_sha256_finish(&shaContext, digest) != 0) {
    responseCode = 500;
    responseMessage = "SHA-256 failed";
    abortUpload();
    transferService.onUploadFailed(responseMessage);
    return;
  }
  mbedtls_sha256_free(&shaContext);
  shaStarted = false;

  char digestHex[65];
  for (size_t i = 0; i < sizeof(digest); ++i) {
    snprintf(digestHex + i * 2, 3, "%02x", digest[i]);
  }
  digestHex[64] = '\0';
  actualSha256 = digestHex;

  if (receivedSize != expectedSize) {
    responseCode = 400;
    responseMessage = "Upload size mismatch";
    abortUpload();
    transferService.onUploadFailed(responseMessage);
    return;
  }
  if (!expectedSha256.isEmpty() && !equalsIgnoreCase(expectedSha256, actualSha256)) {
    responseCode = 422;
    responseMessage = "SHA-256 mismatch";
    abortUpload();
    transferService.onUploadFailed(responseMessage);
    return;
  }

  const String backupPath = targetPath + ".bak";
  if (Storage.exists(backupPath.c_str())) {
    if (!Storage.exists(targetPath.c_str())) {
      if (!Storage.rename(backupPath.c_str(), targetPath.c_str())) {
        responseCode = 500;
        responseMessage = "Cannot restore existing book";
        abortUpload();
        transferService.onUploadFailed(responseMessage);
        return;
      }
    } else {
      Storage.remove(backupPath.c_str());
    }
  }
  const bool replacingExisting = Storage.exists(targetPath.c_str());
  if (replacingExisting && !Storage.rename(targetPath.c_str(), backupPath.c_str())) {
    responseCode = 500;
    responseMessage = "Cannot preserve existing book";
    abortUpload();
    transferService.onUploadFailed(responseMessage);
    return;
  }
  if (!Storage.rename(temporaryPath.c_str(), targetPath.c_str())) {
    if (replacingExisting) Storage.rename(backupPath.c_str(), targetPath.c_str());
    responseCode = 500;
    responseMessage = "Cannot finalize book";
    abortUpload();
    transferService.onUploadFailed(responseMessage);
    return;
  }
  if (replacingExisting) Storage.remove(backupPath.c_str());

  uploadOk = false;
  temporaryPath.clear();
  responseCode = 201;
  responseMessage = "Created";
  transferService.onUploadFinished(filename, receivedSize, actualSha256.c_str());
  LOG_INF("BIZ", "Upload complete: %s (%u bytes, sha256=%s)", filename.c_str(), static_cast<unsigned>(receivedSize),
          actualSha256.c_str());
}

bool BizBookUploadHandler::handle(WebServer& server, const HTTPMethod method, const String& uri) {
  if (method == HTTP_OPTIONS) {
    if (!isAuthorized(server)) {
      server.send(401, "application/json", "{\"error\":\"invalid_token\"}");
      return true;
    }
    server.sendHeader("Allow", "OPTIONS, PUT");
    server.send(204);
    return true;
  }

  if (method != HTTP_PUT || !uri.startsWith("/Ebook/")) return false;

  String response = "{\"ok\":";
  response += responseCode >= 200 && responseCode < 300 ? "true" : "false";
  response += ",\"message\":\"";
  response += responseMessage;
  response += "\",\"size\":";
  response += String(receivedSize);
  if (!actualSha256.isEmpty()) {
    response += ",\"sha256\":\"";
    response += actualSha256;
    response += "\"";
  }
  response += "}";
  server.send(responseCode, "application/json", response);
  return true;
}
