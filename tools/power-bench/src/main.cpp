// ---------------------------------------------------------------------------
// power-bench: standalone current-draw bench test for the LilyGo T5 ePaper
// 4.7" S3 v2.4 board (ESP32-S3-WROOM-1-N16R8).
//
// This file is INDEPENDENT of the main CrossPoint Reader firmware and the
// freeink-sdk. Raw Arduino + the vendor LilyGo-EPD47 library + Wire/SPI only.
//
// ---------------------------------------------------------------------------
// VERIFIED HARDWARE FACTS (confirmed by continuity probing on real v2.4
// hardware -- the vendor schematic is misleading in places, do not trust it
// over these notes):
//
//   EPD panel:
//     Driven through a 74HCT4094 shift register that gates the panel's
//     boost/linear power rails (LT1945 + regs) AND carries several of the
//     panel's own control lines:
//       DATA = GPIO13, CLK = GPIO12, STR = GPIO0
//     GPIO0 is the BOOT strap pin -- NEVER configure it as a runtime input.
//     The vendor library owns these pins internally; we only call its public
//     API (epd_init/epd_poweron/epd_clear/epd_poweroff/epd_poweroff_all).
//
//   GT911 capacitive touch (I2C):
//     SDA = GPIO18, SCL = GPIO17, INT = GPIO47, address 0x5D.
//     No reset line is routed on this board. The chip boots ASLEEP and does
//     not ACK on the I2C bus until INT is pulsed HIGH briefly (~10ms), then
//     released back to INPUT.
//     Sleep command: drive INT LOW, then write 3 bytes over I2C to register
//     0x8040: {0x80, 0x40, 0x05}. Verify sleep by re-probing address 0x5D --
//     a sleeping GT911 does not ACK (Wire.endTransmission() != 0).
//     Scanning GT911 is the prime suspect for excess current (~15-25mA).
//
//   PCF8563 RTC (I2C, same bus, address 0x51):
//     Present on the bus but intentionally left alone by this bench -- we
//     never talk to it. Noted here so the reader isn't surprised it exists.
//
//   SD card (SPI):
//     SCLK = GPIO11, MISO = GPIO16, MOSI = GPIO15, CS = GPIO42.
//     No filesystem mount needed for this bench -- we only bring the raw SPI
//     bus up/down to measure its own power draw.
//
//   Misc:
//     Battery ADC = GPIO14 (resistor divider, not used by this bench).
//     User button = GPIO21, active LOW, external pull-up present, RTC-capable
//     (used as the ext1 deep-sleep wake source, ANY_LOW).
// ---------------------------------------------------------------------------

#include <Arduino.h>
#include <Wire.h>
#include <SPI.h>
#include <epd_driver.h>
#include "esp_sleep.h"
#include "driver/rtc_io.h"
#include "driver/gpio.h"

// ---------------------------------------------------------------------------
// Pin map (see hardware facts above).
// ---------------------------------------------------------------------------
static constexpr int PIN_TOUCH_SDA = 18;
static constexpr int PIN_TOUCH_SCL = 17;
static constexpr int PIN_TOUCH_INT = 47;
static constexpr uint8_t GT911_ADDR = 0x5D;
static constexpr uint8_t PCF8563_ADDR = 0x51; // present on bus, untouched

static constexpr int PIN_SD_SCLK = 11;
static constexpr int PIN_SD_MISO = 16;
static constexpr int PIN_SD_MOSI = 15;
static constexpr int PIN_SD_CS = 42;

static constexpr int PIN_BATT_ADC = 14; // unused by this bench, noted only
static constexpr int PIN_BUTTON = 21;   // active LOW, ext1 wake source

// Shift-register pins that gate the EPD panel rails. The vendor library
// drives these internally; listed here only because MODE B's aggressive
// sleep configs explicitly hold them LOW to guarantee the shift register
// (and therefore the panel rails) stays off during deep sleep.
static constexpr int PIN_EPD_SR_DATA = 13;
static constexpr int PIN_EPD_SR_CLK = 12;
// NOTE: STR is GPIO0 (BOOT strap) -- intentionally NOT included in any pin
// hold list. Holding/driving GPIO0 at runtime risks interfering with the
// next boot's strap sampling on some revisions; the vendor driver leaves it
// idling HIGH and we do not touch it here.

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

