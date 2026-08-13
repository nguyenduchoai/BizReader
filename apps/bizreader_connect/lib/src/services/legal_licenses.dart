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
}
