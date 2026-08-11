#include "BizHubActivity.h"

#include <GfxRenderer.h>
#include <I18n.h>

#include <algorithm>
#include <array>

#include "MappedInputManager.h"
#include "components/UITheme.h"
#include "fontIds.h"

namespace {
constexpr std::array<const char*, 5> MODULE_NAMES = {"Ghi chú", "Việc cần làm", "Lịch", "Thời tiết", "Nền nghỉ"};
constexpr std::array<UIIcon, 5> MODULE_ICONS = {Bookmark, Recent, Library, Wifi, Book};
}  // namespace

void BizHubActivity::onEnter() {
  Activity::onEnter();
  BizContentStore::load(content);
  module = -1;
  selectorIndex = 0;
  showingDetail = false;
  requestUpdate();
}

int BizHubActivity::itemCount() const {
  if (module == 0) return static_cast<int>(content.notes.size());
  if (module == 1) return static_cast<int>(content.todos.size());
  if (module == 2) return static_cast<int>(content.events.size());
  return 0;
}

std::string BizHubActivity::itemTitle(const int index) const {
  if (module == 0 && index < static_cast<int>(content.notes.size())) return content.notes[index].title;
  if (module == 1 && index < static_cast<int>(content.todos.size())) {
    return std::string(content.todos[index].done ? "[x] " : "[ ] ") + content.todos[index].title;
  }
  if (module == 2 && index < static_cast<int>(content.events.size())) return content.events[index].title;
  return {};
}

std::string BizHubActivity::itemSubtitle(const int index) const {
  if (module == 0 && index < static_cast<int>(content.notes.size())) return content.notes[index].body;
  if (module == 1 && index < static_cast<int>(content.todos.size())) return content.todos[index].due;
  if (module == 2 && index < static_cast<int>(content.events.size())) {
    const auto& event = content.events[index];
    return event.date + (event.time.empty() ? "" : "  " + event.time) +
           (event.location.empty() ? "" : "  " + event.location);
  }
  return {};
}

void BizHubActivity::loop() {
  const int count = module < 0 ? static_cast<int>(MODULE_NAMES.size()) : itemCount();
  float touchX = 0.0f, touchY = 0.0f;
  if (!showingDetail && mappedInput.getTouchTap(touchX, touchY)) {
    const auto& metrics = UITheme::getInstance().getMetrics();
    const int contentTop = metrics.topPadding + metrics.headerHeight + metrics.verticalSpacing;
    const int contentHeight =
        renderer.getScreenHeight() - contentTop - metrics.buttonHintsHeight - metrics.verticalSpacing;
    const int touched = mappedInput.touchListIndex(Rect{0, contentTop, renderer.getScreenWidth(), contentHeight}, count,
                                                   selectorIndex, true);
    if (touched >= 0) {
      selectorIndex = touched;
    } else {
      mappedInput.cancelTouchConfirm();
    }
  }

  if (mappedInput.wasReleased(MappedInputManager::Button::Back)) {
    if (showingDetail) {
      showingDetail = false;
      requestUpdate();
    } else if (module >= 0) {
      module = -1;
      selectorIndex = 0;
      requestUpdate();
    } else {
      onGoHome(HomeMenuItem::BIZ_HUB);
    }
    return;
  }

  if (mappedInput.wasReleased(MappedInputManager::Button::Confirm) && !showingDetail) {
    if (module < 0) {
      module = selectorIndex;
      selectorIndex = 0;
      requestUpdate();
    } else if (module == 1 && count > 0) {
      if (BizContentStore::toggleTodo(content.todos[selectorIndex].id)) {
        BizContentStore::load(content);
        requestUpdate();
      }
    } else if (count > 0) {
      showingDetail = true;
      requestUpdate();
    }
    return;
  }

  if (!showingDetail && count > 0) {
    buttonNavigator.onNextRelease([this, count] {
      selectorIndex = ButtonNavigator::nextIndex(selectorIndex, count);
      requestUpdate();
    });
    buttonNavigator.onPreviousRelease([this, count] {
      selectorIndex = ButtonNavigator::previousIndex(selectorIndex, count);
      requestUpdate();
    });
  }
}

