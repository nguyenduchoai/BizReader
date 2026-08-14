import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registered = false;

void registerBizReaderLicenses() {
  if (_registered) return;
  _registered = true;

  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString(
      'android/app/src/main/assets/viewer/GANDER_LICENSE.txt',
    );
    yield LicenseEntryWithLineBreaks(const ['Gander'], license);
  });
  LicenseRegistry.addLicense(() async* {
    final notices = await rootBundle.loadString(
      'android/app/src/main/assets/viewer/VENDORED_NOTICES.md',
    );
    yield LicenseEntryWithLineBreaks(const [
      'BizReader vendored viewers',
    ], notices);
  });
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString(
      'packages/flutter_epub_viewer/LICENSE',
    );
    yield LicenseEntryWithLineBreaks(const [
      'flutter_epub_viewer (BizReader hardened fork)',
    ], license);
  });
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString(
      'packages/flutter_epub_viewer/EPUBJS_LICENSE',
    );
    yield LicenseEntryWithLineBreaks(const ['epub.js 0.3.93'], license);
  });
  LicenseRegistry.addLicense(() async* {
    final notices = await rootBundle.loadString(
      'packages/flutter_epub_viewer/EPUBJS_THIRD_PARTY_NOTICES.md',
    );
    yield LicenseEntryWithLineBreaks(const [
      'epub.js bundled runtime dependencies',
    ], notices);
  });
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString(
      'packages/flutter_epub_viewer/JSZIP_LICENSE',
    );
    yield LicenseEntryWithLineBreaks(const ['JSZip 3.10.1'], license);
  });
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString(
      'packages/flutter_epub_viewer/PAKO_LICENSE',
    );
    yield LicenseEntryWithLineBreaks(const ['pako 1.0.5'], license);
  });
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString(
      'packages/flutter_inappwebview_android/LICENSE',
    );
    yield LicenseEntryWithLineBreaks(const [
      'flutter_inappwebview_android (BizReader AGP 9 patch)',
    ], license);
  });
}