// Pulse GT911 INT high briefly to wake it from its post-power-on sleep, then
// release the pin back to INPUT so the chip can drive it (it's an
// open-drain interrupt line in normal operation).
static void gt911WakeViaInt() {
  pinMode(PIN_TOUCH_INT, OUTPUT);
  digitalWrite(PIN_TOUCH_INT, HIGH);
  delay(10);
  pinMode(PIN_TOUCH_INT, INPUT);
  delay(10);
}

// Returns true if the GT911 ACKs on the bus (i.e. it is awake).
static bool gt911Probe() {
  Wire.beginTransmission(GT911_ADDR);
  uint8_t result = Wire.endTransmission();
  return result == 0;
}

// Put the GT911 to sleep: INT LOW, then write register 0x8040 = 0x05.
static void gt911Sleep() {
  pinMode(PIN_TOUCH_INT, OUTPUT);
  digitalWrite(PIN_TOUCH_INT, LOW);
  delay(5);
  Wire.beginTransmission(GT911_ADDR);
  Wire.write(0x80);
  Wire.write(0x40);
  Wire.write(0x05);
  Wire.endTransmission();
  delay(10);
}

#if BENCH_MODE == 0
// Park the SD SPI pins into a low-current, defined state after SPI.end().
// CS idle-high (deselected), SCLK idle-low, MOSI idle-high (SD spec idle).
// Only the ladder uses this now (the sleeptest SD configs were removed once SD
// was exonerated), so it's guarded to avoid an unused-function warning there.
static void parkSdPins() {
  pinMode(PIN_SD_CS, OUTPUT);
  digitalWrite(PIN_SD_CS, HIGH);
  pinMode(PIN_SD_SCLK, OUTPUT);
  digitalWrite(PIN_SD_SCLK, LOW);
  pinMode(PIN_SD_MOSI, OUTPUT);
  digitalWrite(PIN_SD_MOSI, HIGH);
}
#endif

static void flushBanner() {
  Serial.flush();
  delay(200); // let the USB-CDC marker actually land before anything tears down
}

static void armButtonWake() {
  esp_sleep_enable_ext1_wakeup(1ULL << PIN_BUTTON, ESP_EXT1_WAKEUP_ANY_LOW);
  rtc_gpio_pullup_en(static_cast<gpio_num_t>(PIN_BUTTON));
}

// ===========================================================================
// MODE A (BENCH_MODE=0): active-state incremental ladder.
//
// Each state ADDS to the previous and holds for LADDER_DWELL_MS so the human
// on the ammeter can read the delta caused by just that one addition. A big
// banner is printed (and flushed) before every state so there's no ambiguity
// about what's currently drawing current.
// ===========================================================================
#if BENCH_MODE == 0

#define LADDER_DWELL_MS 20000

static void bigBanner(int stateNum, const char *desc, uint32_t dwellMs) {
  Serial.printf("\n=== BENCH STATE %d: %s ===\n", stateNum, desc);
  Serial.printf(">>> MEASURE NOW, holding %lu s <<<\n", (unsigned long)(dwellMs / 1000));
  flushBanner();
}

static void dwell(uint32_t ms) {
  // Simple countdown so the serial log shows liveness without spamming.
  uint32_t elapsed = 0;
  const uint32_t step = 5000;
  while (elapsed < ms) {
    uint32_t chunk = (ms - elapsed) < step ? (ms - elapsed) : step;
    delay(chunk);
    elapsed += chunk;
    Serial.printf("    ...%lu s elapsed\n", (unsigned long)(elapsed / 1000));
  }
}

