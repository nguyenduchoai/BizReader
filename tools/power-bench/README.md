# power-bench

Standalone PlatformIO project for bench-measuring the current draw of the
**LilyGo T5 ePaper 4.7" S3 v2.4** board (ESP32-S3-WROOM-1-N16R8), peripheral
by peripheral and deep-sleep config by deep-sleep config.

**This project is fully independent of the main CrossPoint Reader firmware.**
It does not use `freeink-sdk`, `lib/hal`, or anything else from the parent
repo. It links only:
- Arduino core (`framework = arduino`)
- the vendor [LilyGo-EPD47](https://github.com/Xinyuan-LilyGO/LilyGo-EPD47)
  panel driver library
- `Wire` (I2C) and `SPI`, both bundled with the Arduino core

Do not add dependencies on the parent repo's code to this project.

## Hardware setup

Put a bench ammeter (or a multimeter in current mode, or a USB power meter
with a current readout) **in series** with the board's power input — either
in series with the battery lead, or in series with the 5V USB supply line if
you're powering it that way and can tolerate the USB regulator's own quiescent
draw being folded into every reading (it's constant, so deltas between states
are still valid).

## Two bench modes

Mode is selected at build time via `-DBENCH_MODE`, wired up as two PlatformIO
environments so you never have to hand-edit a flag:

| Environment       | BENCH_MODE | What it measures                                |
|--------------------|-----------|--------------------------------------------------|
| `env:ladder`       | 0         | Active-state incremental ladder (peripherals ON)  |
| `env:sleeptest`    | 1         | Deep-sleep floor per sleep configuration           |

### Build

```bash
cd tools/power-bench

# Mode A: active-state ladder
pio run -e ladder

# Mode B: deep-sleep config comparison
pio run -e sleeptest
```

### Flash

```bash
# pick whichever env you just built
pio run -e ladder     -t upload
pio run -e sleeptest  -t upload
```

(Or use your normal `pio run -e <env> -t upload --upload-port <port>` if you
need to pin the port explicitly.)

### Monitor

```bash
pio device monitor -b 115200
```

---

## MODE A: active-state ladder (`env:ladder`)

On boot, the firmware walks through a fixed sequence of states. **Each state
ADDS to the previous** — nothing already turned on is turned back off before
the next state begins — so the current you read at each step is the
*cumulative* draw of everything enabled so far. Read the **delta** from the
previous step to attribute current to that one specific peripheral/action.

Each state prints a large banner to serial and flushes it before the dwell
begins, so you can align the ammeter reading with the log:

```
=== BENCH STATE N: <description> ===
>>> MEASURE NOW, holding 20 s <<<
```

Default dwell is 20 seconds per state (`LADDER_DWELL_MS` in `src/main.cpp`).

At the end of the ladder the board deep-sleeps in the vendor-exact
configuration (same as sleeptest config 0) so it doesn't sit hot on the bench.
Press the button (GPIO21) or power-cycle to run the ladder again.

### Ladder states (fill in your measurements)

| State | Description | Measured current |
|-------|-------------|-------------------|
| 0 | Baseline: 240MHz CPU, USB connected, nothing initialised, GPIOs at reset default | |
| 1 | + CPU clamped to 10MHz (`setCpuFrequencyMhz(10)`) | |
| 2 | + CPU back to 240MHz; `epd_init()` + `epd_poweron()` — panel rails ON | |
| 3 | + `epd_clear()` drawn, then `epd_poweroff()` — rails staged-off | |
| 4 | + `epd_poweroff_all()` — vendor all-zeros shift-register latch | |
| 5 | + I2C up, GT911 woken (INT pulse) and actively polled/scanning | |
| 6 | + GT911 put to sleep (INT low + reg 0x8040=0x05), sleep verified | |
| 7 | + `Wire.end()` — I2C bus torn down | |
| 8 | + SD `SPI.begin()` — raw bus up, no card mounted | |
| 9 | + `SPI.end()` + SD pins parked (CS hi, SCLK lo, MOSI hi) | |

---

## MODE B: deep-sleep config comparison (`env:sleeptest`)

An `RTC_DATA_ATTR` counter survives deep sleep and tracks which config is
active. On each boot/wake:

1. Prints the RTC counter and which config you just measured (or, on a truly
   fresh boot, that there's nothing to report yet).
2. Prints an awake banner: `PRESS BUTTON TO ADVANCE TO NEXT CONFIG after
   measuring THIS sleep`, dwells 8 seconds awake (`AWAKE_DWELL_MS`).
3. Enters deep sleep using the next config in the list.
4. You read the ammeter during the sleep period (this is the number you
   want), then press the button (GPIO21, active LOW) to wake it via `ext1`.
   Waking advances the counter and it re-enters sleep in the *next* config.

Repeat until you've cycled through all 5 configs, then the sequence wraps
back to config 0.

### Sleep configs (fill in your measurements)

| Config | Description | Measured current |
|--------|-------------|-------------------|
| 0 | VENDOR-EXACT: `epd_poweroff_all()`; GT911 woken then slept + verified; `Wire.end()`; no SD handling; no GPIO holds; no isolate; ext1 wake on GPIO21 + RTC pullup | |
| 1 | config 0 + SD parked (`SPI.end()`, CS hi, SCLK lo, MOSI hi) | |
| 2 | config 1 + `gpio_deep_sleep_hold_en()` + explicit holds on GPIO12/13/47 (LOW) and GPIO42/15 (HIGH), GPIO11 (LOW) | |
| 3 | config 2 + `esp_sleep_config_gpio_isolate()` called before the holds | |
| 4 | Isolate-only: `esp_sleep_config_gpio_isolate()` + `gpio_deep_sleep_hold_en()`, NO manual per-pin holds; GT911 slept, SD parked | |

---

## Verified hardware facts this project depends on

(Confirmed by continuity probing on real v2.4 hardware — the vendor schematic
is misleading in places; trust these notes over it.)

- **MCU**: ESP32-S3-WROOM-1-N16R8. `board = esp32-s3-devkitc1-n16r8`,
  `board_build.mcu = esp32s3`, `flash_mode = qio`,
  `arduino.memory_type = qio_opi`. PSRAM is OPI, 8MB.
- **EPD panel**: driven through a 74HCT4094 shift register —
  DATA=GPIO13, CLK=GPIO12, STR=GPIO0. GPIO0 is the BOOT strap pin and must
  **never** be used as a runtime input. The shift register gates the panel's
  boost/linear power rails (LT1945 + regs). Only the vendor library's public
  API is used: `epd_init()`, `epd_poweron()`, `epd_poweroff()`,
  `epd_poweroff_all()`, `epd_clear()`.
- **GT911 touch**: I2C SDA=GPIO18, SCL=GPIO17, INT=GPIO47, address `0x5D`.
  No reset line routed. Boots asleep; wake by pulsing INT HIGH ~10ms then
  releasing to INPUT. Sleep by driving INT LOW then writing register
  `0x8040 = 0x05` (bytes `0x80, 0x40, 0x05`). Verify sleep by re-probing
  `0x5D` — a sleeping GT911 does not ACK. GT911 scanning is the prime
  suspect for ~15-25mA of otherwise-unexplained current.
- **PCF8563 RTC**: same I2C bus, address `0x51`. Present but intentionally
  untouched by this bench.
- **SD card SPI**: SCLK=GPIO11, MISO=GPIO16, MOSI=GPIO15, CS=GPIO42. No
  filesystem mount is needed — this bench only brings the raw SPI bus
  up/down to measure its own current.
- **Battery ADC**: GPIO14 (divider), not used by this bench.
- **User button**: GPIO21, active LOW, external pull-up present, RTC-capable
  — used as the `ext1` deep-sleep wake source (`ESP_EXT1_WAKEUP_ANY_LOW`)
  with `rtc_gpio_pullup_en()` so the line has a defined level in deep sleep.

## Notes on the build

- `-include esp_idf_version.h` is **required**: the vendor library's
  `rmt_pulse.c` checks `ESP_IDF_VERSION_MAJOR` before the header that
  normally defines it gets pulled in, on this IDF/Arduino-core combination.
  Without the pre-include, it mis-selects the legacy RMT include path and
  fails to build.
- No `patch_epd47.py`-style `srcFilter` script is used here (unlike the main
  firmware). The main firmware needs one because it also links PNGdec, whose
  bundled zlib collides with the vendor library's own bundled zlib at link
  time. This project has no PNGdec (or any other zlib consumer) at all, so
  the vendor library's bundled `zlib/`, `libjpeg/`, `font.c`, and `touch.cpp`
  objects are simply never referenced by anything and the linker drops them
  — nothing to collide with. Keep it that way: don't add PNGdec or another
  zlib-linking dependency to this project without re-adding a trim step.
