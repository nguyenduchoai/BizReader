import 'dart:math';

import 'package:bizreader_connect/src/services/ble_sync_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round trips snapshots across small BLE MTUs', () {
    final bytes = List<int>.generate(4097, (index) => index % 251);
    for (final payloadSize in [16, 64, 236]) {
      final frames = encodeBleSyncFrames(bytes, payloadSize);
      expect(decodeBleSyncFrames(frames), bytes);
    }
  });

  test('rejects missing or reordered BLE chunks', () {
    final random = Random(7);
    final frames = encodeBleSyncFrames(
      List<int>.generate(600, (_) => random.nextInt(256)),
      100,
    );
    expect(
      () => decodeBleSyncFrames([frames[1], frames[0], ...frames.skip(2)]),
      throwsFormatException,
    );
    expect(
      () => decodeBleSyncFrames(frames.sublist(0, frames.length - 1)),
      throwsFormatException,
    );
  });
}