void setup() {
  Serial.begin(115200);
  delay(300); // USB-CDC enumeration settle

  Serial.println("\n\n########################################");
  Serial.println("# power-bench MODE A: active-state ladder");
  Serial.println("########################################");
  flushBanner();

  // --- STATE 0: baseline ---------------------------------------------------
  // CPU at default (240MHz), USB connected, nothing initialised yet, all
  // GPIOs at their reset default. This is the reference floor everything
  // else is measured as a delta against.
  bigBanner(0, "baseline: 240MHz CPU, USB up, nothing initialised", LADDER_DWELL_MS);
  dwell(LADDER_DWELL_MS);

  // --- STATE 1: CPU clamped to 10MHz ---------------------------------------
  setCpuFrequencyMhz(10);
  bigBanner(1, "+ CPU clamped to 10MHz (setCpuFrequencyMhz(10))", LADDER_DWELL_MS);
  dwell(LADDER_DWELL_MS);

  // Bring CPU back up before driving the panel -- the vendor EPD driver's
  // RMT/I2S timing assumes a normal clock; measuring panel power at 10MHz
  // would conflate two variables (CPU clock AND panel current) in one
  // reading, which defeats the point of an isolated ladder.
  setCpuFrequencyMhz(240);

  // --- STATE 2: EPD rails on -----------------------------------------------
  epd_init();
  epd_poweron();
  bigBanner(2, "+ CPU back to 240MHz; epd_init()+epd_poweron() -- panel rails ON", LADDER_DWELL_MS);
  dwell(LADDER_DWELL_MS);

  // --- STATE 3: panel drawn, rails staged-off -------------------------------
  epd_clear();
  epd_poweroff();
  bigBanner(3, "+ epd_clear() drawn, then epd_poweroff() -- rails staged-off", LADDER_DWELL_MS);
  dwell(LADDER_DWELL_MS);

  // --- STATE 4: vendor all-zeros latch --------------------------------------
  epd_poweroff_all();
  bigBanner(4, "+ epd_poweroff_all() -- vendor all-zeros shift-register latch", LADDER_DWELL_MS);
  dwell(LADDER_DWELL_MS);

  // --- STATE 5: GT911 awake and actively scanning ---------------------------
  Wire.begin(PIN_TOUCH_SDA, PIN_TOUCH_SCL);
  gt911WakeViaInt();
  bool awake = gt911Probe();
  Serial.printf("    GT911 probe after wake: %s\n", awake ? "ACK (awake)" : "NO ACK (unexpected)");
  bigBanner(5, "+ I2C up, GT911 woken (INT pulse) and actively scanning", LADDER_DWELL_MS);
  {
    // Poll during the dwell to keep the chip actively scanning (reading the
    // status register at 0x814E is the standard GT911 "is a touch ready"
    // poll and keeps the chip in active mode rather than idling towards its
    // own low-power state).
    uint32_t elapsed = 0;
    const uint32_t step = 5000;
    while (elapsed < LADDER_DWELL_MS) {
      uint32_t chunk = (LADDER_DWELL_MS - elapsed) < step ? (LADDER_DWELL_MS - elapsed) : step;
      uint32_t pollEnd = millis() + chunk;
      while (millis() < pollEnd) {
        Wire.beginTransmission(GT911_ADDR);
        Wire.write(0x81);
        Wire.write(0x4E);
        Wire.endTransmission(false);
        Wire.requestFrom(GT911_ADDR, (uint8_t)1);
        if (Wire.available()) Wire.read();
        delay(20); // ~50Hz poll, roughly matches typical touch scan cadence
      }
      elapsed += chunk;
      Serial.printf("    ...%lu s elapsed (still polling GT911)\n", (unsigned long)(elapsed / 1000));
    }
  }

  // --- STATE 6: GT911 asleep, verified --------------------------------------
  gt911Sleep();
  bool stillAwake = gt911Probe();
  bool verified = !stillAwake;
  Serial.printf("    GT911 sleep verify: re-probe %s -> sleep %s\n",
                stillAwake ? "ACKed" : "did not ACK",
                verified ? "CONFIRMED" : "FAILED");
  bigBanner(6, "+ GT911 put to sleep (INT low + 0x8040=0x05), verified above", LADDER_DWELL_MS);
  dwell(LADDER_DWELL_MS);

  // --- STATE 7: I2C bus down -------------------------------------------------
  Wire.end();
  bigBanner(7, "+ Wire.end() -- I2C bus torn down", LADDER_DWELL_MS);
  dwell(LADDER_DWELL_MS);

  // --- STATE 8: SD SPI bus up (no card mount) --------------------------------
  SPI.begin(PIN_SD_SCLK, PIN_SD_MISO, PIN_SD_MOSI, PIN_SD_CS);
  pinMode(PIN_SD_CS, OUTPUT);
  digitalWrite(PIN_SD_CS, HIGH); // deselected, but bus clocking is live
  bigBanner(8, "+ SD SPI.begin() -- raw bus up, no card mount", LADDER_DWELL_MS);
  dwell(LADDER_DWELL_MS);

  // --- STATE 9: SD SPI bus down, pins parked --------------------------------
  SPI.end();
  parkSdPins();
  bigBanner(9, "+ SPI.end() + SD pins parked (CS hi, SCLK lo, MOSI hi)", LADDER_DWELL_MS);
  dwell(LADDER_DWELL_MS);

  Serial.println("\nLADDER COMPLETE -- entering deep sleep (vendor-exact config)");
  flushBanner();

  // Vendor-exact deep sleep so the board doesn't sit hot on the bench after
  // the ladder finishes. Mirrors sleeptest config 0.
  epd_poweroff_all();
  gt911Sleep();
  Wire.end();
  armButtonWake();
  esp_deep_sleep_start();
}

