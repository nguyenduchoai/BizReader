#pragma once

#include <HalGPIO.h>

#include <array>

class GfxRenderer;
struct Rect;

class MappedInputManager {
 public:
  enum class Button { Back, Confirm, Left, Right, Up, Down, Power, PageBack, PageForward, NavNext, NavPrevious };

  struct Labels {
    const char* btn1;
    const char* btn2;
    const char* btn3;
    const char* btn4;
  };

  MappedInputManager(HalGPIO& gpio, const GfxRenderer& renderer) : gpio(gpio), renderer(renderer) {}

  void update() const {
    gpio.update();
    serviceTouchGestures();
  }
  bool wasPressed(Button button) const;
  bool wasReleased(Button button) const;
  bool isPressed(Button button) const;
  bool wasAnyPressed() const;
  bool wasAnyReleased() const;
  unsigned long getHeldTime() const;
  Labels mapLabels(const char* back, const char* confirm, const char* previous, const char* next) const;
  // Returns the raw front button index that was pressed this frame (or -1 if none).
  int getPressedFrontButton() const;

  // Returns a non-footer tap in normalized logical screen coordinates. The
  // point follows the current renderer orientation, so activities can hit-test
  // what the user actually touched.
  bool getTouchTap(float& logicalX, float& logicalY) const;
  int touchListIndex(const Rect& rect, int itemCount, int selectedIndex, bool hasSubtitle) const;
  void cancelTouchConfirm() const { tsConfirm = false; }

  // True when the control axis is flipped relative to the physical buttons: the user opted into
  // orientation-following front buttons AND the screen is *currently rendered* rotated (INVERTED /
  // LANDSCAPE_CCW). Keyed on the live renderer orientation rather than the persisted reader setting,
  // so portrait UI (home, settings) never swaps while the reader and its menus do.
  [[nodiscard]] bool isNavDirectionSwapped() const;

  // Set each frame by the main loop: true while the reader itself is the current
  // activity. Gates the swipe -> Left/Right primitive mapping (see
  // touchSynthesizedEdge); reader-launched popups/menus are separate activities,
  // so directional swipes keep working there. No-op on non-touch boards.
  void setReaderOnScreen(const bool onScreen) { readerOnScreen = onScreen; }

 private:
  enum class TouchHintAction : uint8_t { None, Back, Confirm, Previous, Next };

  HalGPIO& gpio;
  // Logical-to-physical button mapping depends on what the user is actually looking at: when the
  // screen is rendered rotated, the directional buttons must flip to match. The renderer is the only
  // authority on the *live* orientation (the reader rotates it and restores portrait on exit), so we
  // read it here instead of CrossPointSettings.orientation, which is just the persisted reader
  // preference and stays "rotated" even while portrait UI like home/settings is on screen.
  const GfxRenderer& renderer;

  bool mapButton(Button button, bool (HalGPIO::*fn)(uint8_t) const) const;

  // --- Touch gesture synthesis (Milestone B) --------------------------------
  // On touch boards (LilyGo T5 EPD47) there is one physical key, so the whole
  // logical control set is synthesized from GT911 gestures each update():
  //   tap (release, no movement)  -> direct hit-test + Confirm fallback
  //   long-press (in place, held) -> Back
  //   swipe                       -> a primitive direction (up/down/left/right)
  // touchSynthesizedEdge() then answers that direction for every logical button
  // it means to some consumer: NavNext/NavPrevious for list menus, PageForward/
  // PageBack for the reader, and the raw Up/Down/Left/Right for popups
  // (ConfirmationActivity, IntervalSelection, keyboard). Direction is resolved
  // in the current logical orientation before latching, so it stays correct as
  // the reader rotates. The synthesized edges are OR'd into BOTH wasPressed()
  // and wasReleased() so consumers that act on either edge fire; they are inert
  // (never set) on boards without a touch controller, so other platforms are
  // unaffected. See [[lilygo-t5-epd47-touch-quirks]].
  void serviceTouchGestures() const;
  bool routeTouchHintTap(float panelX, float panelY) const;
  void panelToLogical(float panelX, float panelY, float& logicalX, float& logicalY) const;

  // True this frame if `button` was produced by a touch gesture (tap/long-press/
  // swipe). Shared by wasPressed() and wasReleased(); false on non-touch boards.
  bool touchSynthesizedEdge(Button button) const;

  // Long-press threshold for a stationary contact to synthesize Back.
  static constexpr unsigned long TOUCH_LONGPRESS_MS = 550;

  // Latched one-frame synthesized gesture edges (mutable: update() is const but
  // owns this per-frame edge state, mirroring how it drives the non-const gpio).
  mutable bool tsConfirm = false;
  mutable bool tsBack = false;
  mutable bool tsSwipeUp = false;
  mutable bool tsSwipeDown = false;
  mutable bool tsSwipeLeft = false;
  mutable bool tsSwipeRight = false;
  mutable bool tsHintPrevious = false;
  mutable bool tsHintNext = false;
  mutable bool tsTapPageBack = false;
  mutable bool tsTapPageForward = false;
  mutable bool tsBodyTap = false;
  mutable float tsTapX = 0.0f;
  mutable float tsTapY = 0.0f;
  mutable std::array<TouchHintAction, 4> touchHintActions = {
      TouchHintAction::None, TouchHintAction::None, TouchHintAction::None, TouchHintAction::None};
  // True once a long-press has fired Back for the current contact; suppresses the
  // tap-on-release that would otherwise also Confirm, and blocks a repeat Back.
  mutable bool longPressLatched = false;
  // See setReaderOnScreen().
  bool readerOnScreen = false;
};
