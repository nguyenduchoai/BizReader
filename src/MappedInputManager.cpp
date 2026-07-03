#include "MappedInputManager.h"

#include <GfxRenderer.h>

#include <cmath>

#include "CrossPointSettings.h"
#include "Logging.h"

bool MappedInputManager::isNavDirectionSwapped() const {
  // Key the swap on the orientation the screen is *actually* rendered at, not the persisted reader
  // setting. The reader (and its modal menus) render rotated, so navigation/labels flip there; the
  // home and settings UI render in portrait, so they never flip even when a rotated reader is configured.
  const auto orientation = renderer.getOrientation();
  return SETTINGS.frontButtonFollowOrientation &&
         (orientation == GfxRenderer::PortraitInverted || orientation == GfxRenderer::LandscapeCounterClockwise);
}

bool MappedInputManager::mapButton(const Button button, bool (HalGPIO::*fn)(uint8_t) const) const {
  const auto sideLayout = SETTINGS.sideButtonLayout;

  switch (button) {
    case Button::Back:
      // Logical Back maps to user-configured front button.
      return (gpio.*fn)(SETTINGS.frontButtonBack);
    case Button::Confirm:
      // Logical Confirm maps to user-configured front button.
      return (gpio.*fn)(SETTINGS.frontButtonConfirm);
    case Button::Left:
      // Logical Left maps to user-configured front button.
      return (gpio.*fn)(SETTINGS.frontButtonLeft);
    case Button::Right:
      // Logical Right maps to user-configured front button.
      return (gpio.*fn)(SETTINGS.frontButtonRight);
    case Button::Up:
      // Side buttons remain fixed for Up/Down.
      return (gpio.*fn)(HalGPIO::BTN_UP);
    case Button::Down:
      // Side buttons remain fixed for Up/Down.
      return (gpio.*fn)(HalGPIO::BTN_DOWN);
    case Button::Power:
      // Power button bypasses remapping.
      return (gpio.*fn)(HalGPIO::BTN_POWER);
    case Button::PageBack:
      // Reader page navigation uses side buttons and can be swapped via settings.
      switch (sideLayout) {
        case CrossPointSettings::PREV_NEXT:
          return (gpio.*fn)(HalGPIO::BTN_UP);
        case CrossPointSettings::NEXT_PREV:
          return (gpio.*fn)(HalGPIO::BTN_DOWN);
        case CrossPointSettings::SIDE_BUTTONS_DISABLED:
        default:
          return false;
      }
    case Button::PageForward:
      // Reader page navigation uses side buttons and can be swapped via settings.
      switch (sideLayout) {
        case CrossPointSettings::PREV_NEXT:
          return (gpio.*fn)(HalGPIO::BTN_DOWN);
        case CrossPointSettings::NEXT_PREV:
          return (gpio.*fn)(HalGPIO::BTN_UP);
        case CrossPointSettings::SIDE_BUTTONS_DISABLED:
        default:
          return false;
      }
    case Button::NavNext:
      // Logical "next item" navigation: side Down + front Right, with the control axis flipped in
      // INVERTED / LANDSCAPE_CCW (frontButtonFollowOrientation) so it matches the rotated hint labels.
      return isNavDirectionSwapped() ? (mapButton(Button::Up, fn) || mapButton(Button::Left, fn))
                                     : (mapButton(Button::Down, fn) || mapButton(Button::Right, fn));
    case Button::NavPrevious:
      // Logical "previous item" navigation: side Up + front Left, axis-flipped in the same orientations.
      return isNavDirectionSwapped() ? (mapButton(Button::Down, fn) || mapButton(Button::Right, fn))
                                     : (mapButton(Button::Up, fn) || mapButton(Button::Left, fn));
  }

  return false;
}