void loop() {
  // never reached: setup() ends in esp_deep_sleep_start()
}

#endif // BENCH_MODE == 0

// ===========================================================================
// MODE B (BENCH_MODE=1): deep-sleep config comparison.
//
// An RTC_DATA_ATTR counter survives deep sleep and increments on every
// boot/wake. Each boot: print which config is about to be tested, dwell
// briefly awake, then deep-sleep using config[counter % NUM_SLEEP_CONFIGS].
// The user presses the GPIO21 button to wake (ext1), which advances the
// counter and re-enters sleep in the NEXT config -- so a human walks the
// whole config list with button taps, reading the ammeter between taps.
// ===========================================================================
#if BENCH_MODE == 1

#define AWAKE_DWELL_MS 8000

RTC_DATA_ATTR static uint32_t bootCounter = 0;

static constexpr int NUM_SLEEP_CONFIGS = 3;

static const char *sleepConfigName(int idx) {
  switch (idx) {
    case 0: return "0: BASELINE (EPD never powered on; epd_poweroff_all, GT911 sleep, Wire.end)";
    case 1: return "1: EPD POWERED ON + drawn, then epd_poweroff_all() [=demo.ino/firmware end, power_disable=false]";
    case 2: return "2: EPD POWERED ON + drawn, then epd_poweroff()     [power_disable=TRUE, rail actively cut]";
    default: return "?: unknown";
  }
}

// GT911 -> sleep + tear down the shared I2C bus. Shared common tail for every
// config (extracted so the EPD-powered configs can run their panel sequence
// first, then reuse the same touch/I2C teardown).
static void gt911SleepAndEndI2c() {
  Wire.begin(PIN_TOUCH_SDA, PIN_TOUCH_SCL);
  gt911WakeViaInt(); // must wake it first -- can't command-sleep a chip not ACKing
  gt911Sleep();
  bool stillAwake = gt911Probe();
  Serial.printf("    GT911 sleep verify: %s\n", stillAwake ? "FAILED (still ACKing)" : "CONFIRMED");
  Wire.end();
}

