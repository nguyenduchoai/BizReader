#pragma once

#include "components/themes/lyra/LyraTheme.h"

namespace BizReaderMetrics {
constexpr ThemeMetrics values = LyraMetrics::values;
}

class BizReaderTheme final : public LyraTheme {
 public:
  void drawHeader(const GfxRenderer& renderer, Rect rect, const char* title,
                  const char* subtitle = nullptr) const override;
  void drawButtonMenu(GfxRenderer& renderer, Rect rect, int buttonCount, int selectedIndex,
                      const std::function<std::string(int index)>& buttonLabel,
                      const std::function<UIIcon(int index)>& rowIcon) const override;
  int getButtonMenuItemAt(Rect rect, int buttonCount, int x, int y) const override;
};
