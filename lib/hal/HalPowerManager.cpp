#include "HalPowerManager.h"

#include <Logging.h>
#include <PowerManager.h>
#include <WiFi.h>
#include <esp_sleep.h>

#include <cassert>

#include "HalGPIO.h"
#if FREEINK_DEVICE_LILYGO_EPD47
#include <Wire.h>
#include <driver/gpio.h>
#endif

HalPowerManager powerManager;  // Singleton instance

void HalPowerManager::releaseSleepHolds() {
#if FREEINK_DEVICE_LILYGO_EPD47
  // This firmware no longer engages gpio holds for sleep (bench-measured as
  // useless — see startDeepSleep), but a device that entered deep sleep on an
  // OLDER build still has its holds latched across the wake. Release them
  // defensively; a no-op when nothing is held. Must stay BEFORE gpio.begin()
  // in setup(): a still-held-LOW GT911 INT pad swallows the touch wake pulse.
  gpio_deep_sleep_hold_dis();
  for (const gpio_num_t p : {GPIO_NUM_11, GPIO_NUM_12, GPIO_NUM_13, GPIO_NUM_15, GPIO_NUM_42, GPIO_NUM_47}) {
    gpio_hold_dis(p);
  }
#endif
}

void HalPowerManager::begin() {
  // NOTE: releaseSleepHolds() must already have run (setup() calls it before
  // gpio.begin(); this begin() runs after gpio.begin() and would be too late).
#if CROSSPOINT_HW_XTEINK
  if (gpio.deviceIsX3()) {
    // X3 uses an I2C fuel gauge for battery monitoring.
    // I2C init must come AFTER gpio.begin() so early hardware detection/probes are finished.
    Wire.begin(X3_I2C_SDA, X3_I2C_SCL, X3_I2C_FREQ);
    Wire.setTimeOut(4);
    _batteryUseI2C = true;
  } else {
    pinMode(BAT_GPIO0, INPUT);
  }
#endif
  normalFreq = getCpuFrequencyMhz();
  modeMutex = xSemaphoreCreateMutex();
  assert(modeMutex != nullptr);

  // NOTE (LilyGo): do NOT arm esp_sleep_enable_gpio_wakeup()/gpio_wakeup_enable
  // here for light sleep. The armed source persists into esp_deep_sleep_start(),
  // and with the GT911 INT (GPIO47) deliberately held LOW for touch sleep the
  // wake condition is permanently true — the device instant-wakes out of deep
  // sleep in a boot loop. The esp_pm light-sleep governor was also tried and
  // reverted: a held PM lock (USB-CDC) kept it from ever sleeping, so it just
  // ran DFS at max — worse than the 10 MHz idle clamp it replaced.
}

void HalPowerManager::setPowerSaving(bool enabled) {
  if (normalFreq <= 0) {
    return;  // invalid state
  }

  auto wifiMode = WiFi.getMode();
  if (wifiMode != WIFI_MODE_NULL) {
    // Wifi is active, force disabling power saving
    enabled = false;
  }

  // Note: We don't use mutex here to avoid too much overhead,
  // it's not very important if we read a slightly stale value for currentLockMode
  const LockMode mode = currentLockMode;

  if (mode == None && enabled && !isLowPower) {
    LOG_DBG("PWR", "Going to low-power mode");
    if (!setCpuFrequencyMhz(LOW_POWER_FREQ)) {
      LOG_DBG("PWR", "Failed to set CPU frequency = %d MHz", LOW_POWER_FREQ);
      return;
    }
    isLowPower = true;

  } else if ((!enabled || mode != None) && isLowPower) {
    LOG_DBG("PWR", "Restoring normal CPU frequency");
    if (!setCpuFrequencyMhz(normalFreq)) {
      LOG_DBG("PWR", "Failed to set CPU frequency = %d MHz", normalFreq);
      return;
    }
    isLowPower = false;
  }

  // Otherwise, no change needed
}

