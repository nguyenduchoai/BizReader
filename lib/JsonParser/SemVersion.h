#pragma once

#include <climits>
#include <cstring>

struct SemVersion {
  int major = 0;
  int minor = 0;
  int patch = 0;
};

inline bool parseSemVersion(const char* value, SemVersion& version) {
  if (!value) return false;
  if (*value == 'v' || *value == 'V') ++value;

  const auto parsePart = [](const char*& cursor, int& result) {
    if (*cursor < '0' || *cursor > '9') return false;
    result = 0;
    while (*cursor >= '0' && *cursor <= '9') {
      const int digit = *cursor - '0';
      if (result > (INT_MAX - digit) / 10) return false;
      result = result * 10 + digit;
      ++cursor;
    }
    return true;
  };

  SemVersion parsed;
  if (!parsePart(value, parsed.major) || *value++ != '.' || !parsePart(value, parsed.minor) || *value++ != '.' ||
      !parsePart(value, parsed.patch)) {
    return false;
  }
  if (*value != '\0' && *value != '-' && *value != '+') return false;
  version = parsed;
  return true;
}

inline int compareSemVersions(const SemVersion& left, const SemVersion& right) {
  if (left.major != right.major) return left.major < right.major ? -1 : 1;
  if (left.minor != right.minor) return left.minor < right.minor ? -1 : 1;
  if (left.patch != right.patch) return left.patch < right.patch ? -1 : 1;
  return 0;
}

inline bool isBizReaderPreReleaseVersion(const char* value) {
  return value != nullptr && (strstr(value, "-dev") != nullptr || strstr(value, "-rc") != nullptr);
}
