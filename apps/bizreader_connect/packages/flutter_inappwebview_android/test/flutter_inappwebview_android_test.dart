import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the AGP 9 supported ProGuard defaults', () {
    final buildFile = File('android/build.gradle').readAsStringSync();

    expect(buildFile,
        isNot(contains("getDefaultProguardFile('proguard-android.txt')")));
    expect(
      'proguard-android-optimize.txt'.allMatches(buildFile).length,
      greaterThanOrEqualTo(2),
    );
  });
}
