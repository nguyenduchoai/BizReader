import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('epubView.js subscribes the lowercase epub.js display error event', () {
    // epub.js 0.3.x emits EVENTS.RENDITION.DISPLAY_ERROR = 'displayerror';
    // subscribing the camelCase name silently disables CFI recovery.
    final source = File(
      'lib/assets/webpage/html/epubView.js',
    ).readAsStringSync();

    expect(source, contains("rendition.on('displayerror'"));
    expect(source, isNot(contains("rendition.on('displayError'")));
  });

  test('vendored JSZip is at least the hardened 3.10.1 baseline', () {
    final source = File(
      'lib/assets/webpage/dist/jszip.min.js',
    ).readAsStringSync();
    final match = RegExp(r'JSZip v(\d+)\.(\d+)\.(\d+)').firstMatch(source);

    expect(match, isNotNull, reason: 'JSZip version banner must be preserved.');
    final version = <int>[
      int.parse(match!.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    ];
    expect(
      _compareVersions(version, const [3, 10, 1]),
      greaterThanOrEqualTo(0),
      reason: 'Older JSZip releases contain known ZIP handling flaws.',
    );
  });
}

int _compareVersions(List<int> left, List<int> right) {
  for (var index = 0; index < 3; index++) {
    final comparison = left[index].compareTo(right[index]);
    if (comparison != 0) return comparison;
  }
  return 0;
}