void HalPowerManager::startDeepSleep(HalGPIO& gpio) const {
  // Ensure that the power button has been released to avoid immediately turning back on if you're holding it
  while (gpio.isPressed(HalGPIO::BTN_POWER)) {
    delay(50);
    gpio.update();
  }

#if FREEINK_DEVICE_LILYGO_EPD47
  // Quiesce the GT911 (bench-measured: an awake GT911 adds ~5 mA through deep
  // sleep) while the I2C bus is still alive, then release the bus — the exact
  // sequence the vendor demo uses. Deliberately NOTHING else: SD pin parking
  // and gpio holds were bench-measured on this board (tools/power-bench) to
  // add ~330 uA / save nothing, and the plain vendor-style sleep below reads
  // ~0.86 mA with the SD card mounted and all pads floating.
  gpio.touchSleep();  // logs verified/FAILED
  Wire.end();
  // Keep the GT911 INT line LOW through deep sleep with the internal PULLDOWN,
  // NOT a gpio hold. Two bench-established facts force this choice:
  //  - INT floating (from touchSleep's driven-LOW) can drift high; a LOW->HIGH
  //    edge is the GT911's documented wake trigger, and an awake GT911 is the
  //    "~5 mA with bursty spikes" sleep signature.
  //  - gpio_hold_en(47) needs gpio_deep_sleep_hold_en(), which freezes EVERY
  //    driven digital pad — including the EPD bus lines the vendor driver
  //    leaves HIGH after the sleep-cover draw (STH et al). Those then
  //    back-power the unpowered panel through its input protection diodes,
  //    ~15 mA all through sleep: the root cause of the recurring 20 mA reads
  //    (present in every build that called gpio_deep_sleep_hold_en).
  // GPIO47 is not an RTC pad, so the pulldown relies on
  // CONFIG_ESP_SLEEP_GPIO_ENABLE_INTERNAL_RESISTORS=y (set in the prebuilt
  // Arduino sdkconfig) to persist into deep sleep.
  gpio_set_direction(GPIO_NUM_47, GPIO_MODE_INPUT);
  gpio_pullup_dis(GPIO_NUM_47);
  gpio_pulldown_en(GPIO_NUM_47);
  // Last serial breadcrumb: if this prints but sleep current is high, the draw
  // is an external chip; if it does NOT print, the sleep path hung above and
  // the CPU is spinning awake (which reads like ~20 mA on the meter).
  LOG_INF("PWR", "Sleep quiesce done (touch, I2C); entering deep sleep");
#ifdef ENABLE_SERIAL_LOG
  // Push the touch/quiesce breadcrumbs out before the CDC teardown below:
  // esp_deep_sleep_start() follows immediately, so anything still sitting in the
  // USB-CDC TX buffer (the GT911 sleep status line in particular) is lost. The
  // background CDC flush task won't get a tick in that window; force it.
  logSerial.flush();
  delay(60);
#endif
#endif

#ifdef ENABLE_SERIAL_LOG
  // Tear down HWCDC so the host sees a clean disconnect and the peripheral
  // doesn't hold power domains that interfere with USB-powered GPIO wake.
  // logSerial is the raw HWCDC reference; Serial is the MySerialImpl proxy
  // (which doesn't expose end()).
  logSerial.end();
#endif

#if CROSSPOINT_HW_XTEINK
  // Pre-sleep routines from the original firmware
  // GPIO13 is connected to battery latch MOSFET, we need to make sure it's low during sleep
  // Note that this means the MCU will be completely powered off during sleep, including RTC
  // (Xteink only — on the LilyGo T5 EPD47, GPIO13 is the EPD shift-register data line.)
  constexpr gpio_num_t GPIO_SPIWP = GPIO_NUM_13;
  gpio_set_direction(GPIO_SPIWP, GPIO_MODE_OUTPUT);
  gpio_set_level(GPIO_SPIWP, 0);
  esp_sleep_config_gpio_isolate();
  gpio_deep_sleep_hold_en();
  gpio_hold_en(GPIO_SPIWP);
#elif FREEINK_DEVICE_LILYGO_EPD47
  // Deliberately NO esp_sleep_config_gpio_isolate() and no gpio holds beyond
  // the single GT911 INT hold engaged above. Bench-measured on real v2.4
  // hardware (tools/power-bench): the plain vendor-style sleep — EPD latched
  // all-zeros, GT911 slept, pads left to float — reads ~0.86 mA; blanket
  // holds/isolate saved nothing, and SD pin parking made it WORSE (+330 uA).
  // The earlier floating-CFG-line artifact/brownout theory was disproven by
  // the same bench (config 0 slept stably with everything floating).
#else
  esp_sleep_config_gpio_isolate();
  gpio_deep_sleep_hold_en();
#endif
  // Arm the wakeup trigger *after* the button is released. PowerManager sets the
  // matching pull on the power pin and picks the SoC-correct wake source (gpio on
  // C3, RTC ext1 on S3) from BoardConfig::ACTIVE.
  // Note: on Xteink this is only useful for waking up on USB power. On battery, the MCU will be completely powered
  // off, so the power button is hard-wired to briefly provide power to the MCU, waking it up regardless of the wakeup
  // source configuration
  freeink::PowerManager::armPowerButtonWakeup();
  // Enter Deep Sleep
  esp_deep_sleep_start();
}