static void enterSleepConfig(int idx) {
  Serial.printf("\n=== ENTERING DEEP SLEEP CONFIG %s ===\n", sleepConfigName(idx));

  switch (idx) {
    case 0: {
      // BASELINE reference: panel initialised but NEVER powered on, latched off
      // with epd_poweroff_all(), GT911 asleep, I2C down. Previously measured
      // ~0.86 mA. Kept as the "everything quiet" floor to compare 1/2 against.
      epd_init();
      epd_poweroff_all();
      gt911SleepAndEndI2c();
      break;
    }
    case 1: {
      // Reproduce the firmware's REAL EPD state: actually power the panel ON
      // and draw, then end with epd_poweroff_all() -- the exact end latch the
      // firmware AND the vendor demo.ino use (power_disable=false). Decisive
      // test of whether powering the panel on leaves a leak poweroff_all can't
      // clear.
      epd_init();
      epd_poweron();
      epd_clear();
      epd_poweroff_all();
      gt911SleepAndEndI2c();
      break;
    }
    case 2: {
      // config 1, but end with epd_poweroff() instead -- sets power_disable=TRUE
      // (PWR_EN/QP5 actively cuts the rail) rather than the memset-0 that
      // poweroff_all leaves. If config 1 reads high and this reads low, the fix
      // is: after powering the panel on, the LAST panel op before sleep must be
      // epd_poweroff(), never epd_poweroff_all().
      epd_init();
      epd_poweron();
      epd_clear();
      epd_poweroff();
      gt911SleepAndEndI2c();
      break;
    }
    default:
      // Should not happen (idx is always % NUM_SLEEP_CONFIGS), but fail safe.
      epd_init();
      epd_poweroff_all();
      gt911SleepAndEndI2c();
      break;
  }

  armButtonWake();

  Serial.printf("Sleeping now in config: %s\n", sleepConfigName(idx));
  flushBanner();
  esp_deep_sleep_start();
}

void setup() {
  Serial.begin(115200);
  delay(300); // USB-CDC enumeration settle

  // bootCounter is RTC_DATA_ATTR: it survives deep sleep and starts at 0 only
  // on a fresh flash/power-up. On a fresh boot there is no prior sleep to
  // report. On every ext1-button wake, bootCounter already holds the index
  // of the config we just woke FROM (set right before that sleep call, on
  // the previous pass through this function), so report it, THEN advance.
  bool freshBoot = (bootCounter == 0) && (esp_sleep_get_wakeup_cause() == ESP_SLEEP_WAKEUP_UNDEFINED);
  int justMeasuredConfig = bootCounter % NUM_SLEEP_CONFIGS;

  Serial.println("\n\n########################################");
  Serial.println("# power-bench MODE B: deep-sleep config comparison");
  Serial.println("########################################");
  Serial.printf("RTC boot counter = %lu\n", (unsigned long)bootCounter);
  if (freshBoot) {
    Serial.println("First boot -- no prior sleep to report. About to test config 0 first.");
  } else {
    Serial.printf("You just woke from (and should have measured) config: %s\n",
                  sleepConfigName(justMeasuredConfig));
  }
  flushBanner();

  // Advance the counter now so the config we're about to sleep in is
  // "nextConfig" -- the button press that wakes us back up will re-enter
  // this same setup() with bootCounter already pointing at it.
  int nextConfig = freshBoot ? 0 : (justMeasuredConfig + 1) % NUM_SLEEP_CONFIGS;
  bootCounter = nextConfig;

  Serial.printf("\n>>> Awake dwell %d s, then entering sleep in config: %s <<<\n",
                AWAKE_DWELL_MS / 1000, sleepConfigName(nextConfig));
  Serial.printf(">>> PRESS BUTTON (GPIO%d) AFTER measuring that sleep to advance to the NEXT config <<<\n", PIN_BUTTON);
  flushBanner();

  delay(AWAKE_DWELL_MS);

  enterSleepConfig(nextConfig);
}

void loop() {
  // never reached: setup() ends in esp_deep_sleep_start()
}

#endif // BENCH_MODE == 1

#if BENCH_MODE != 0 && BENCH_MODE != 1
#error "BENCH_MODE must be defined as 0 (ladder) or 1 (sleeptest) -- see platformio.ini envs"
#endif
