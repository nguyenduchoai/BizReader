#include "BizReadingProgressStore.h"

#include <ArduinoJson.h>
#include <HalStorage.h>
#include <Logging.h>

#include <algorithm>
#include <cstdint>
#include <ctime>

namespace {
constexpr char PROGRESS_DIRECTORY[] = "/.crosspoint/bizsync";

uint32_t fnv1a(const std::string& value) {
  uint32_t hash = 2166136261u;
  for (const unsigned char byte : value) {
    hash ^= byte;
    hash *= 16777619u;
  }
  return hash;
}
}  // namespace

std::string BizReadingProgressStore::filenameFromPath(const std::string& path) {
  const size_t slash = path.find_last_of('/');
  return slash == std::string::npos ? path : path.substr(slash + 1);
}

std::string BizReadingProgressStore::pathForFilename(const std::string& filename) {
  char hash[9];
  snprintf(hash, sizeof(hash), "%08lx", static_cast<unsigned long>(fnv1a(filename)));
  return std::string(PROGRESS_DIRECTORY) + "/" + hash + ".json";
}

bool BizReadingProgressStore::load(const std::string& filename, BizReadingProgress& progress) {
  if (filename.empty()) return false;
  const std::string path = pathForFilename(filename);
  if (!Storage.exists(path.c_str())) return false;

  const String json = Storage.readFile(path.c_str());
  JsonDocument document;
  const DeserializationError error = deserializeJson(document, json);
  if (error) {
    LOG_ERR("BIZ", "Cannot parse reading progress for %s: %s", filename.c_str(), error.c_str());
    return false;
  }

  const std::string storedFilename = document["filename"] | std::string();
  if (storedFilename != filename) {
    LOG_ERR("BIZ", "Reading progress hash collision for %s", filename.c_str());
    return false;
  }

  progress.filename = storedFilename;
  progress.percentage = std::clamp(document["percentage"] | 0.0f, 0.0f, 1.0f);
  progress.spineIndex = std::max(0, document["spineIndex"] | 0);
  progress.pageNumber = std::max(0, document["pageNumber"] | 0);
  progress.pageCount = std::max(0, document["pageCount"] | 0);
  progress.pending = document["pending"] | false;
  progress.updatedAt = document["updatedAt"] | uint64_t{0};
  return true;
}

bool BizReadingProgressStore::save(const BizReadingProgress& progress) {
  if (progress.filename.empty()) return false;
  Storage.mkdir(PROGRESS_DIRECTORY);

  JsonDocument document;
  document["filename"] = progress.filename;
  document["percentage"] = std::clamp(progress.percentage, 0.0f, 1.0f);
  document["spineIndex"] = std::max(0, progress.spineIndex);
  document["pageNumber"] = std::max(0, progress.pageNumber);
  document["pageCount"] = std::max(0, progress.pageCount);
  document["pending"] = progress.pending;
  document["updatedAt"] = progress.updatedAt;

  String json;
  serializeJson(document, json);
  return Storage.writeFile(pathForFilename(progress.filename).c_str(), json);
}

std::vector<BizReadingProgress> BizReadingProgressStore::list(const int maxItems) {
  std::vector<BizReadingProgress> result;
  for (const String& name : Storage.listFiles(PROGRESS_DIRECTORY, maxItems + 4)) {
    if (!name.endsWith(".json") || name == "content.json") continue;
    const std::string path = std::string(PROGRESS_DIRECTORY) + "/" + name.c_str();
    const String json = Storage.readFile(path.c_str());
    JsonDocument document;
    if (deserializeJson(document, json)) continue;
    const std::string filename = document["filename"] | std::string();
    BizReadingProgress progress;
    if (!filename.empty() && load(filename, progress)) result.push_back(progress);
    if (static_cast<int>(result.size()) >= maxItems) break;
  }
  return result;
}

uint64_t BizReadingProgressStore::nextTimestamp(const uint64_t previous) {
  const time_t now = time(nullptr);
  const uint64_t epochMs = now > 1700000000 ? static_cast<uint64_t>(now) * 1000ULL : 0;
  return std::max(epochMs, previous + 1);
}
