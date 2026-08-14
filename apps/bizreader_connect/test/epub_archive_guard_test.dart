import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bizreader_connect/src/services/epub_archive_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;
  late EpubArchiveGuard guard;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'bizreader-epub-guard',
    );
    guard = EpubArchiveGuard();
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('accepts a valid minimal EPUB without inflating its entries', () async {
    final file = await _writeFixture(
      temporaryDirectory,
      'valid.epub',
      _minimalEpubEntries(),
    );

    final report = await guard.inspect(file);

    expect(report.entryCount, 3);
    expect(report.compressedBytes, await file.length());
    expect(report.totalUncompressedBytes, greaterThan(20));
    expect(report.highestCompressionRatio, 1);
  });

  test('keeps an ordinary 30 MiB stored book within the limits', () async {
    final file = await _writeSparseThirtyMegabyteEpub(temporaryDirectory);

    final report = await guard.inspect(file);

    expect(report.compressedBytes, greaterThan(30 * 1024 * 1024));
    expect(
      report.totalUncompressedBytes,
      inInclusiveRange(30 * 1024 * 1024, 31 * 1024 * 1024),
    );
    expect(report.highestCompressionRatio, 1);
  });

  test('rejects a compressed EPUB larger than 128 MiB', () async {
    final file = File('${temporaryDirectory.path}/too-large.epub');
    final writer = await file.open(mode: FileMode.write);
    await writer.truncate(EpubArchiveGuard.maxCompressedBytes + 1);
    await writer.close();

    await _expectViolation(
      guard.inspect(file),
      EpubArchiveViolation.compressedFileTooLarge,
    );
  });

  test('rejects a central directory with too many entries', () async {
    final entries = _minimalEpubEntries();
    for (
      var index = entries.length;
      index <= EpubArchiveGuard.maxEntries;
      index++
    ) {
      entries.add(_FixtureEntry('OEBPS/item-$index', Uint8List(0)));
    }
    final file = await _writeFixture(
      temporaryDirectory,
      'too-many.epub',
      entries,
    );

    await _expectViolation(
      guard.inspect(file),
      EpubArchiveViolation.tooManyEntries,
    );
  });

  test('rejects an entry whose declared expanded size is too large', () async {
    final entries = _minimalEpubEntries()
      ..add(
        _FixtureEntry(
          'OEBPS/oversize.xhtml',
          Uint8List.fromList(const [0]),
          compressionMethod: 8,
          uncompressedSize: EpubArchiveGuard.maxEntryUncompressedBytes + 1,
        ),
      );
    final file = await _writeFixture(
      temporaryDirectory,
      'entry-too-large.epub',
      entries,
    );

    await _expectViolation(
      guard.inspect(file),
      EpubArchiveViolation.entryTooLarge,
    );
  });

  test('rejects excessive aggregate expanded size', () async {
    final entries = _minimalEpubEntries();
    for (var index = 0; index < 5; index++) {
      entries.add(
        _FixtureEntry(
          'OEBPS/large-$index.bin',
          Uint8List(384 * 1024),
          compressionMethod: 8,
          uncompressedSize: 60 * 1024 * 1024,
        ),
      );
    }
    final file = await _writeFixture(
      temporaryDirectory,
      'expanded-too-large.epub',
      entries,
    );

    await _expectViolation(
      guard.inspect(file),
      EpubArchiveViolation.expandedArchiveTooLarge,
    );
  });

  test('rejects an implausible compression ratio', () async {
    final entries = _minimalEpubEntries()
      ..add(
        _FixtureEntry(
          'OEBPS/bomb.xhtml',
          Uint8List(8 * 1024),
          compressionMethod: 8,
          uncompressedSize: 2 * 1024 * 1024,
        ),
      );
    final file = await _writeFixture(temporaryDirectory, 'ratio.epub', entries);

    await _expectViolation(
      guard.inspect(file),
      EpubArchiveViolation.compressionRatioTooHigh,
    );
  });

  test('rejects a truncated central directory', () async {
    final file = await _writeFixture(
      temporaryDirectory,
      'truncated.epub',
      _minimalEpubEntries(),
    );
    final bytes = await file.readAsBytes();
    final eocdOffset = bytes.length - 22;
    final data = ByteData.sublistView(bytes);
    final originalSize = data.getUint32(eocdOffset + 12, Endian.little);
    data.setUint32(eocdOffset + 12, originalSize + 1, Endian.little);
    await file.writeAsBytes(bytes, flush: true);

    await _expectViolation(
      guard.inspect(file),
      EpubArchiveViolation.centralDirectoryTruncated,
    );
  });
}

