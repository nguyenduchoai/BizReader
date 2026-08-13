#include "MappedInputManager.h"

#include <GfxRenderer.h>

#include <algorithm>
#include <cmath>

#include "CrossPointSettings.h"
#include "Logging.h"
#include "components/UITheme.h"

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
  tsConfirm = tsBack = tsSwipeUp = tsSwipeDown = tsSwipeLeft = tsSwipeRight = false;
  tsHintPrevious = tsHintNext = false;
  tsTapPageBack = tsTapPageForward = tsBodyTap = false;
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

  // Tap on release records the logical point for activity-level hit-testing.
  // Reader edge zones turn pages; other body taps synthesize Confirm so the
  // existing non-touch activity handlers remain the fallback.
  float tx = 0.0f, ty = 0.0f;
  if (gpio.wasTouchTap(tx, ty) && !longPressLatched) {
    if (!routeTouchHintTap(tx, ty)) {
      panelToLogical(tx, ty, tsTapX, tsTapY);
      tsBodyTap = true;
      if (readerOnScreen) {
        constexpr float kReaderTapZone = 0.30f;
        if (tsTapX < kReaderTapZone) {
          tsTapPageBack = true;
        } else if (tsTapX > 1.0f - kReaderTapZone) {
          tsTapPageForward = true;
        } else {
          tsConfirm = true;
        }
      } else {
        tsConfirm = true;
      }
    }
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
        dxL = -dyN;
        dyL = dxN;
        break;
      case GfxRenderer::LandscapeClockwise:  // 180°
        dxL = -dxN;
        dyL = -dyN;
        break;
      case GfxRenderer::PortraitInverted:  // 270°
        dxL = dyN;
        dyL = -dxN;
        break;
    }

    // Latch the dominant axis as a primitive direction; touchSynthesizedEdge()
    // maps it onto the logical buttons each consumer actually polls.
    if (std::fabs(dxL) >= std::fabs(dyL)) {
      if (dxL < 0.0f) {
        tsSwipeLeft = true;
      } else {
        tsSwipeRight = true;
      }
    } else {
      if (dyL < 0.0f) {
        tsSwipeUp = true;
      } else {
        tsSwipeDown = true;
      }
    }
  }

  // Clear the long-press latch once the contact ends, arming the next contact.
  const bool released = gpio.wasTouchReleased();
#ifdef TOUCH_PROBE_DEBUG
  const bool hadLongPressLatch = longPressLatched;
#endif
  if (released) {
    longPressLatched = false;
  }

#ifdef TOUCH_PROBE_DEBUG
  if (tsConfirm || tsBack || tsSwipeUp || tsSwipeDown || tsSwipeLeft || tsSwipeRight) {
    LOG_DBG("TOUCH", "gesture: confirm=%d back=%d swipe(U=%d D=%d L=%d R=%d) readerOnScreen=%d", tsConfirm, tsBack,
            tsSwipeUp, tsSwipeDown, tsSwipeLeft, tsSwipeRight, readerOnScreen);
  } else if (released) {
    // A contact ended but produced no gesture: log why, so a "confirm didn't
    // fire" report can be diagnosed without guessing. hadLongPressLatch=1 means
    // long-press already consumed this contact as Back earlier in the hold;
    // otherwise heldMs small with no tap/swipe means the contact exceeded
    // TOUCH_TAP_SLOP_PX (28 native px) sometime during the hold — wasTouchTap()'s
    // moved-beyond-slop latch is permanent for the whole contact, so any brief
    // jitter anywhere in the hold disables tap-to-Confirm even if the finger
    // lands back on target before lifting.
    LOG_DBG("TOUCH", "release with no gesture: heldMs=%lu hadLongPressLatch=%d", gpio.lastTouchHeldMs(),
            hadLongPressLatch);
  }
#endif
}

