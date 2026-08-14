# BizReader AGP 9 compatibility patch

This directory vendors `flutter_inappwebview_android` 1.1.3 from pub.dev.
BizReader changes only the Android ProGuard defaults in `android/build.gradle`:

- replace the removed `proguard-android.txt` default with
  `proguard-android-optimize.txt` for debug and release builds.
- add a regression test that prevents the legacy ProGuard default from being
  restored accidentally.

The local override keeps Android builds reproducible until upstream publishes a
stable release with the same AGP 9 compatibility fix. The upstream Apache-2.0
license is preserved in `LICENSE`.
