"""Build the LilyGo firmware Corresponding Source archive.

The firmware build mutates some PlatformIO library working trees, so this
packages the resolved post-build sources instead of archiving their pristine
Git commits.  It also vendors the exact PlatformIO/Arduino sources and the
upstream inputs used to create Arduino's precompiled ESP-IDF libraries.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
import shutil
import subprocess
import tarfile
import tempfile
import urllib.parse
import urllib.request
import zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

PLATFORM_VERSION = "55.03.37"
PLATFORM_COMMIT = "a9fac0739db3490cf80bd06af22f72d0d7259768"
PLATFORM_URL = (
    "https://github.com/pioarduino/platform-espressif32/releases/download/"
    "55.03.37/platform-espressif32.zip"
)
PLATFORM_SHA256 = "ffce4a512581abd417c42edf2695a3b49e8b1447849847d3f62d0db695da9efc"

ARDUINO_VERSION = "3.3.7"
ARDUINO_PACKAGE_URL = (
    "https://github.com/espressif/arduino-esp32/releases/download/3.3.7/"
    "esp32-core-3.3.7.tar.xz"
)
ARDUINO_PACKAGE_SHA256 = (
    "9dd09b11ae75ba25b0610e76ff1265a4e59441cc5fdf3cb20dcd323904814186"
)
ARDUINO_LIBS_URL = (
    "https://github.com/espressif/arduino-esp32/releases/download/3.3.7/"
    "esp32-core-3.3.7-libs.tar.xz"
)
ARDUINO_LIBS_SHA256 = "a67e82c5af501db31261b37cae4cf0270b9c08a8d73b68d867f825669e85a2f6"

IDF_COMMIT = "87912cd291d68f4319f13695718af6754879a83f"
IDF_SOURCE_URL = (
    "https://github.com/pioarduino/esp-idf/releases/download/v5.5.2.260206/"
    "esp-idf-v5.5.2.tar.xz"
)
IDF_SOURCE_SHA256 = "00b1e7b52f0932d13b2736fee4667c6c36d27f8b4e03ee58e3eebd850060b922"
ARDUINO_LIB_BUILD_COMMIT = "86c2c0046d4c732aa7cf6e049ac3b76a4da148b3"
LIB_BUILDER_COMMIT = "8cabf2c3eaa169754f55f58675e224c918815eb7"
TINYUSB_COMMIT = "2883403ed010c54c33a38c28358a4dd0c67d67c0"
ESP32_CAMERA_COMMIT = "fb7b85b2b79fb039551c67d295e884d2b1eb907b"

PLATFORMIO_CORE_URL = (
    "https://github.com/pioarduino/platformio-core/archive/refs/tags/v6.1.19.zip"
)
XTENSA_TOOLCHAIN_VERSION = "14.2.0+20251107"
XTENSA_TOOLCHAIN_URL = (
    "https://github.com/pioarduino/registry/releases/download/0.0.1/"
    "xtensa-esp-elf-14.2.0_20251107.zip"
)

JPEGDEC_COMMIT = "86282979224c8a32fd51e091ed5a35b0c699a52b"
EPD47_COMMIT = "77387e337483be92186dee1e5ac6ad1d193ae16a"

UPSTREAM_ARCHIVES = (
    (
        "arduino-esp32-lib-build-source.tar.gz",
        "https://codeload.github.com/espressif/arduino-esp32/tar.gz/"
        + ARDUINO_LIB_BUILD_COMMIT,
        ARDUINO_LIB_BUILD_COMMIT,
    ),
    (
        "esp32-arduino-lib-builder-source.tar.gz",
        "https://codeload.github.com/espressif/esp32-arduino-lib-builder/tar.gz/"
        + LIB_BUILDER_COMMIT,
        LIB_BUILDER_COMMIT,
    ),
    (
        "tinyusb-source.tar.gz",
        "https://codeload.github.com/hathach/tinyusb/tar.gz/" + TINYUSB_COMMIT,
        TINYUSB_COMMIT,
    ),
    (
        "esp32-camera-source.tar.gz",
        "https://codeload.github.com/espressif/esp32-camera/tar.gz/"
        + ESP32_CAMERA_COMMIT,
        ESP32_CAMERA_COMMIT,
    ),
)

IGNORED_NAMES = {".DS_Store", "__pycache__", ".git"}


def run(*args: str, cwd: Path | None = None) -> str:
    return subprocess.check_output(args, cwd=cwd, text=True).strip()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(url: str, destination: Path, expected_sha256: str | None = None) -> str:
    request = urllib.request.Request(
        url, headers={"User-Agent": "BizReader-source-packager/1"}
    )
    with (
        urllib.request.urlopen(request, timeout=120) as response,
        destination.open("wb") as output,
    ):
        shutil.copyfileobj(response, output)
    actual = sha256(destination)
    if expected_sha256 and actual != expected_sha256:
        raise RuntimeError(
            f"SHA-256 mismatch for {url}: expected {expected_sha256}, got {actual}"
        )
    return actual


def copy_tree(
    source: Path, destination: Path, *, ignore_binaries: bool = False
) -> None:
    def ignored(_: str, names: list[str]) -> set[str]:
        result = {
            name for name in names if name in IGNORED_NAMES or name.endswith(".pyc")
        }
        if ignore_binaries:
            result.update(
                name for name in names if name.endswith((".a", ".bin", ".elf"))
            )
        return result

    shutil.copytree(source, destination, symlinks=False, ignore=ignored)


def extract_git_archive(repository: Path, destination: Path) -> str:
    commit = run("git", "rev-parse", "HEAD", cwd=repository)
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".tar") as archive:
        subprocess.run(
            ["git", "archive", "--format=tar", f"--output={archive.name}", "HEAD"],
            cwd=repository,
            check=True,
        )
        with tarfile.open(archive.name) as source:
            source.extractall(destination, filter="data")
    return commit


def load_piopm(package: Path) -> dict[str, Any]:
    return json.loads((package / ".piopm").read_text(encoding="utf-8"))


def check_package(package: Path, name: str, version: str, uri: str) -> None:
    metadata = load_piopm(package)
    if metadata.get("name") != name or metadata.get("version") != version:
        raise RuntimeError(f"Unexpected PlatformIO package at {package}: {metadata}")
    if metadata.get("spec", {}).get("uri") != uri:
        raise RuntimeError(f"Unexpected source URI for {name}: {metadata}")


def parse_component_lock(lock_path: Path) -> list[dict[str, str]]:
    entries: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    for line in lock_path.read_text(encoding="utf-8").splitlines():
        if line.startswith("  ") and not line.startswith("    ") and line.endswith(":"):
            current = {"name": line.strip()[:-1]}
            entries.append(current)
            in_source = False
        elif current is not None:
            if line.startswith("    component_hash: "):
                current["component_hash"] = line.split(": ", 1)[1].strip("'\"")
            elif line.startswith("    version: "):
                current["version"] = line.split(": ", 1)[1].strip("'\"")
            elif line == "    source:":
                in_source = True
            elif in_source and line.startswith("      type: "):
                current["type"] = line.split(": ", 1)[1].strip("'\"")
            elif in_source and line.startswith("      git: "):
                current["git"] = line.split(": ", 1)[1].strip("'\"")
    return entries


def fetch_registry_component(
    entry: dict[str, str], destination: Path
) -> dict[str, str]:
    quoted_name = urllib.parse.quote(entry["name"], safe="/")
    api_url = "https://components.espressif.com/api/components/" + quoted_name
    with urllib.request.urlopen(api_url, timeout=60) as response:
        metadata = json.load(response)
    versions = [
        item for item in metadata["versions"] if item["version"] == entry["version"]
    ]
    if len(versions) != 1:
        raise RuntimeError(
            f"Registry version not found: {entry['name']}@{entry['version']}"
        )
    version = versions[0]
    if version["component_hash"] != entry["component_hash"]:
        raise RuntimeError(
            f"Registry component hash changed: {entry['name']}@{entry['version']}"
        )

    safe_name = (
        entry["name"].replace("/", "__") + "-" + entry["version"].replace("~", "_")
    )
    archive_path = destination / f"{safe_name}.zip"
    checksums_path = destination / f"{safe_name}.CHECKSUMS.json"
    archive_sha = download(version["url"], archive_path)
    download(version["checksums"], checksums_path)

    checksums = json.loads(checksums_path.read_text(encoding="utf-8"))
    expected_files = {item["path"]: item for item in checksums["files"]}
    with zipfile.ZipFile(archive_path) as archive:
        actual_files = {name for name in archive.namelist() if not name.endswith("/")}
        if actual_files != set(expected_files):
            raise RuntimeError(f"Registry archive file list mismatch: {entry['name']}")
        for name, expected in expected_files.items():
            payload = archive.read(name)
            if len(payload) != expected["size"]:
                raise RuntimeError(
                    f"Registry file size mismatch: {entry['name']}:{name}"
                )
            if hashlib.sha256(payload).hexdigest() != expected["hash"]:
                raise RuntimeError(
                    f"Registry file hash mismatch: {entry['name']}:{name}"
                )

    return {
        "name": entry["name"],
        "version": entry["version"],
        "component_hash": entry["component_hash"],
        "archive": archive_path.name,
        "archive_sha256": archive_sha,
        "url": version["url"],
        "checksums_url": version["checksums"],
    }


def normalized_tar(source: Path, output: Path) -> None:
    temporary = output.with_suffix(output.suffix + ".tmp")
    with (
        temporary.open("wb") as raw,
        gzip.GzipFile(fileobj=raw, mode="wb", mtime=0) as compressed,
        tarfile.open(fileobj=compressed, mode="w") as archive,
    ):
        for path in sorted(source.rglob("*"), key=lambda item: item.as_posix()):
            relative = Path("BizReader-source") / path.relative_to(source)
            info = archive.gettarinfo(str(path), relative.as_posix())
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            info.mtime = 0
            if info.isfile():
                with path.open("rb") as payload:
                    archive.addfile(info, payload)
            else:
                archive.addfile(info)
    os.replace(temporary, output)


def write_file_checksums(root: Path) -> None:
    checksum_file = root / "FILES.sha256"
    lines = []
    for path in sorted(root.rglob("*"), key=lambda item: item.as_posix()):
        if path.is_file() and path != checksum_file:
            lines.append(f"{sha256(path)}  {path.relative_to(root).as_posix()}")
    checksum_file.write_text("\n".join(lines) + "\n", encoding="ascii")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--env", required=True, choices=("lilygo_release", "lilygo_release_rc")
    )
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--platformio-core-dir",
        type=Path,
        default=Path(
            os.environ.get("PLATFORMIO_CORE_DIR", Path.home() / ".platformio")
        ),
    )
    args = parser.parse_args()

    repository = Path(__file__).resolve().parents[1]
    if run("git", "status", "--porcelain", "--untracked-files=no", cwd=repository):
        raise RuntimeError(
            "Tracked project files must be clean before packaging a release"
        )
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    libdeps = repository / ".pio" / "libdeps" / args.env
    platform = args.platformio_core_dir / "platforms" / "espressif32"
    arduino = args.platformio_core_dir / "packages" / "framework-arduinoespressif32"
    arduino_libs = (
        args.platformio_core_dir / "packages" / "framework-arduinoespressif32-libs"
    )
    for required in (libdeps, platform, arduino, arduino_libs):
        if not required.is_dir():
            raise RuntimeError(
                f"Required post-build source tree is missing: {required}"
            )

    check_package(platform, "espressif32", "55.3.37", PLATFORM_URL)
    check_package(
        arduino, "framework-arduinoespressif32", ARDUINO_VERSION, ARDUINO_PACKAGE_URL
    )
    check_package(
        arduino_libs,
        "framework-arduinoespressif32-libs",
        "5.5.0+sha.87912cd291",
        ARDUINO_LIBS_URL,
    )

    with tempfile.TemporaryDirectory(
        prefix="bizreader-source-", dir=output.parent
    ) as temp_name:
        staging = Path(temp_name) / "BizReader-source"
        project = staging / "project"
        project_commit = extract_git_archive(repository, project)
        freeink = repository / "freeink-sdk"
        freeink_commit = extract_git_archive(freeink, project / "freeink-sdk")
        lucide = freeink / "libs" / "assets" / "Icons" / "lucide"
        lucide_commit = extract_git_archive(
            lucide, project / "freeink-sdk" / "libs" / "assets" / "Icons" / "lucide"
        )

        resolved = staging / "resolved-platformio-libdeps"
        resolved.mkdir(parents=True)
        for dependency in sorted(libdeps.iterdir(), key=lambda item: item.name):
            if dependency.is_dir():
                copy_tree(dependency, resolved / dependency.name)
            elif dependency.name == "integrity.dat":
                shutil.copy2(dependency, resolved / dependency.name)

        jpeg = libdeps / "JPEGDEC"
        epd47 = libdeps / "LilyGo-EPD47"
        if run("git", "rev-parse", "HEAD", cwd=jpeg) != JPEGDEC_COMMIT:
            raise RuntimeError("Unexpected JPEGDEC revision")
        if run("git", "rev-parse", "HEAD", cwd=epd47) != EPD47_COMMIT:
            raise RuntimeError("Unexpected LilyGo-EPD47 revision")
        if set(run("git", "diff", "--name-only", cwd=jpeg).splitlines()) != {
            "src/jpeg.inl"
        }:
            raise RuntimeError("Expected resolved JPEGDEC patch is missing or changed")
        if set(run("git", "diff", "--name-only", cwd=epd47).splitlines()) != {
            "library.json"
        }:
            raise RuntimeError(
                "Expected resolved LilyGo-EPD47 patch is missing or changed"
            )

        toolchain_sources = staging / "toolchain-sources"
        copy_tree(platform, toolchain_sources / "platform-espressif32-55.03.37")
        copy_tree(arduino, toolchain_sources / "framework-arduinoespressif32-3.3.7")
        metadata_root = toolchain_sources / "framework-arduinoespressif32-libs-metadata"
        metadata_root.mkdir()
        shutil.copy2(arduino_libs / "package.json", metadata_root / "package.json")
        shutil.copy2(arduino_libs / ".piopm", metadata_root / ".piopm")
        shutil.copy2(arduino_libs / "versions.txt", metadata_root / "versions.txt")
        copy_tree(
            arduino_libs / "esp32s3", metadata_root / "esp32s3", ignore_binaries=True
        )

        upstream = staging / "upstream-source-archives"
        upstream.mkdir()
        idf_archive = upstream / "esp-idf-v5.5.2.260206-source.tar.xz"
        download(IDF_SOURCE_URL, idf_archive, IDF_SOURCE_SHA256)
        upstream_manifest: list[dict[str, str]] = [
            {
                "name": "esp-idf",
                "commit": IDF_COMMIT,
                "url": IDF_SOURCE_URL,
                "archive": idf_archive.name,
                "sha256": IDF_SOURCE_SHA256,
            }
        ]
        for filename, url, commit in UPSTREAM_ARCHIVES:
            archive = upstream / filename
            digest = download(url, archive)
            upstream_manifest.append(
                {
                    "name": filename.removesuffix("-source.tar.gz"),
                    "commit": commit,
                    "url": url,
                    "archive": filename,
                    "sha256": digest,
                }
            )

        lock_path = arduino_libs / "esp32s3" / "dependencies.lock"
        component_entries = [
            entry
            for entry in parse_component_lock(lock_path)
            if entry.get("type") == "service"
        ]
        registry_sources = upstream / "esp-idf-managed-components"
        registry_sources.mkdir()
        with ThreadPoolExecutor(max_workers=8) as executor:
            registry_manifest = list(
                executor.map(
                    lambda entry: fetch_registry_component(entry, registry_sources),
                    component_entries,
                )
            )
        registry_manifest.sort(key=lambda item: item["name"])

        manifest = {
            "format": 1,
            "platformio_environment": args.env,
            "project": {"commit": project_commit},
            "submodules": {"freeink-sdk": freeink_commit, "lucide": lucide_commit},
            "resolved_dependencies": {
                "JPEGDEC": JPEGDEC_COMMIT,
                "LilyGo-EPD47": EPD47_COMMIT,
            },
            "platform": {
                "version": PLATFORM_VERSION,
                "commit": PLATFORM_COMMIT,
                "url": PLATFORM_URL,
                "sha256": PLATFORM_SHA256,
            },
            "arduino_framework": {
                "version": ARDUINO_VERSION,
                "package_url": ARDUINO_PACKAGE_URL,
                "package_sha256": ARDUINO_PACKAGE_SHA256,
            },
            "arduino_precompiled_libraries": {
                "binary_package_url": ARDUINO_LIBS_URL,
                "binary_package_sha256": ARDUINO_LIBS_SHA256,
                "esp_idf_commit": IDF_COMMIT,
                "arduino_commit": ARDUINO_LIB_BUILD_COMMIT,
                "lib_builder_commit": LIB_BUILDER_COMMIT,
            },
            "upstream_source_archives": upstream_manifest,
            "managed_components": registry_manifest,
            "build_tools_not_conveyed": {
                "platformio_core": {"version": "v6.1.19", "url": PLATFORMIO_CORE_URL},
                "toolchain_xtensa_esp_elf": {
                    "version": XTENSA_TOOLCHAIN_VERSION,
                    "url": XTENSA_TOOLCHAIN_URL,
                },
            },
        }
        (staging / "SOURCE_MANIFEST.json").write_text(
            json.dumps(manifest, ensure_ascii=True, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        (staging / "README-CORRESPONDING-SOURCE.md").write_text(
            "# BizReader LilyGo Corresponding Source\n\n"
            "This archive is the source paired with one LilyGo firmware artifact. It contains "
            "the committed BizReader tree and recursive submodules, the resolved post-build "
            "PlatformIO libraries (including applied JPEGDEC and EPD47 patches), the exact "
            "PlatformIO platform and Arduino framework source packages, and the pinned inputs "
            "used to rebuild Arduino's ESP-IDF libraries.\n\n"
            "Verify the pins and archive hashes in `SOURCE_MANIFEST.json`. A normal firmware "
            "build can use PlatformIO Core v6.1.19 and the pinned binary library package listed "
            "there. To rebuild those libraries from source, use the included lib-builder, "
            "Arduino, ESP-IDF, TinyUSB, camera, and managed-component archives with the "
            "`esp32s3` configuration and lock files under "
            "`toolchain-sources/framework-arduinoespressif32-libs-metadata`.\n",
            encoding="ascii",
        )

        write_file_checksums(staging)

        normalized_tar(staging, output)
    print(f"Created {output} ({output.stat().st_size} bytes, sha256 {sha256(output)})")


if __name__ == "__main__":
    main()