uint16_t HalPowerManager::getBatteryPercentage() const {
#if CROSSPOINT_HW_XTEINK
  if (_batteryUseI2C) {
    const unsigned long now = millis();
    if (_batteryLastPollMs != 0 && (now - _batteryLastPollMs) < BATTERY_POLL_MS) {
      return _batteryCachedPercent;
    }

    // Read SOC directly from I2C fuel gauge (16-bit LE register).
    // On I2C error, keep last known value to avoid UI jitter/slowdowns.
    Wire.beginTransmission(I2C_ADDR_BQ27220);
    Wire.write(BQ27220_SOC_REG);
    if (Wire.endTransmission(false) != 0) {
      _batteryLastPollMs = now;
      return _batteryCachedPercent;
    }
    Wire.requestFrom(I2C_ADDR_BQ27220, (uint8_t)2);
    if (Wire.available() < 2) {
      _batteryLastPollMs = now;
      return _batteryCachedPercent;
    }
    const uint8_t lo = Wire.read();
    const uint8_t hi = Wire.read();
    const uint16_t soc = (hi << 8) | lo;
    _batteryCachedPercent = soc > 100 ? 100 : soc;
    _batteryLastPollMs = now;
    return _batteryCachedPercent;
  }
#endif
  // Profile-driven: pin + divider come from BoardConfig::ACTIVE (X4: GPIO0 x2.0,
  // LilyGo T5 EPD47: GPIO14 x2.0).
  static const BatteryMonitor battery = BatteryMonitor();

  // smooth the battery %.
  if (_batteryCachedPercent == 0) {
    _batteryCachedPercent = 10 * battery.readPercentage();
  } else {
    _batteryCachedPercent = (_batteryCachedPercent * 9 + battery.readPercentage() * 10) / 10;
  }
  return _batteryCachedPercent / 10;
}

HalPowerManager::Lock::Lock() {
  xSemaphoreTake(powerManager.modeMutex, portMAX_DELAY);
  // Current limitation: only one lock at a time
  if (powerManager.currentLockMode != None) {
    LOG_ERR("PWR", "Lock already held, ignore");
    valid = false;
  } else {
    powerManager.currentLockMode = NormalSpeed;
    valid = true;
  }
  xSemaphoreGive(powerManager.modeMutex);
  if (valid) {
    // Immediately restore normal CPU frequency if currently in low-power mode
    powerManager.setPowerSaving(false);
  }
}

HalPowerManager::Lock::~Lock() {
  xSemaphoreTake(powerManager.modeMutex, portMAX_DELAY);
  if (valid) {
    powerManager.currentLockMode = None;
  }
  xSemaphoreGive(powerManager.modeMutex);
}
