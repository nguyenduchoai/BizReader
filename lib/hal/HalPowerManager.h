#pragma once

#include <Arduino.h>
#include <BatteryMonitor.h>
#include <InputManager.h>
#include <Logging.h>
#include <Wire.h>
#include <freertos/semphr.h>

#include <cassert>

#include "HalGPIO.h"

class HalPowerManager;
extern HalPowerManager powerManager;  // Singleton

class HalPowerManager {
  int normalFreq = 0;  // MHz
  bool isLowPower = false;

  // I2C fuel gauge configuration for X3 battery monitoring
  bool _batteryUseI2C = false;                   // True if using I2C fuel gauge (X3), false for ADC (X4)
  mutable int _batteryCachedPercent = 0;         // Last read battery percentage (0-100)
  mutable unsigned long _batteryLastPollMs = 0;  // Timestamp of last battery read in milliseconds

  enum LockMode { None, NormalSpeed };
  LockMode currentLockMode = None;
  SemaphoreHandle_t modeMutex = nullptr;  // Protect access to currentLockMode

 public:
  static constexpr int LOW_POWER_FREQ = 10;  // MHz
  // How long to hold full CPU speed after the last user activity before clamping
  // to LOW_POWER_FREQ. The page render runs synchronously in activityManager.loop()
  // at full speed and the next input edge restores it before the next render, so
  // this window is pure post-render idle time — on the LilyGo EPD47 it was ~3 s of
  // ~70 mA (240 MHz + I2S) after every page turn before settling to the ~40 mA
  // idle floor. Shorten it there so the CPU downclocks right after the draw.
  // Xteink keeps the original 3 s (its bench/UX was tuned around it).
#if FREEINK_DEVICE_LILYGO_EPD47
  static constexpr unsigned long IDLE_POWER_SAVING_MS = 600;  // ms
#else
  static constexpr unsigned long IDLE_POWER_SAVING_MS = 3000;  // ms
#endif
  static constexpr unsigned long BATTERY_POLL_MS = 1500;  // ms

  void begin();

  // Defensively release gpio_hold latches a PREVIOUS build's sleep may have
  // left engaged (current builds hold nothing — bench-measured as useless).
  // MUST run before gpio.begin(): the GT911 wake pulse (INT driven HIGH) is
  // fired during touch bring-up, and a still-held-LOW INT pad swallows it —
  // the probe then NACKs and touch is dead for the session.
  void releaseSleepHolds();

  // Control CPU frequency for power saving
  void setPowerSaving(bool enabled);

  // Setup wake up GPIO and enter deep sleep
  // Should be called inside main loop() to handle the currentLockMode
  void startDeepSleep(HalGPIO& gpio) const;

  // Get battery percentage (range 0-100)
  uint16_t getBatteryPercentage() const;

  // RAII helper class to manage power saving locks
  // Usage: create an instance of Lock in a scope to disable power saving, for example when running a task that needs
  // full performance. When the Lock instance is destroyed (goes out of scope), power saving will be re-enabled.
  class Lock {
    friend class HalPowerManager;
    bool valid = false;

   public:
    explicit Lock();
    ~Lock();

    // Non-copyable and non-movable
    Lock(const Lock&) = delete;
    Lock& operator=(const Lock&) = delete;
    Lock(Lock&&) = delete;
    Lock& operator=(Lock&&) = delete;
  };
};