void BizHubActivity::renderDetail(const int contentTop, const int contentHeight) const {
  const auto& metrics = UITheme::getInstance().getMetrics();
  const int x = metrics.contentSidePadding;
  const int width = renderer.getScreenWidth() - x * 2;
  int y = contentTop + 12;
  const int lineHeight = renderer.getLineHeight(UI_12_FONT_ID);

  if (module == 3) {
    char temperature[24];
    snprintf(temperature, sizeof(temperature), "%d°C", content.weather.temperature);
    renderer.drawCenteredText(NOTOSANS_18_FONT_ID, y + 25, temperature, true, EpdFontFamily::BOLD);
    y += 125;
    renderer.drawCenteredText(UI_12_FONT_ID, y, content.weather.location.c_str(), true, EpdFontFamily::BOLD);
    renderer.drawCenteredText(UI_10_FONT_ID, y + 40, content.weather.condition.c_str());
    char range[48];
    snprintf(range, sizeof(range), "Thấp %d°C   Cao %d°C", content.weather.low, content.weather.high);
    renderer.drawCenteredText(UI_10_FONT_ID, y + 75, range);
    return;
  }
  if (module == 4) {
    renderer.drawCenteredText(UI_12_FONT_ID, y + 50,
                              content.sleepMode == "photo" ? "Ảnh từ ứng dụng" : "Lịch và thời tiết", true,
                              EpdFontFamily::BOLD);
    renderer.drawCenteredText(UI_10_FONT_ID, y + 95, "Nền nghỉ được quản lý từ BizReader App");
    return;
  }

  const std::string title = itemTitle(selectorIndex);
  const std::string body = itemSubtitle(selectorIndex);
  for (const auto& line : renderer.wrappedText(UI_12_FONT_ID, title.c_str(), width, 3, EpdFontFamily::BOLD)) {
    renderer.drawText(UI_12_FONT_ID, x, y, line.c_str(), true, EpdFontFamily::BOLD);
    y += lineHeight;
  }
  y += 16;
  const int maxLines = std::max(1, (contentHeight - (y - contentTop)) / renderer.getLineHeight(UI_10_FONT_ID));
  for (const auto& line : renderer.wrappedText(UI_10_FONT_ID, body.c_str(), width, maxLines)) {
    renderer.drawText(UI_10_FONT_ID, x, y, line.c_str());
    y += renderer.getLineHeight(UI_10_FONT_ID);
  }
}

void BizHubActivity::render(RenderLock&&) {
  renderer.clearScreen();
  const auto& metrics = UITheme::getInstance().getMetrics();
  const int pageWidth = renderer.getScreenWidth();
  const int pageHeight = renderer.getScreenHeight();
  const int contentTop = metrics.topPadding + metrics.headerHeight + metrics.verticalSpacing;
  const int contentHeight = pageHeight - contentTop - metrics.buttonHintsHeight - metrics.verticalSpacing;
  const char* header = module < 0 ? "Tiện ích BizReader" : MODULE_NAMES[module];
  GUI.drawHeader(renderer, Rect{0, metrics.topPadding, pageWidth, metrics.headerHeight}, header);

  if (module < 0) {
    GUI.drawList(
        renderer, Rect{0, contentTop, pageWidth, contentHeight}, MODULE_NAMES.size(), selectorIndex,
        [](int index) { return std::string(MODULE_NAMES[index]); },
        [this](int index) {
          if (index == 0) return std::to_string(content.notes.size()) + " ghi chú";
          if (index == 1) return std::to_string(content.todos.size()) + " công việc";
          if (index == 2) return std::to_string(content.events.size()) + " sự kiện";
          if (index == 3) return content.weather.location;
          return content.sleepMode == "photo" ? std::string("Ảnh") : std::string("Lịch");
        },
        [](int index) { return MODULE_ICONS[index]; });
  } else if (showingDetail || module >= 3) {
    renderDetail(contentTop, contentHeight);
  } else if (itemCount() == 0) {
    renderer.drawCenteredText(UI_10_FONT_ID, contentTop + 60, "Chưa có dữ liệu từ ứng dụng");
  } else {
    GUI.drawList(
        renderer, Rect{0, contentTop, pageWidth, contentHeight}, itemCount(), selectorIndex,
        [this](int index) { return itemTitle(index); }, [this](int index) { return itemSubtitle(index); },
        [this](int) { return module == 0 ? Bookmark : (module == 1 ? Recent : Library); });
  }

  const char* actionLabel = module == 1 ? "Đánh dấu" : (module >= 3 ? "" : tr(STR_OPEN));
  const auto labels = mappedInput.mapLabels(tr(STR_BACK), actionLabel, tr(STR_DIR_UP), tr(STR_DIR_DOWN));
  GUI.drawButtonHints(renderer, labels.btn1, labels.btn2, labels.btn3, labels.btn4);
  renderer.displayBuffer();
}
