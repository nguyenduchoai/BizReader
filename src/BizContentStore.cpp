#include "BizContentStore.h"

#include <ArduinoJson.h>
#include <HalStorage.h>
#include <Logging.h>

#include <algorithm>
#include <ctime>

namespace {
constexpr char DIRECTORY[] = "/.crosspoint/bizsync";

std::string limited(const JsonVariantConst value, const size_t maxLength) {
  const char* text = value | "";
  std::string result = text ? text : "";
  if (result.size() > maxLength) {
    size_t cut = maxLength;
    while (cut > 0 && (static_cast<unsigned char>(result[cut]) & 0xC0) == 0x80) --cut;
    result.resize(cut);
  }
  return result;
}

bool validateDocument(const JsonDocument& document, std::string& error) {
  const int version = document["version"] | 0;
  if (version != 1 && version != 2) {
    error = "unsupported_version";
    return false;
  }
  if (!document["notes"].is<JsonArrayConst>() || !document["todos"].is<JsonArrayConst>() ||
      !document["events"].is<JsonArrayConst>() || !document["weather"].is<JsonObjectConst>() ||
      !document["sleep"].is<JsonObjectConst>()) {
    error = "invalid_content_shape";
    return false;
  }
  if (document["notes"].size() > 40 || document["todos"].size() > 60 || document["events"].size() > 60) {
    error = "too_many_items";
    return false;
  }
  if (version >= 2 &&
      (!document["deleted"].is<JsonObjectConst>() || !document["deleted"]["notes"].is<JsonArrayConst>() ||
       !document["deleted"]["todos"].is<JsonArrayConst>())) {
    error = "invalid_deleted_shape";
    return false;
  }
  if (version >= 2) {
    if (document["deleted"]["notes"].size() > 80 || document["deleted"]["todos"].size() > 120) {
      error = "too_many_tombstones";
      return false;
    }
  }
  const std::string mode = document["sleep"]["mode"] | "calendar";
  if (mode != "calendar" && mode != "photo") {
    error = "invalid_sleep_mode";
    return false;
  }
  return true;
}

uint64_t nextTimestamp(const uint64_t previous) {
  const time_t now = time(nullptr);
  const uint64_t epochMs = now > 1700000000 ? static_cast<uint64_t>(now) * 1000ULL : 0;
  return std::max(epochMs, previous + 1);
}
}  // namespace

bool BizContentStore::saveJson(const std::string& json, std::string& error) {
  if (json.empty() || json.size() > MAX_JSON_SIZE) {
    error = "content_too_large";
    return false;
  }
  JsonDocument document;
  const DeserializationError parseError = deserializeJson(document, json);
  if (parseError) {
    error = "invalid_json";
    return false;
  }
  if (!validateDocument(document, error)) return false;

  Storage.mkdir(DIRECTORY);
  const std::string temporaryPath = std::string(PATH) + ".part";
  Storage.remove(temporaryPath.c_str());
  if (!Storage.writeFile(temporaryPath.c_str(), String(json.c_str()))) {
    error = "write_failed";
    return false;
  }
  const std::string backupPath = std::string(PATH) + ".bak";
  Storage.remove(backupPath.c_str());
  const bool replacing = Storage.exists(PATH);
  if (replacing && !Storage.rename(PATH, backupPath.c_str())) {
    Storage.remove(temporaryPath.c_str());
    error = "backup_failed";
    return false;
  }
  if (!Storage.rename(temporaryPath.c_str(), PATH)) {
    if (replacing) Storage.rename(backupPath.c_str(), PATH);
    Storage.remove(temporaryPath.c_str());
    error = "rename_failed";
    return false;
  }
  if (replacing) Storage.remove(backupPath.c_str());
  if (std::string(document["sleep"]["mode"] | "calendar") == "calendar") Storage.remove("/sleep.bmp");
  return true;
}

bool BizContentStore::load(BizContentData& data) {
  data = {};
  if (!Storage.exists(PATH)) return false;
  const String json = Storage.readFile(PATH);
  JsonDocument document;
  std::string error;
  if (deserializeJson(document, json) || !validateDocument(document, error)) {
    LOG_ERR("BIZ", "Cannot load content snapshot: %s", error.c_str());
    return false;
  }

  data.updatedAt = document["updatedAt"] | uint64_t{0};
  data.sleepMode = document["sleep"]["mode"] | "calendar";
  const JsonObjectConst weather = document["weather"].as<JsonObjectConst>();
  data.weather.location = limited(weather["location"], 80);
  data.weather.condition = limited(weather["condition"], 80);
  data.weather.temperature = std::clamp(weather["temperature"] | 0, -99, 99);
  data.weather.high = std::clamp(weather["high"] | 0, -99, 99);
  data.weather.low = std::clamp(weather["low"] | 0, -99, 99);

  for (const JsonObjectConst item : document["notes"].as<JsonArrayConst>()) {
    data.notes.push_back({limited(item["id"], 80), limited(item["title"], 120), limited(item["body"], 600),
                          item["updatedAt"] | uint64_t{0}});
  }
  for (const JsonObjectConst item : document["todos"].as<JsonArrayConst>()) {
    data.todos.push_back({limited(item["id"], 80), limited(item["title"], 140), limited(item["due"], 60),
                          item["done"] | false, item["updatedAt"] | uint64_t{0}});
  }
  if (document["deleted"].is<JsonObjectConst>()) {
    for (const JsonObjectConst item : document["deleted"]["notes"].as<JsonArrayConst>()) {
      data.deletedNotes.push_back({limited(item["id"], 80), item["updatedAt"] | uint64_t{0}});
    }
    for (const JsonObjectConst item : document["deleted"]["todos"].as<JsonArrayConst>()) {
      data.deletedTodos.push_back({limited(item["id"], 80), item["updatedAt"] | uint64_t{0}});
    }
  }
  for (const JsonObjectConst item : document["events"].as<JsonArrayConst>()) {
    data.events.push_back({limited(item["title"], 140), limited(item["date"], 10), limited(item["time"], 5),
                           limited(item["location"], 100)});
  }
  return true;
}

bool BizContentStore::loadJson(std::string& json) {
  json.clear();
  if (!Storage.exists(PATH)) return false;
  const String stored = Storage.readFile(PATH);
  if (stored.isEmpty()) return false;
  json.assign(stored.c_str(), stored.length());
  return true;
}

bool BizContentStore::toggleTodo(const std::string& id) {
  if (id.empty() || !Storage.exists(PATH)) return false;
  const String stored = Storage.readFile(PATH);
  JsonDocument document;
  std::string error;
  if (deserializeJson(document, stored) || !validateDocument(document, error)) return false;

  const uint64_t timestamp = nextTimestamp(document["updatedAt"] | uint64_t{0});
  bool found = false;
  for (JsonObject item : document["todos"].as<JsonArray>()) {
    if (std::string(item["id"] | "") != id) continue;
    item["done"] = !(item["done"] | false);
    item["updatedAt"] = timestamp;
    found = true;
    break;
  }
  if (!found) return false;

  document["version"] = 2;
  document["updatedAt"] = timestamp;
  if (!document["deleted"].is<JsonObject>()) {
    JsonObject deleted = document["deleted"].to<JsonObject>();
    deleted["notes"].to<JsonArray>();
    deleted["todos"].to<JsonArray>();
  }
  String json;
  serializeJson(document, json);
  return saveJson(std::string(json.c_str(), json.length()), error);
}
