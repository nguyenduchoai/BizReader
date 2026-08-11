import 'dart:typed_data';

const int bleSyncFrameHeaderSize = 4;

List<Uint8List> encodeBleSyncFrames(List<int> bytes, int payloadSize) {
  if (bytes.isEmpty || payloadSize < 1) {
    throw const FormatException('Dữ liệu BLE rỗng');
  }
  final total = (bytes.length + payloadSize - 1) ~/ payloadSize;
  if (total > 0xffff) throw const FormatException('Quá nhiều gói BLE');
  return [
    for (var sequence = 0; sequence < total; sequence++)
      () {
        final start = sequence * payloadSize;
        final end = (start + payloadSize).clamp(0, bytes.length);
        final frame = Uint8List(bleSyncFrameHeaderSize + end - start);
        final header = ByteData.sublistView(frame);
        header.setUint16(0, sequence, Endian.little);
        header.setUint16(2, total, Endian.little);
        frame.setRange(bleSyncFrameHeaderSize, frame.length, bytes, start);
        return frame;
      }(),
  ];
}

Uint8List decodeBleSyncFrames(List<List<int>> frames) {
  if (frames.isEmpty) throw const FormatException('Thiếu dữ liệu BLE');
  final output = BytesBuilder(copy: false);
  int? total;
  for (var sequence = 0; sequence < frames.length; sequence++) {
    final frame = frames[sequence];
    if (frame.length < bleSyncFrameHeaderSize) {
      throw const FormatException('Gói BLE quá ngắn');
    }
    final header = ByteData.sublistView(Uint8List.fromList(frame));
    final frameSequence = header.getUint16(0, Endian.little);
    final frameTotal = header.getUint16(2, Endian.little);
    total ??= frameTotal;
    if (frameSequence != sequence || frameTotal != total) {
      throw const FormatException('Sai thứ tự gói BLE');
    }
    output.add(frame.sublist(bleSyncFrameHeaderSize));
  }
  if (total != frames.length) throw const FormatException('Thiếu gói BLE');
  return output.takeBytes();
}
