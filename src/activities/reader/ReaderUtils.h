#pragma once

#include <CrossPointSettings.h>
#include <GfxRenderer.h>
#include <HalTiltSensor.h>
#include <Logging.h>

#include <algorithm>

#include "MappedInputManager.h"

namespace ReaderUtils {

constexpr unsigned long GO_HOME_MS = 1000;
constexpr unsigned long SKIP_HOLD_MS = 700;
constexpr unsigned long BOOKMARK_HOLD_MS = 400;
constexpr unsigned long BOOKMARK_MESSAGE_DURATION_MS = 2500;

inline void applyOrientation(GfxRenderer& renderer, const uint8_t orientation) {
  switch (orientation) {
    case CrossPointSettings::ORIENTATION::PORTRAIT:
      renderer.setOrientation(GfxRenderer::Orientation::Portrait);
      break;
    case CrossPointSettings::ORIENTATION::LANDSCAPE_CW:
      renderer.setOrientation(GfxRenderer::Orientation::LandscapeClockwise);
      break;
    case CrossPointSettings::ORIENTATION::INVERTED:
      renderer.setOrientation(GfxRenderer::Orientation::PortraitInverted);
      break;
    case CrossPointSettings::ORIENTATION::LANDSCAPE_CCW:
      renderer.setOrientation(GfxRenderer::Orientation::LandscapeCounterClockwise);
      break;
    default:
      break;
  }
}

struct PageTurnResult {
  bool prev;
  bool next;
  bool fromTilt;
};

inline PageTurnResult detectPageTurn(const MappedInputManager& input) {
  const bool usePress = SETTINGS.longPressButtonBehavior == SETTINGS.OFF;
  const bool tiltNext = SETTINGS.tiltPageTurn && halTiltSensor.wasTiltedForward();
  const bool tiltPrev = SETTINGS.tiltPageTurn && halTiltSensor.wasTiltedBack();
  const bool swapFront = input.isNavDirectionSwapped();
  const auto prevButton = swapFront ? MappedInputManager::Button::Right : MappedInputManager::Button::Left;
  const auto nextButton = swapFront ? MappedInputManager::Button::Left : MappedInputManager::Button::Right;
  const bool prev =
      tiltPrev ||
      (usePress ? (input.wasPressed(MappedInputManager::Button::PageBack) || input.wasPressed(prevButton))
                : (input.wasReleased(MappedInputManager::Button::PageBack) || input.wasReleased(prevButton)));
  const bool powerTurn = SETTINGS.shortPwrBtn == CrossPointSettings::SHORT_PWRBTN::PAGE_TURN &&
                         input.wasReleased(MappedInputManager::Button::Power);
  const bool next = tiltNext || (usePress ? (input.wasPressed(MappedInputManager::Button::PageForward) || powerTurn ||
                                             input.wasPressed(nextButton))
                                          : (input.wasReleased(MappedInputManager::Button::PageForward) || powerTurn ||
                                             input.wasReleased(nextButton)));
  return {prev, next, tiltPrev || tiltNext};
}

inline void displayWithRefreshCycle(const GfxRenderer& renderer, int& pagesUntilFullRefresh) {
  if (pagesUntilFullRefresh <= 1) {
    renderer.displayBuffer(HalDisplay::HALF_REFRESH);
    pagesUntilFullRefresh = SETTINGS.getRefreshFrequency();
  } else {
    renderer.displayBuffer();
    pagesUntilFullRefresh--;
  }
}

// Grayscale sibling of displayWithRefreshCycle: pick the deghost strength for a
// grayscale page from the same full-refresh cadence. Every getRefreshFrequency()
// pages force a FULL clear (complete deghost); other pages get a quick FAST
// update. Returns the mode to hand to renderer.displayGrayBuffer(). This is what
// makes the refresh-frequency setting affect anti-aliased reading on controller-
// less panels (EPD47), whose grayscale draw does its own on-glass clear; on-glass
// controllers ignore the mode and run their own grayscale waveform.
inline HalDisplay::RefreshMode grayscaleRefreshMode(int& pagesUntilFullRefresh) {
  if (pagesUntilFullRefresh <= 1) {
    pagesUntilFullRefresh = SETTINGS.getRefreshFrequency();
    return HalDisplay::FULL_REFRESH;
  }
  pagesUntilFullRefresh--;
  return HalDisplay::FAST_REFRESH;
}

// Grayscale anti-aliasing pass. Renders content twice (LSB + MSB) to build
// the grayscale buffer. Only the content callback is re-rendered — status bars
// and other overlays should be drawn before calling this.
// Kept as a template to avoid std::function overhead; instantiated once per reader type.
template <typename RenderFn>
bool renderAntiAliased(GfxRenderer& renderer, RenderFn&& renderFn,
                       const HalDisplay::RefreshMode refreshMode = HalDisplay::FAST_REFRESH) {
  if (renderer.supportsStripGrayscale()) {
    const int height = renderer.getDisplayHeight();
    const int widthBytes = renderer.getDisplayWidthBytes();
    int rows = 80;
    uint8_t* scratch = nullptr;
#if defined(BOARD_HAS_PSRAM)
    scratch = renderer.acquireGrayscaleScratch(static_cast<size_t>(widthBytes) * height, true);
    if (scratch) rows = height;
    if (!scratch) {
      scratch = renderer.acquireGrayscaleScratch(static_cast<size_t>(widthBytes) * rows);
    }
#else
    scratch = renderer.acquireGrayscaleScratch(static_cast<size_t>(widthBytes) * rows);
#endif
    if (!scratch) {
      LOG_ERR("READER", "Failed to allocate grayscale scratch");
      return false;
    }

    const auto renderPlane = [&](const bool lsb) {
      renderer.setRenderMode(lsb ? GfxRenderer::GRAYSCALE_LSB : GfxRenderer::GRAYSCALE_MSB);
      for (int y = 0; y < height; y += rows) {
        const int bandRows = std::min(rows, height - y);
        renderer.beginStripTarget(scratch, y, bandRows);
        renderer.clearScreen(0x00);
        renderFn();
        renderer.endStripTarget();
        renderer.writeGrayscalePlaneStrip(lsb, scratch, y, bandRows);
      }
    };

    renderPlane(true);
    renderPlane(false);
    renderer.setRenderMode(GfxRenderer::BW);
    renderer.displayGrayBuffer(refreshMode);
    renderer.cleanupGrayscaleWithFrameBuffer();
    return true;
  }

  if (!renderer.storeBwBuffer()) {
    LOG_ERR("READER", "Failed to store BW buffer for anti-aliasing");
    return false;
  }

  renderer.clearScreen(0x00);
  renderer.setRenderMode(GfxRenderer::GRAYSCALE_LSB);
  renderFn();
  renderer.copyGrayscaleLsbBuffers();

  renderer.clearScreen(0x00);
  renderer.setRenderMode(GfxRenderer::GRAYSCALE_MSB);
  renderFn();
  renderer.copyGrayscaleMsbBuffers();

  renderer.setRenderMode(GfxRenderer::BW);
  renderer.restoreBwBuffer(false);
  renderer.displayGrayBuffer(refreshMode);
  renderer.cleanupGrayscaleWithFrameBuffer();
  return true;
}

}  // namespace ReaderUtils