void MappedInputManager::serviceTouchGestures() const {
  // Recompute per-frame synthesized edges. Cleared first so a frame with no
  // gesture reports nothing, and left all-false on non-touch boards.
  tsConfirm = tsBack = tsNavNext = tsNavPrev = tsPageForward = tsPageBack = false;
  if (!gpio.hasTouch()) {
    return;
  }

  // Long-press (stationary contact held past the threshold) -> Back. Fires once
  // per contact, mid-hold, and latches so the tap-on-release below is suppressed.
  float nx = 0.0f, ny = 0.0f;
  unsigned long heldMs = 0;
  if (gpio.isTouchTapCandidate(nx, ny, heldMs)) {
    if (!longPressLatched && heldMs >= TOUCH_LONGPRESS_MS) {
      tsBack = true;
      longPressLatched = true;
    }
  }

  // Tap on release (no movement) -> Confirm, unless this contact already fired a
  // long-press Back.
  float tx = 0.0f, ty = 0.0f;
  if (gpio.wasTouchTap(tx, ty) && !longPressLatched) {
    tsConfirm = true;
  }

  // Swipe (flick) -> directional navigation. The SDK reports start/end normalized
  // in the panel's native (physical) frame; rotate the delta into the current
  // logical orientation so "up on screen" is NavPrevious regardless of rotation.
  float x0 = 0.0f, y0 = 0.0f, x1 = 0.0f, y1 = 0.0f;
  if (gpio.wasSwipe(x0, y0, x1, y1)) {
    const float dxN = x1 - x0;     // + = toward native X-max (long panel edge)
    const float dyN = y1 - y0;     // + = toward native Y-max (short panel edge)
    float dxL = 0.0f, dyL = 0.0f;  // logical: +x = right, +y = down
    switch (renderer.getOrientation()) {
      case GfxRenderer::LandscapeCounterClockwise:  // logical frame == native frame
        dxL = dxN;
        dyL = dyN;
        break;
      case GfxRenderer::Portrait:  // native rotated 90°: long panel axis is vertical
        dxL = dyN;
        dyL = -dxN;
        break;
      case GfxRenderer::LandscapeClockwise:  // 180°
        dxL = -dxN;
        dyL = -dyN;
        break;
      case GfxRenderer::PortraitInverted:  // 270°
        dxL = -dyN;
        dyL = dxN;
        break;
    }

    if (std::fabs(dxL) >= std::fabs(dyL)) {
      // Horizontal flick = page turn. Swipe left (content forward) -> next page.
      if (dxL < 0.0f) {
        tsPageForward = true;
      } else {
        tsPageBack = true;
      }
    } else {
      // Vertical flick = move the list highlight. Swipe up -> previous item.
      if (dyL < 0.0f) {
        tsNavPrev = true;
      } else {
        tsNavNext = true;
      }
    }
  }

  // Clear the long-press latch once the contact ends, arming the next contact.
  if (gpio.wasTouchReleased()) {
    longPressLatched = false;
  }

#ifdef TOUCH_PROBE_DEBUG
  if (tsConfirm || tsBack || tsNavNext || tsNavPrev || tsPageForward || tsPageBack) {
    LOG_DBG("TOUCH", "gesture: confirm=%d back=%d navNext=%d navPrev=%d pageFwd=%d pageBack=%d", tsConfirm, tsBack,
            tsNavNext, tsNavPrev, tsPageForward, tsPageBack);
  }
#endif
}

bool MappedInputManager::wasPressed(const Button button) const {
  // Touch boards (e.g. LilyGo T5 EPD47) drive the whole logical control set from
  // GT911 gestures (serviceTouchGestures): the panel has one physical key, so
  // tap = Confirm, long-press = Back, swipes = page/list navigation. These
  // synthesized edges are OR'd in below; on non-touch boards they are never set.
  if (gpio.hasTouch()) {
    // The GT911 capacitive home key (if present) also maps to logical Back.
    if (button == Button::Back && (tsBack || gpio.wasHomeKeyPressed())) {
      return true;
    }
    switch (button) {
      case Button::Confirm:
        if (tsConfirm) return true;
        break;
      case Button::Back:
        if (tsBack) return true;
        break;
      case Button::NavNext:
        if (tsNavNext) return true;
        break;
      case Button::NavPrevious:
        if (tsNavPrev) return true;
        break;
      case Button::PageForward:
        if (tsPageForward) return true;
        break;
      case Button::PageBack:
        if (tsPageBack) return true;
        break;
      default:
        break;
    }
  }
  return mapButton(button, &HalGPIO::wasPressed);
}

bool MappedInputManager::wasReleased(const Button button) const { return mapButton(button, &HalGPIO::wasReleased); }

bool MappedInputManager::isPressed(const Button button) const { return mapButton(button, &HalGPIO::isPressed); }

bool MappedInputManager::wasAnyPressed() const { return gpio.wasAnyPressed(); }

bool MappedInputManager::wasAnyReleased() const { return gpio.wasAnyReleased(); }

unsigned long MappedInputManager::getHeldTime() const { return gpio.getHeldTime(); }

MappedInputManager::Labels MappedInputManager::mapLabels(const char* back, const char* confirm, const char* previous,
                                                         const char* next) const {
  // Swap previous/next labels to match the page turn direction swap in INVERTED and LANDSCAPE_CCW.
  const bool swapLabels = isNavDirectionSwapped();
  const char* leftLabel = swapLabels ? next : previous;
  const char* rightLabel = swapLabels ? previous : next;

  // Build the label order based on the configured hardware mapping.
  auto labelForHardware = [&](uint8_t hw) -> const char* {
    // Compare against configured logical roles and return the matching label.
    if (hw == SETTINGS.frontButtonBack) {
      return back;
    }
    if (hw == SETTINGS.frontButtonConfirm) {
      return confirm;
    }
    if (hw == SETTINGS.frontButtonLeft) {
      return leftLabel;
    }
    if (hw == SETTINGS.frontButtonRight) {
      return rightLabel;
    }
    return "";
  };

  return {labelForHardware(HalGPIO::BTN_BACK), labelForHardware(HalGPIO::BTN_CONFIRM),
          labelForHardware(HalGPIO::BTN_LEFT), labelForHardware(HalGPIO::BTN_RIGHT)};
}

int MappedInputManager::getPressedFrontButton() const {
  // Scan the raw front buttons in hardware order.
  // This bypasses remapping so the remap activity can capture physical presses.
  if (gpio.wasPressed(HalGPIO::BTN_BACK)) {
    return HalGPIO::BTN_BACK;
  }
  if (gpio.wasPressed(HalGPIO::BTN_CONFIRM)) {
    return HalGPIO::BTN_CONFIRM;
  }
  if (gpio.wasPressed(HalGPIO::BTN_LEFT)) {
    return HalGPIO::BTN_LEFT;
  }
  if (gpio.wasPressed(HalGPIO::BTN_RIGHT)) {
    return HalGPIO::BTN_RIGHT;
  }
  return -1;
}
