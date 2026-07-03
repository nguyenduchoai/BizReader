#pragma once

#include <HalGPIO.h>

class GfxRenderer;

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

  // True when the control axis is flipped relative to the physical buttons: the user opted into
  // orientation-following front buttons AND the screen is *currently rendered* rotated (INVERTED /
  // LANDSCAPE_CCW). Keyed on the live renderer orientation rather than the persisted reader setting,
  // so portrait UI (home, settings) never swaps while the reader and its menus do.
  [[nodiscard]] bool isNavDirectionSwapped() const;

 private:
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
  //   tap (release, no movement)  -> Confirm
  //   long-press (in place, held) -> Back
  //   horizontal swipe            -> PageForward / PageBack (reader page turn)
  //   vertical swipe              -> NavNext / NavPrevious (move list highlight)
  // Direction is resolved in the current logical orientation before mapping to
  // a logical button, so it stays correct as the reader rotates. The synthesized
  // edges are latched here in update() and OR'd into wasPressed(); they are inert
  // (never set) on boards without a touch controller, so other platforms are
  // unaffected. See [[lilygo-t5-epd47-touch-quirks]].
  void serviceTouchGestures() const;

  // Long-press threshold for a stationary contact to synthesize Back.
  static constexpr unsigned long TOUCH_LONGPRESS_MS = 550;

  // Latched one-frame synthesized press edges (mutable: update() is const but
  // owns this per-frame edge state, mirroring how it drives the non-const gpio).
  mutable bool tsConfirm = false;
  mutable bool tsBack = false;
  mutable bool tsNavNext = false;
  mutable bool tsNavPrev = false;
  mutable bool tsPageForward = false;
  mutable bool tsPageBack = false;
  // True once a long-press has fired Back for the current contact; suppresses the
  // tap-on-release that would otherwise also Confirm, and blocks a repeat Back.
  mutable bool longPressLatched = false;
};
