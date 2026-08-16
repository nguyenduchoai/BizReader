#pragma once

#include <ArduinoJson.h>

#include <vector>

class CrossPointSettings;
class CrossPointState;
class WifiCredentialStore;
class RecentBooksStore;
class OpdsServerStore;
struct BookmarkEntry;

namespace JsonSettingsIO {

// CrossPointSettings
bool saveSettings(const CrossPointSettings& s, const char* path);
bool loadSettings(CrossPointSettings& s, const char* json, bool* needsResave = nullptr);
// In-memory halves of the settings file format, shared with the BLE sync
// snapshot so settings.json and the app payload stay one format/one validator.
void settingsToJson(const CrossPointSettings& s, JsonDocument& doc);
// Applies a full or partial settings object: absent keys keep their current
// values, out-of-range values are clamped exactly like the file loader.
// migrateLegacy enables pre-refactor file migrations (file loads only).
void settingsFromJson(CrossPointSettings& s, JsonObjectConst doc, bool* needsResave = nullptr,
                      bool migrateLegacy = false);

// CrossPointState
bool saveState(const CrossPointState& s, const char* path);
bool loadState(CrossPointState& s, const char* json);

// WifiCredentialStore
bool saveWifi(const WifiCredentialStore& store, const char* path);
bool loadWifi(WifiCredentialStore& store, const char* json, bool* needsResave = nullptr);

// RecentBooksStore
bool saveRecentBooks(const RecentBooksStore& store, const char* path);
bool loadRecentBooks(RecentBooksStore& store, const char* json);

// OpdsServerStore
bool saveOpds(const OpdsServerStore& store, const char* path);
bool loadOpds(OpdsServerStore& store, const char* json, bool* needsResave = nullptr);

// Bookmarks
bool saveBookmarks(const std::vector<BookmarkEntry>& bookmarks, const char* path);
bool loadBookmarks(std::vector<BookmarkEntry>& bookmarks, const char* json);

}  // namespace JsonSettingsIO
