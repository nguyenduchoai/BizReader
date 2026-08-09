#pragma once
#include <I18n.h>

#include <algorithm>
#include <functional>
#include <string>
#include <vector>

#include "GfxRenderer.h"
#include "MappedInputManager.h"
#include "components/UITheme.h"
#include "fontIds.h"

class OptionPopup {
 public:
  void show(StrId titleId, const StrId* optionIds, int optionCount, int currentIndex,
            std::function<void(int)> onSelect) {
    title = I18N.get(titleId);
    ownedStrings.resize(optionCount);
    for (int i = 0; i < optionCount; i++) {
      ownedStrings[i] = I18N.get(optionIds[i]);
    }
    selectedIndex = currentIndex;
    onSelectCallback = std::move(onSelect);
    active = true;
  }

  void show(const char* titleStr, const char* const* options, int optionCount, int currentIndex,
            std::function<void(int)> onSelect) {
    title = titleStr;
    ownedStrings.resize(optionCount);
    for (int i = 0; i < optionCount; i++) {
      ownedStrings[i] = options[i];
    }
    selectedIndex = currentIndex;
    onSelectCallback = std::move(onSelect);
    active = true;
  }

  void show(StrId titleId, const std::vector<std::string>& options, int currentIndex,
            std::function<void(int)> onSelect) {
    title = I18N.get(titleId);
    ownedStrings = options;
    selectedIndex = currentIndex;
    onSelectCallback = std::move(onSelect);
    active = true;
  }

  bool handleInput(MappedInputManager& input, const GfxRenderer& renderer,
                   const std::function<void()>& requestUpdate) {
    if (!active) return false;

    const int count = static_cast<int>(ownedStrings.size());
    float touchX = 0.0f, touchY = 0.0f;
    if (input.getTouchTap(touchX, touchY)) {
      const int touched = getTouchedIndex(renderer, touchX, touchY);
      if (touched >= 0) {
        selectedIndex = touched;
      } else {
        input.cancelTouchConfirm();
      }
    }

    if (input.wasPressed(MappedInputManager::Button::Up) || input.wasPressed(MappedInputManager::Button::Left)) {
      selectedIndex = (selectedIndex - 1 + count) % count;
      requestUpdate();
      return true;
    } else if (input.wasPressed(MappedInputManager::Button::Down) ||
               input.wasPressed(MappedInputManager::Button::Right)) {
      selectedIndex = (selectedIndex + 1) % count;
      requestUpdate();
      return true;
    } else if (input.wasPressed(MappedInputManager::Button::Confirm)) {
      active = false;
      if (onSelectCallback) onSelectCallback(selectedIndex);
      requestUpdate();
      return true;
    } else if (input.wasPressed(MappedInputManager::Button::Back)) {
      active = false;
      requestUpdate();
      return true;
    }
    return true;
  }

  bool processRender(GfxRenderer& renderer, const MappedInputManager& input) const {
    if (!active) return false;
    const auto popupLabels = input.mapLabels(tr(STR_BACK), tr(STR_SELECT), tr(STR_DIR_UP), tr(STR_DIR_DOWN));
    GUI.drawButtonHints(renderer, popupLabels.btn1, popupLabels.btn2, popupLabels.btn3, popupLabels.btn4);
    render(renderer);
    renderer.displayBuffer();
    return true;
  }

  void render(const GfxRenderer& renderer) const {
    if (!active) return;
    GUI.drawOptionPopup(renderer, title.c_str(), ownedStrings, selectedIndex);
  }

  bool isActive() const { return active; }

 private:
  bool active = false;
  std::string title;
  std::vector<std::string> ownedStrings;
  int selectedIndex = 0;
  std::function<void(int)> onSelectCallback;

  int getTouchedIndex(const GfxRenderer& renderer, const float logicalX, const float logicalY) const {
    const auto& metrics = UITheme::getInstance().getMetrics();
    const int pageWidth = renderer.getScreenWidth();
    const int pageHeight = renderer.getScreenHeight();
    const int touchX = static_cast<int>(logicalX * pageWidth);
    const int touchY = static_cast<int>(logicalY * pageHeight);
    const int optionFontId = metrics.optionPopupUseSmallFont ? UI_10_FONT_ID : UI_12_FONT_ID;
    const EpdFontFamily::Style optionStyle =
        metrics.optionPopupOptionFontBold ? EpdFontFamily::BOLD : EpdFontFamily::REGULAR;
    const int optionLineHeight = renderer.getLineHeight(optionFontId);
    const int titleLineHeight = renderer.getLineHeight(UI_12_FONT_ID);
    const int rowHeight = optionLineHeight + metrics.optionPopupSelectionVPadding * 2;

    int maxTextWidth = renderer.getTextWidth(UI_12_FONT_ID, title.c_str(), EpdFontFamily::BOLD);
    for (const auto& option : ownedStrings) {
      maxTextWidth = std::max(maxTextWidth, renderer.getTextWidth(optionFontId, option.c_str(), optionStyle));
    }

    const int count = static_cast<int>(ownedStrings.size());
    const int listHeight = rowHeight * count + metrics.optionPopupItemSpacing * (count - 1);
    const int dialogWidth =
        std::min((maxTextWidth + metrics.optionPopupInnerPadding * 2 +
                  metrics.optionPopupSelectionHPadding * 2) *
                     12 / 10,
                 pageWidth - metrics.optionPopupDialogSideMargin * 2);
    const int dialogHeight = titleLineHeight + metrics.optionPopupTitleGap + listHeight +
                             metrics.optionPopupInnerPadding * 2;
    const int dialogX = (pageWidth - dialogWidth) / 2;
    const int dialogY = (pageHeight - dialogHeight) / 2;
    const int itemX = dialogX + metrics.optionPopupInnerPadding;
    const int itemWidth = dialogWidth - metrics.optionPopupInnerPadding * 2;
    const int listY = dialogY + metrics.optionPopupInnerPadding + titleLineHeight + metrics.optionPopupTitleGap;

    if (touchX < itemX || touchX >= itemX + itemWidth) return -1;
    for (int i = 0; i < count; ++i) {
      const int rowY = listY + i * (rowHeight + metrics.optionPopupItemSpacing);
      if (touchY >= rowY && touchY < rowY + rowHeight) return i;
    }
    return -1;
  }
};
