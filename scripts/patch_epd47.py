"""
PlatformIO pre-build script: trim the LilyGo-EPD47 libdep to its panel driver.

Upstream LilyGo-EPD47 ships bundled copies of zlib and libjpeg plus a font
renderer (font.c) and an old touch class for its demos. CrossPoint only needs
the four panel-driver sources (epd_driver.c, ed047tc1.c, i2s_data_bus.c,
rmt_pulse.c); the bundled zlib duplicates the copy inside PNGdec and collides
at link time (multiple definition of adler32/crc32/inflate*). This script
writes a build.srcFilter into the installed libdep's library.json so only the
driver compiles. Idempotent: rewrites the manifest only when the filter is
missing or different.
"""

Import("env")  # noqa: F821 (SCons-injected global)
import json
import os

SRC_FILTER = [
    "+<*.c>",
    "+<*.h>",
    "-<font.c>",
    "-<touch.cpp>",
    "-<zlib/>",
    "-<libjpeg/>",
]


def patch_epd47(env):
    libdeps_dir = os.path.join(env["PROJECT_DIR"], ".pio", "libdeps")
    if not os.path.isdir(libdeps_dir):
        return
    for env_dir in os.listdir(libdeps_dir):
        manifest_path = os.path.join(libdeps_dir, env_dir, "LilyGo-EPD47", "library.json")
        if not os.path.isfile(manifest_path):
            continue
        with open(manifest_path, "r", encoding="utf-8") as f:
            manifest = json.load(f)
        build = manifest.setdefault("build", {})
        if build.get("srcFilter") == SRC_FILTER:
            continue
        build["srcFilter"] = SRC_FILTER
        with open(manifest_path, "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=2)
            f.write("\n")
        print("Trimmed LilyGo-EPD47 to panel-driver sources: %s" % manifest_path)


patch_epd47(env)  # noqa: F821
