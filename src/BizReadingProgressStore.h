#pragma once

#include <string>

struct BizReadingProgress {
  std::string filename;
  float percentage = 0.0f;
  int spineIndex = 0;
  int pageNumber = 0;
  int pageCount = 0;
  bool pending = false;
};

class BizReadingProgressStore {
 public:
  static bool load(const std::string& filename, BizReadingProgress& progress);
  static bool save(const BizReadingProgress& progress);
  static std::string filenameFromPath(const std::string& path);

 private:
  static std::string pathForFilename(const std::string& filename);
};
