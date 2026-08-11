#pragma once

#include <cstdint>
#include <string>
#include <vector>

struct BizNoteItem {
  std::string id;
  std::string title;
  std::string body;
  uint64_t updatedAt = 0;
};

struct BizTodoItem {
  std::string id;
  std::string title;
  std::string due;
  bool done = false;
  uint64_t updatedAt = 0;
};

struct BizDeletedItem {
  std::string id;
  uint64_t updatedAt = 0;
};

struct BizCalendarItem {
  std::string title;
  std::string date;
  std::string time;
  std::string location;
};

struct BizWeatherData {
  std::string location;
  std::string condition;
  int temperature = 0;
  int high = 0;
  int low = 0;
};

struct BizContentData {
  std::vector<BizNoteItem> notes;
  std::vector<BizTodoItem> todos;
  std::vector<BizDeletedItem> deletedNotes;
  std::vector<BizDeletedItem> deletedTodos;
  std::vector<BizCalendarItem> events;
  BizWeatherData weather;
  std::string sleepMode = "calendar";
  uint64_t updatedAt = 0;
};

class BizContentStore {
 public:
  static constexpr const char* PATH = "/.crosspoint/bizsync/content.json";
  static constexpr size_t MAX_JSON_SIZE = 32UL * 1024UL;

  static bool saveJson(const std::string& json, std::string& error);
  static bool loadJson(std::string& json);
  static bool load(BizContentData& data);
  static bool toggleTodo(const std::string& id);
};