void MappedInputManager::panelToLogical(const float panelX, const float panelY, float& logicalX,
                                        float& logicalY) const {
  switch (renderer.getOrientation()) {
    case GfxRenderer::LandscapeCounterClockwise:
      logicalX = panelX;
      logicalY = panelY;
      break;
    case GfxRenderer::Portrait:
      logicalX = 1.0f - panelY;
      logicalY = panelX;
      break;
    case GfxRenderer::LandscapeClockwise:
      logicalX = 1.0f - panelX;
      logicalY = 1.0f - panelY;
      break;
    case GfxRenderer::PortraitInverted:
      logicalX = panelY;
      logicalY = 1.0f - panelX;
      break;
  }
}

bool MappedInputManager::getTouchTap(float& logicalX, float& logicalY) const {
  if (!tsBodyTap) return false;
  logicalX = tsTapX;
  logicalY = tsTapY;
  return true;
}

int MappedInputManager::touchListIndex(const Rect& rect, const int itemCount, const int selectedIndex,
                                       const bool hasSubtitle) const {
  float logicalX = 0.0f, logicalY = 0.0f;
  if (!getTouchTap(logicalX, logicalY) || itemCount <= 0) return -1;

  const int touchX = static_cast<int>(logicalX * renderer.getScreenWidth());
  const int touchY = static_cast<int>(logicalY * renderer.getScreenHeight());
  if (touchX < rect.x || touchX >= rect.x + rect.width || touchY < rect.y || touchY >= rect.y + rect.height) {
    return -1;
  }

  const auto& metrics = UITheme::getInstance().getMetrics();
  const int rowHeight = hasSubtitle ? metrics.listWithSubtitleRowHeight : metrics.listRowHeight;
  if (rowHeight <= 0) return -1;
  const int pageItems = std::max(1, rect.height / rowHeight);
  const int pageStart = selectedIndex >= 0 ? (selectedIndex / pageItems) * pageItems : 0;
  const int touchedIndex = pageStart + (touchY - rect.y) / rowHeight;
  return touchedIndex < itemCount ? touchedIndex : -1;
}

bool MappedInputManager::routeTouchHintTap(const float panelX, const float panelY) const {
  // Button hints are always rendered in portrait at the bottom edge, even when
  // the current activity temporarily rotates its content. Convert the native
  // landscape touch frame into that portrait frame before hit-testing.
  const float portraitX = 1.0f - panelY;
  const float portraitY = panelX;
  constexpr float kTouchFooterTop = 0.90f;
  if (portraitY < kTouchFooterTop) {
    return false;
  }

  int slot = static_cast<int>(portraitX * touchHintActions.size());
  if (slot < 0) slot = 0;
  if (slot >= static_cast<int>(touchHintActions.size())) slot = touchHintActions.size() - 1;

  const auto action = touchHintActions[slot];
  switch (action) {
    case TouchHintAction::Back:
      tsBack = true;
      break;
    case TouchHintAction::Confirm:
      tsConfirm = true;
      break;
    case TouchHintAction::Previous:
      tsHintPrevious = true;
      break;
    case TouchHintAction::Next:
      tsHintNext = true;
      break;
    case TouchHintAction::None:
      break;
  }
  LOG_DBG("TOUCH", "footer tap slot=%d action=%u portrait=(%.3f,%.3f)", slot, static_cast<unsigned>(action), portraitX,
          portraitY);
  return true;
}

