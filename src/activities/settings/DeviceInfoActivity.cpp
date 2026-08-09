#include "DeviceInfoActivity.h"

#include <GfxRenderer.h>
#include <HalGPIO.h>
#include <I18n.h>

#include <array>
#include <string>

#include "MappedInputManager.h"
#include "components/UITheme.h"

namespace {
constexpr int kInfoRows = 4;

const char* hardwareName() {
#if defined(FREEINK_DEVICE_LILYGO_EPD47) && FREEINK_DEVICE_LILYGO_EPD47
  return "LilyGo T5S3 4.7-inch";
#else
  return gpio.deviceIsX3() ? "Xteink X3" : "Xteink X4";
#endif
}
}  // namespace

void DeviceInfoActivity::onEnter() {
  Activity::onEnter();
  requestUpdate();
}

void DeviceInfoActivity::loop() {
  if (mappedInput.wasReleased(MappedInputManager::Button::Back) ||
      mappedInput.wasReleased(MappedInputManager::Button::Confirm)) {
    finish();
  }
}

void DeviceInfoActivity::render(RenderLock&&) {
  renderer.clearScreen();

  const auto& metrics = UITheme::getInstance().getMetrics();
  const int pageWidth = renderer.getScreenWidth();
  const int pageHeight = renderer.getScreenHeight();
  GUI.drawHeader(renderer, Rect{0, metrics.topPadding, pageWidth, metrics.headerHeight}, tr(STR_ABOUT_DEVICE),
                 "BizReader");

  const std::array<const char*, kInfoRows> labels = {
      tr(STR_PRODUCT_NAME), tr(STR_DEVICE_NAME), tr(STR_HARDWARE), tr(STR_FIRMWARE_VERSION)};
  const std::array<const char*, kInfoRows> values = {"BizReader", "Hoài Nguyễn", hardwareName(), CROSSPOINT_VERSION};
  const int contentTop = metrics.topPadding + metrics.headerHeight + metrics.verticalSpacing;
  const int contentHeight = pageHeight - contentTop - metrics.buttonHintsHeight - metrics.verticalSpacing;

  GUI.drawList(
      renderer, Rect{0, contentTop, pageWidth, contentHeight}, kInfoRows, -1,
      [&labels](int index) { return std::string(labels[index]); }, nullptr, nullptr,
      [&values](int index) { return std::string(values[index]); });

  const auto footer = mappedInput.mapLabels(tr(STR_BACK), tr(STR_BACK), "", "");
  GUI.drawButtonHints(renderer, footer.btn1, footer.btn2, footer.btn3, footer.btn4);
  renderer.displayBuffer();
}
