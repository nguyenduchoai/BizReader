#include "BizReaderTheme.h"

#include <GfxRenderer.h>

#include <algorithm>

#include "CrossPointSettings.h"
#include "components/icons/book.h"
#include "components/icons/bookmark.h"
#include "components/icons/folder.h"
#include "components/icons/hotspot.h"
#include "components/icons/library.h"
#include "components/icons/recent.h"
#include "components/icons/settings2.h"
#include "components/icons/transfer.h"
#include "components/icons/wifi.h"
#include "fontIds.h"

namespace {
constexpr int kCornerRadius = 6;
constexpr int kMenuColumns = 2;
constexpr int kMenuGap = 12;
constexpr int kTileHeight = 92;
constexpr int kIconSize = 32;

const uint8_t* iconForMenu(const UIIcon icon) {
  switch (icon) {
    case UIIcon::Folder:
      return FolderIcon;
    case UIIcon::Book:
      return BookIcon;
    case UIIcon::Recent:
      return RecentIcon;
    case UIIcon::Settings:
      return Settings2Icon;
    case UIIcon::Transfer:
      return TransferIcon;
    case UIIcon::Library:
      return LibraryIcon;
    case UIIcon::Wifi:
      return WifiIcon;
    case UIIcon::Hotspot:
      return HotspotIcon;
    case UIIcon::Bookmark:
      return BookmarkIcon;
    default:
      return nullptr;
  }
}
}  // namespace

void BizReaderTheme::drawHeader(const GfxRenderer& renderer, const Rect rect, const char* title,
                                const char* subtitle) const {
  renderer.fillRect(rect.x, rect.y, rect.width, rect.height, false);

  const bool showBatteryPercentage =
      SETTINGS.hideBatteryPercentage != CrossPointSettings::HIDE_BATTERY_PERCENTAGE::HIDE_ALWAYS;
  const int batteryX =
      rect.x + rect.width - BizReaderMetrics::values.contentSidePadding - BizReaderMetrics::values.batteryWidth;
  drawBatteryRight(
      renderer,
      Rect{batteryX, rect.y + 6, BizReaderMetrics::values.batteryWidth, BizReaderMetrics::values.batteryHeight},
      showBatteryPercentage);

  const char* heading = title != nullptr && title[0] != '\0' ? title : "BizReader";
  const auto style = title != nullptr && title[0] != '\0' ? EpdFontFamily::REGULAR : EpdFontFamily::BOLD;
  const int fontId = title != nullptr && title[0] != '\0' ? UI_10_FONT_ID : UI_12_FONT_ID;
  const int reservedRight = showBatteryPercentage ? 108 : 48;
  const auto renderedHeading = renderer.truncatedText(
      fontId, heading, rect.width - BizReaderMetrics::values.contentSidePadding * 2 - reservedRight, style);

  if (title != nullptr && title[0] != '\0') {
    const int headingWidth = renderer.getTextWidth(fontId, renderedHeading.c_str(), style);
    renderer.drawText(fontId, rect.x + (rect.width - headingWidth) / 2,
                      rect.y + BizReaderMetrics::values.batteryBarHeight + 4, renderedHeading.c_str(), true, style);
  } else {
    renderer.drawText(fontId, rect.x + BizReaderMetrics::values.contentSidePadding, rect.y + 10,
                      renderedHeading.c_str(), true, style);
  }

  if (subtitle != nullptr && subtitle[0] != '\0' && rect.height >= BizReaderMetrics::values.headerHeight) {
    const auto renderedSubtitle =
        renderer.truncatedText(SMALL_FONT_ID, subtitle, rect.width - BizReaderMetrics::values.contentSidePadding * 2);
    const int subtitleWidth = renderer.getTextWidth(SMALL_FONT_ID, renderedSubtitle.c_str());
    renderer.drawText(SMALL_FONT_ID, rect.x + (rect.width - subtitleWidth) / 2, rect.y + 56, renderedSubtitle.c_str());
  }

  renderer.drawLine(rect.x + BizReaderMetrics::values.contentSidePadding, rect.y + rect.height - 2,
                    rect.x + rect.width - BizReaderMetrics::values.contentSidePadding, rect.y + rect.height - 2, true);
}

void BizReaderTheme::drawButtonMenu(GfxRenderer& renderer, const Rect rect, const int buttonCount,
                                    const int selectedIndex, const std::function<std::string(int index)>& buttonLabel,
                                    const std::function<UIIcon(int index)>& rowIcon) const {
  const int sidePadding = BizReaderMetrics::values.contentSidePadding;
  const int tileWidth = (rect.width - sidePadding * 2 - kMenuGap) / kMenuColumns;

  for (int i = 0; i < buttonCount; ++i) {
    const int column = i % kMenuColumns;
    const int row = i / kMenuColumns;
    const Rect tile{rect.x + sidePadding + column * (tileWidth + kMenuGap), rect.y + row * (kTileHeight + kMenuGap),
                    tileWidth, kTileHeight};
    const bool selected = selectedIndex == i;

    renderer.fillRoundedRect(tile.x, tile.y, tile.width, tile.height, kCornerRadius,
                             selected ? Color::LightGray : Color::White);
    renderer.drawRoundedRect(tile.x, tile.y, tile.width, tile.height, selected ? 2 : 1, kCornerRadius, true);

    const uint8_t* icon = rowIcon != nullptr ? iconForMenu(rowIcon(i)) : nullptr;
    if (icon != nullptr) {
      renderer.drawIcon(icon, tile.x + (tile.width - kIconSize) / 2, tile.y + 14, kIconSize);
    }

    const std::string rawLabel = buttonLabel(i);
    const auto label = renderer.truncatedText(UI_10_FONT_ID, rawLabel.c_str(), tile.width - 16,
                                              selected ? EpdFontFamily::BOLD : EpdFontFamily::REGULAR);
    const auto labelStyle = selected ? EpdFontFamily::BOLD : EpdFontFamily::REGULAR;
    const int labelWidth = renderer.getTextWidth(UI_10_FONT_ID, label.c_str(), labelStyle);
    renderer.drawText(UI_10_FONT_ID, tile.x + std::max(8, (tile.width - labelWidth) / 2), tile.y + 58, label.c_str(),
                      true, labelStyle);
  }
}

int BizReaderTheme::getButtonMenuItemAt(const Rect rect, const int buttonCount, const int x, const int y) const {
  const int sidePadding = BizReaderMetrics::values.contentSidePadding;
  const int tileWidth = (rect.width - sidePadding * 2 - kMenuGap) / kMenuColumns;
  for (int i = 0; i < buttonCount; ++i) {
    const int column = i % kMenuColumns;
    const int row = i / kMenuColumns;
    const Rect tile{rect.x + sidePadding + column * (tileWidth + kMenuGap), rect.y + row * (kTileHeight + kMenuGap),
                    tileWidth, kTileHeight};
    if (x >= tile.x && x < tile.x + tile.width && y >= tile.y && y < tile.y + tile.height) return i;
  }
  return -1;
}