bool MappedInputManager::touchSynthesizedEdge(const Button button) const {
  // A gesture (tap/long-press/swipe) is a single instantaneous event, but
  // different consumers poll different edges: menus confirm on wasReleased()
  // (HomeActivity, FileBrowserActivity), list nav uses both onNextPress
  // (wasPressed) and onNextRelease (wasReleased) across screens. So a gesture is
  // surfaced as BOTH a press and a release edge in the same frame (isPressed
  // stays physical-only, so hold-to-repeat and lock-on-enter checks see nothing).
  if (!gpio.hasTouch()) {
    return false;
  }
  switch (button) {
    case Button::Confirm:
      return tsConfirm;
    case Button::Back:
      // The GT911 capacitive home key (if present) also maps to logical Back.
      return tsBack || gpio.wasHomeKeyPressed();
    // A swipe answers for every logical button that direction means to some
    // consumer: list menus poll NavNext/NavPrevious, the reader polls
    // PageForward/PageBack, popups (ConfirmationActivity, IntervalSelection,
    // keyboard) poll the raw Up/Down/Left/Right primitives.
    case Button::NavNext:
      return tsSwipeDown || tsHintNext;
    case Button::NavPrevious:
      return tsSwipeUp || tsHintPrevious;
    case Button::PageForward:
      return tsSwipeLeft || tsHintNext || tsTapPageForward;
    case Button::PageBack:
      return tsSwipeRight || tsHintPrevious || tsTapPageBack;
    case Button::Up:
      return tsSwipeUp || tsHintPrevious;
    case Button::Down:
      return tsSwipeDown || tsHintNext;
    case Button::Left:
    case Button::Right:
      // While the reader itself is on screen, horizontal swipes are page turns
      // only: ReaderUtils::detectPageTurn ORs PageBack||Left and PageForward||
      // Right, and front-button Left means *previous* page while swipe-left
      // means *next* — answering both would fire prev+next from one swipe.
      if (readerOnScreen) {
        return false;
      }
      return button == Button::Left ? (tsSwipeLeft || tsHintPrevious) : (tsSwipeRight || tsHintNext);
    default:
      return false;
  }
}

bool MappedInputManager::wasPressed(const Button button) const {
  // Touch boards (e.g. LilyGo T5 EPD47) drive the whole logical control set from
  // GT911 gestures (serviceTouchGestures); the panel has one physical key.
  if (touchSynthesizedEdge(button)) {
    return true;
  }
  return mapButton(button, &HalGPIO::wasPressed);
}

bool MappedInputManager::wasReleased(const Button button) const {
  if (touchSynthesizedEdge(button)) {
    return true;
  }
  return mapButton(button, &HalGPIO::wasReleased);
}

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

  if (gpio.hasTouch()) {
    touchHintActions[0] = back != nullptr && back[0] != '\0' ? TouchHintAction::Back : TouchHintAction::None;
    touchHintActions[1] = confirm != nullptr && confirm[0] != '\0' ? TouchHintAction::Confirm : TouchHintAction::None;
    if (leftLabel == nullptr || leftLabel[0] == '\0') {
      touchHintActions[2] = TouchHintAction::None;
    } else {
      touchHintActions[2] = swapLabels ? TouchHintAction::Next : TouchHintAction::Previous;
    }
    if (rightLabel == nullptr || rightLabel[0] == '\0') {
      touchHintActions[3] = TouchHintAction::None;
    } else {
      touchHintActions[3] = swapLabels ? TouchHintAction::Previous : TouchHintAction::Next;
    }
    return {back, confirm, leftLabel, rightLabel};
  }

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

  auto actionForHardware = [&](uint8_t hw) -> TouchHintAction {
    if (hw == SETTINGS.frontButtonBack) {
      return back != nullptr && back[0] != '\0' ? TouchHintAction::Back : TouchHintAction::None;
    }
    if (hw == SETTINGS.frontButtonConfirm) {
      return confirm != nullptr && confirm[0] != '\0' ? TouchHintAction::Confirm : TouchHintAction::None;
    }
    if (hw == SETTINGS.frontButtonLeft) {
      if (leftLabel == nullptr || leftLabel[0] == '\0') return TouchHintAction::None;
      return swapLabels ? TouchHintAction::Next : TouchHintAction::Previous;
    }
    if (hw == SETTINGS.frontButtonRight) {
      if (rightLabel == nullptr || rightLabel[0] == '\0') return TouchHintAction::None;
      return swapLabels ? TouchHintAction::Previous : TouchHintAction::Next;
    }
    return TouchHintAction::None;
  };

  constexpr uint8_t kFrontButtons[] = {HalGPIO::BTN_BACK, HalGPIO::BTN_CONFIRM, HalGPIO::BTN_LEFT, HalGPIO::BTN_RIGHT};
  for (size_t i = 0; i < touchHintActions.size(); ++i) {
    touchHintActions[i] = actionForHardware(kFrontButtons[i]);
  }

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
