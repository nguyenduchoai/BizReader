#pragma once

#include <cstddef>
#include <cstdint>

// Limits expensive e-ink progress repaints while keeping transfers responsive.
// Call reset() after synchronously drawing the initial 0% frame.
class ProgressRenderThrottle final {
 public:
  static constexpr uint32_t DEFAULT_INTERVAL_MS = 1000;
  static constexpr uint8_t DEFAULT_PERCENT_STEP = 5;

  constexpr explicit ProgressRenderThrottle(const uint32_t intervalMs = DEFAULT_INTERVAL_MS,
                                            const uint8_t percentStep = DEFAULT_PERCENT_STEP)
      : intervalMs_(intervalMs), percentStep_(percentStep) {}

  void reset(const uint32_t nowMs) {
    lastRenderMs_ = nowMs;
    lastPercent_ = 0;
    initialized_ = true;
  }

  [[nodiscard]] bool shouldRender(const size_t completed, const size_t total, const uint32_t nowMs) {
    const uint8_t percent = percentage(completed, total);
    const bool firstUpdate = !initialized_;
    const bool reachedEnd = percent == 100 && lastPercent_ != 100;
    const bool percentAdvanced = percent > lastPercent_ && percent - lastPercent_ >= percentStep_;
    const bool intervalElapsed = initialized_ && nowMs - lastRenderMs_ >= intervalMs_;
    const bool progressReady = total == 0 ? intervalElapsed : (percentAdvanced && intervalElapsed);

    if (!firstUpdate && !reachedEnd && !progressReady) {
      return false;
    }

    lastRenderMs_ = nowMs;
    lastPercent_ = percent;
    initialized_ = true;
    return true;
  }

 private:
  static uint8_t percentage(const size_t completed, const size_t total) {
    if (total == 0) return 0;
    if (completed >= total) return 100;
    return static_cast<uint8_t>((static_cast<uint64_t>(completed) * 100U) / total);
  }

  uint32_t intervalMs_;
  uint8_t percentStep_;
  uint32_t lastRenderMs_ = 0;
  uint8_t lastPercent_ = 0;
  bool initialized_ = false;
};
