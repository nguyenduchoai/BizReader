#include "BizReadingProgressStore.h"

#include <ArduinoJson.h>
#include <HalClock.h>
#include <HalStorage.h>
#include <Logging.h>
#include <sys/time.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <ctime>
#include <unordered_set>

namespace {
constexpr char PROGRESS_DIRECTORY[] = "/.crosspoint/bizsync";
constexpr uint64_t MIN_VALID_EPOCH_SECONDS = 1700000000ULL;

uint32_t fnv1a(const std::string& value) {
  uint32_t hash = 2166136261u;
  for (const unsigned char byte : value) {
    hash ^= byte;
    hash *= 16777619u;
  }
  return hash;
}

int64_t daysFromCivil(int year, const unsigned month, const unsigned day) {
  year -= month <= 2;
  const int era = (year >= 0 ? year : year - 399) / 400;
  const unsigned yearOfEra = static_cast<unsigned>(year - era * 400);
  const unsigned adjustedMonth = month > 2 ? month - 3 : month + 9;
  const unsigned dayOfYear = (153 * adjustedMonth + 2) / 5 + day - 1;
  const unsigned dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear;
  return era * 146097LL + static_cast<int>(dayOfEra) - 719468LL;
}

bool systemClockValid() { return time(nullptr) > static_cast<time_t>(MIN_VALID_EPOCH_SECONDS); }

uint64_t currentEpochMs() {
  if (systemClockValid()) return static_cast<uint64_t>(time(nullptr)) * 1000ULL;

  uint16_t year = 0;
  uint8_t month = 0;
  uint8_t day = 0;
  uint8_t weekday = 0;
  uint8_t hour = 0;
  uint8_t minute = 0;
  if (!halClock.getDate(year, month, day, weekday) || !halClock.getTime(hour, minute) || year < 2023 || month < 1 ||
      month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59) {
    return 0;
  }

  const int64_t epochSeconds =
      daysFromCivil(year, month, day) * 86400LL + static_cast<int64_t>(hour) * 3600LL + minute * 60LL;
  return epochSeconds > static_cast<int64_t>(MIN_VALID_EPOCH_SECONDS) ? static_cast<uint64_t>(epochSeconds) * 1000ULL
                                                                      : 0;
}

bool parseProgressJson(const String& json, const std::string& expectedFilename, BizReadingProgress& progress) {
  JsonDocument document;
  if (deserializeJson(document, json)) return false;
  if (!document.is<JsonObjectConst>() || !document["filename"].is<const char*>() ||
      !document["percentage"].is<float>() || !document["spineIndex"].is<int>() || !document["pageNumber"].is<int>() ||
      !document["pageCount"].is<int>() || !document["pending"].is<bool>() ||
      (!document["updatedAt"].isNull() && !document["updatedAt"].is<uint64_t>())) {
    return false;
  }

  const std::string storedFilename = document["filename"] | std::string();
  if (storedFilename != expectedFilename) return false;

  const float percentage = document["percentage"] | -1.0f;
  const int spineIndex = document["spineIndex"] | -1;
  const int pageNumber = document["pageNumber"] | -1;
  const int pageCount = document["pageCount"] | -1;
  if (!std::isfinite(percentage) || percentage < 0.0f || percentage > 1.0f || spineIndex < 0 || pageNumber < 0 ||
      pageCount < 0) {
    return false;
  }

  progress.filename = storedFilename;
  progress.percentage = percentage;
  progress.spineIndex = spineIndex;
  progress.pageNumber = pageNumber;
  progress.pageCount = pageCount;
  progress.pending = document["pending"] | false;
  progress.updatedAt = document["updatedAt"] | uint64_t{0};
  return true;
}

bool parseProgressFile(const std::string& path, const std::string& filename, BizReadingProgress& progress) {
  if (!Storage.exists(path.c_str())) return false;
  return parseProgressJson(Storage.readFile(path.c_str()), filename, progress);
}

bool recoverProgressPath(const std::string& path, const std::string& filename) {
  const std::string temporaryPath = path + ".part";
  const std::string backupPath = path + ".bak";
  BizReadingProgress parsed;

  if (parseProgressFile(path, filename, parsed)) {
    Storage.remove(temporaryPath.c_str());
    Storage.remove(backupPath.c_str());
    return true;
  }

  if (parseProgressFile(backupPath, filename, parsed)) {
    Storage.remove(path.c_str());
    if (Storage.rename(backupPath.c_str(), path.c_str())) {
      Storage.remove(temporaryPath.c_str());
      return true;
    }
  }

  if (parseProgressFile(temporaryPath, filename, parsed)) {
    Storage.remove(path.c_str());
    if (Storage.rename(temporaryPath.c_str(), path.c_str())) {
      Storage.remove(backupPath.c_str());
      return true;
    }
  }
  return false;
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
  const bool hadCandidate = Storage.exists(path.c_str()) || Storage.exists((path + ".part").c_str()) ||
                            Storage.exists((path + ".bak").c_str());
  if (!recoverProgressPath(path, filename) || !parseProgressFile(path, filename, progress)) {
    if (hadCandidate) LOG_ERR("BIZ", "Cannot load reading progress for %s", filename.c_str());
    return false;
  }

  const String stored = Storage.readFile(path.c_str());
  JsonDocument document;
  const bool legacyTimestamp = !deserializeJson(document, stored) && document["updatedAt"].isNull();
  if (legacyTimestamp &&
      (progress.percentage > 0.0f || progress.spineIndex > 0 || progress.pageNumber > 0 || progress.pageCount > 0)) {
    const uint64_t migratedTimestamp = currentEpochMs();
    if (migratedTimestamp > 0) {
      progress.updatedAt = migratedTimestamp;
      if (!save(progress)) LOG_ERR("BIZ", "Cannot migrate reading progress timestamp for %s", filename.c_str());
    }
  }
  return true;
}

bool BizReadingProgressStore::save(const BizReadingProgress& progress) {
  if (progress.filename.empty() || progress.filename.size() > 191 || progress.filename.find('/') != std::string::npos ||
      progress.filename.find('\\') != std::string::npos) {
    return false;
  }
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
  const std::string path = pathForFilename(progress.filename);
  const std::string temporaryPath = path + ".part";
  const std::string backupPath = path + ".bak";
  recoverProgressPath(path, progress.filename);

  BizReadingProgress existing;
  if (Storage.exists(path.c_str()) && parseProgressFile(path, progress.filename, existing) == false) {
    JsonDocument existingDocument;
    if (!deserializeJson(existingDocument, Storage.readFile(path.c_str())) &&
        std::string(existingDocument["filename"] | "") != progress.filename) {
      LOG_ERR("BIZ", "Reading progress hash collision for %s", progress.filename.c_str());
      return false;
    }
  }

  Storage.remove(temporaryPath.c_str());
  if (!Storage.writeFile(temporaryPath.c_str(), json)) return false;

  Storage.remove(backupPath.c_str());
  const bool replacing = Storage.exists(path.c_str());
  if (replacing && !Storage.rename(path.c_str(), backupPath.c_str())) {
    Storage.remove(temporaryPath.c_str());
    return false;
  }
  if (!Storage.rename(temporaryPath.c_str(), path.c_str())) {
    if (replacing) Storage.rename(backupPath.c_str(), path.c_str());
    Storage.remove(temporaryPath.c_str());
    return false;
  }
  if (replacing) Storage.remove(backupPath.c_str());
  return true;
}

std::vector<BizReadingProgress> BizReadingProgressStore::list(const int maxItems) {
  std::vector<BizReadingProgress> result;
  std::unordered_set<std::string> seenFilenames;
  if (maxItems <= 0) return result;
  for (const String& name : Storage.listFiles(PROGRESS_DIRECTORY, maxItems * 3 + 4)) {
    if ((!name.endsWith(".json") && !name.endsWith(".json.part") && !name.endsWith(".json.bak")) ||
        name.startsWith("content.json")) {
      continue;
    }
    const std::string path = std::string(PROGRESS_DIRECTORY) + "/" + name.c_str();
    const String json = Storage.readFile(path.c_str());
    JsonDocument document;
    if (deserializeJson(document, json)) continue;
    const std::string filename = document["filename"] | std::string();
    if (!seenFilenames.insert(filename).second) continue;
    BizReadingProgress progress;
    if (!filename.empty() && load(filename, progress)) result.push_back(progress);
  }
  std::sort(result.begin(), result.end(), [](const BizReadingProgress& left, const BizReadingProgress& right) {
    if (left.updatedAt != right.updatedAt) return left.updatedAt > right.updatedAt;
    return left.filename < right.filename;
  });
  if (static_cast<int>(result.size()) > maxItems) result.resize(maxItems);
  return result;
}

uint64_t BizReadingProgressStore::nextTimestamp(const uint64_t previous) {
  const uint64_t incremented = previous == UINT64_MAX ? UINT64_MAX : previous + 1;
  return std::max(currentEpochMs(), incremented);
}

void BizReadingProgressStore::maybeAdoptExternalEpochMs(const uint64_t epochMs) {
  if (epochMs / 1000ULL <= MIN_VALID_EPOCH_SECONDS) return;  // implausible input
  if (systemClockValid()) return;                            // never override a valid clock
  timeval now{};
  now.tv_sec = static_cast<time_t>(epochMs / 1000ULL);
  now.tv_usec = static_cast<suseconds_t>((epochMs % 1000ULL) * 1000ULL);
  if (settimeofday(&now, nullptr) != 0) {
    LOG_ERR("BIZ", "settimeofday failed");
    return;
  }
  LOG_INF("BIZ", "Adopted external clock: %llu ms", static_cast<unsigned long long>(epochMs));

  // One-shot migration: records stamped by the counter fallback during the
  // dead-clock era get real timestamps, spaced to preserve their relative
  // order (epochMs >> maxCounter, so the subtraction cannot underflow).
  // Records with updatedAt == 0 are deliberately excluded: both sync sides
  // already treat 0 as "legacy, position wins" and must keep doing so.
  // Runs at most once per dead-clock episode — from here on systemClockValid()
  // is true and this function returns above.
  // ponytail: assumes counter-stamped device records are the newest activity;
  // loses phone progress in the mirror case (device sat un-synced while the
  // user read ahead on the phone) — accepted because counters only survive
  // while un-synced and device-then-connect is the dominant flow.
  constexpr uint64_t MIN_VALID_EPOCH_MS = MIN_VALID_EPOCH_SECONDS * 1000ULL;
  const std::vector<BizReadingProgress> records = list();
  uint64_t maxCounter = 0;
  for (const BizReadingProgress& record : records) {
    if (record.updatedAt > 0 && record.updatedAt < MIN_VALID_EPOCH_MS) {
      maxCounter = std::max(maxCounter, record.updatedAt);
    }
  }
  if (maxCounter == 0) return;
  for (const BizReadingProgress& record : records) {
    if (record.updatedAt == 0 || record.updatedAt >= MIN_VALID_EPOCH_MS) continue;
    BizReadingProgress migrated = record;
    migrated.updatedAt = epochMs - (maxCounter - record.updatedAt);
    if (!save(migrated)) {
      LOG_ERR("BIZ", "Cannot migrate counter timestamp for %s", migrated.filename.c_str());
    }
  }
}