Future<void> _expectViolation(
  Future<EpubArchiveReport> operation,
  EpubArchiveViolation violation,
) async {
  await expectLater(
    operation,
    throwsA(
      isA<EpubArchiveGuardException>().having(
        (error) => error.violation,
        'violation',
        violation,
      ),
    ),
  );
}

List<_FixtureEntry> _minimalEpubEntries() => [
  _FixtureEntry('mimetype', ascii.encode('application/epub+zip')),
  _FixtureEntry(
    'META-INF/container.xml',
    utf8.encode(
      '<?xml version="1.0"?>'
      '<container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles>'
      '</container>',
    ),
  ),
  _FixtureEntry(
    'OEBPS/content.opf',
    utf8.encode(
      '<?xml version="1.0"?>'
      '<package version="3.0" unique-identifier="id" '
      'xmlns="http://www.idpf.org/2007/opf">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">bizreader-test</dc:identifier>'
      '<dc:title>BizReader</dc:title><dc:language>vi</dc:language>'
      '</metadata><manifest/><spine/></package>',
    ),
  ),
];

Future<File> _writeFixture(
  Directory directory,
  String filename,
  List<_FixtureEntry> entries,
) async {
  final output = BytesBuilder(copy: false);
  final localOffsets = <int>[];

  for (final entry in entries) {
    final name = utf8.encode(entry.name);
    localOffsets.add(output.length);
    _writeUint32(output, 0x04034b50);
    _writeUint16(output, 20);
    _writeUint16(output, 0x0800);
    _writeUint16(output, entry.compressionMethod);
    _writeUint16(output, 0);
    _writeUint16(output, 0);
    _writeUint32(output, _crc32(entry.data));
    _writeUint32(output, entry.data.length);
    _writeUint32(output, entry.uncompressedSize);
    _writeUint16(output, name.length);
    _writeUint16(output, 0);
    output.add(name);
    output.add(entry.data);
  }

  final centralDirectoryOffset = output.length;
  for (var index = 0; index < entries.length; index++) {
    final entry = entries[index];
    final name = utf8.encode(entry.name);
    _writeUint32(output, 0x02014b50);
    _writeUint16(output, 20);
    _writeUint16(output, 20);
    _writeUint16(output, 0x0800);
    _writeUint16(output, entry.compressionMethod);
    _writeUint16(output, 0);
    _writeUint16(output, 0);
    _writeUint32(output, _crc32(entry.data));
    _writeUint32(output, entry.data.length);
    _writeUint32(output, entry.uncompressedSize);
    _writeUint16(output, name.length);
    _writeUint16(output, 0);
    _writeUint16(output, 0);
    _writeUint16(output, 0);
    _writeUint16(output, 0);
    _writeUint32(output, 0);
    _writeUint32(output, localOffsets[index]);
    output.add(name);
  }
  final centralDirectorySize = output.length - centralDirectoryOffset;

  _writeUint32(output, 0x06054b50);
  _writeUint16(output, 0);
  _writeUint16(output, 0);
  _writeUint16(output, entries.length);
  _writeUint16(output, entries.length);
  _writeUint32(output, centralDirectorySize);
  _writeUint32(output, centralDirectoryOffset);
  _writeUint16(output, 0);

  final file = File('${directory.path}/$filename');
  await file.writeAsBytes(output.takeBytes(), flush: true);
  return file;
}

Future<File> _writeSparseThirtyMegabyteEpub(Directory directory) async {
  const bookPayloadBytes = 30 * 1024 * 1024;
  final entries = _minimalEpubEntries();
  final localOffsets = <int>[];
  final file = File('${directory.path}/ordinary-30mb.epub');
  final writer = await file.open(mode: FileMode.write);
  try {
    for (final entry in entries) {
      final name = utf8.encode(entry.name);
      localOffsets.add(await writer.position());
      final header = BytesBuilder(copy: false);
      _writeUint32(header, 0x04034b50);
      _writeUint16(header, 20);
      _writeUint16(header, 0x0800);
      _writeUint16(header, entry.compressionMethod);
      _writeUint16(header, 0);
      _writeUint16(header, 0);
      _writeUint32(header, _crc32(entry.data));
      _writeUint32(header, entry.data.length);
      _writeUint32(header, entry.uncompressedSize);
      _writeUint16(header, name.length);
      _writeUint16(header, 0);
      header.add(name);
      header.add(entry.data);
      await writer.writeFrom(header.takeBytes());
    }

    final payloadName = utf8.encode('OEBPS/book.bin');
    localOffsets.add(await writer.position());
    final payloadHeader = BytesBuilder(copy: false);
    _writeUint32(payloadHeader, 0x04034b50);
    _writeUint16(payloadHeader, 20);
    _writeUint16(payloadHeader, 0x0800);
    _writeUint16(payloadHeader, 0);
    _writeUint16(payloadHeader, 0);
    _writeUint16(payloadHeader, 0);
    _writeUint32(payloadHeader, 0);
    _writeUint32(payloadHeader, bookPayloadBytes);
    _writeUint32(payloadHeader, bookPayloadBytes);
    _writeUint16(payloadHeader, payloadName.length);
    _writeUint16(payloadHeader, 0);
    payloadHeader.add(payloadName);
    await writer.writeFrom(payloadHeader.takeBytes());
    await writer.setPosition((await writer.position()) + bookPayloadBytes);

    final centralDirectoryOffset = await writer.position();
    final allEntries = [...entries, _FixtureEntry('OEBPS/book.bin', const [])];
    final central = BytesBuilder(copy: false);
    for (var index = 0; index < allEntries.length; index++) {
      final entry = allEntries[index];
      final isPayload = index == allEntries.length - 1;
      final name = utf8.encode(entry.name);
      final compressedSize = isPayload ? bookPayloadBytes : entry.data.length;
      final uncompressedSize = isPayload
          ? bookPayloadBytes
          : entry.uncompressedSize;
      _writeUint32(central, 0x02014b50);
      _writeUint16(central, 20);
      _writeUint16(central, 20);
      _writeUint16(central, 0x0800);
      _writeUint16(central, 0);
      _writeUint16(central, 0);
      _writeUint16(central, 0);
      _writeUint32(central, isPayload ? 0 : _crc32(entry.data));
      _writeUint32(central, compressedSize);
      _writeUint32(central, uncompressedSize);
      _writeUint16(central, name.length);
      _writeUint16(central, 0);
      _writeUint16(central, 0);
      _writeUint16(central, 0);
      _writeUint16(central, 0);
      _writeUint32(central, 0);
      _writeUint32(central, localOffsets[index]);
      central.add(name);
    }
    final centralBytes = central.takeBytes();
    await writer.writeFrom(centralBytes);

    final eocd = BytesBuilder(copy: false);
    _writeUint32(eocd, 0x06054b50);
    _writeUint16(eocd, 0);
    _writeUint16(eocd, 0);
    _writeUint16(eocd, allEntries.length);
    _writeUint16(eocd, allEntries.length);
    _writeUint32(eocd, centralBytes.length);
    _writeUint32(eocd, centralDirectoryOffset);
    _writeUint16(eocd, 0);
    await writer.writeFrom(eocd.takeBytes());
  } finally {
    await writer.close();
  }
  return file;
}

void _writeUint16(BytesBuilder output, int value) {
  final bytes = ByteData(2)..setUint16(0, value, Endian.little);
  output.add(bytes.buffer.asUint8List());
}

void _writeUint32(BytesBuilder output, int value) {
  final bytes = ByteData(4)..setUint32(0, value, Endian.little);
  output.add(bytes.buffer.asUint8List());
}

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

class _FixtureEntry {
  _FixtureEntry(
    this.name,
    List<int> data, {
    this.compressionMethod = 0,
    int? uncompressedSize,
  }) : data = Uint8List.fromList(data),
       uncompressedSize = uncompressedSize ?? data.length;

  final String name;
  final Uint8List data;
  final int compressionMethod;
  final int uncompressedSize;
}
