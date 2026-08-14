import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

enum EpubArchiveViolation {
  compressedFileTooLarge,
  endOfCentralDirectoryMissing,
  multiDiskArchive,
  zip64Archive,
  centralDirectoryTooLarge,
  centralDirectoryTruncated,
  tooManyEntries,
  entryTooLarge,
  expandedArchiveTooLarge,
  compressionRatioTooHigh,
  encryptedEntry,
  unsupportedCompression,
  invalidEntryName,
  duplicateEntry,
  invalidLocalHeader,
  missingEpubStructure,
  sourceChanged,
}

class EpubArchiveGuardException implements Exception {
  const EpubArchiveGuardException(this.violation, this.message);

  final EpubArchiveViolation violation;
  final String message;

  @override
  String toString() => message;
}

class EpubArchiveReport {
  const EpubArchiveReport({
    required this.compressedBytes,
    required this.entryCount,
    required this.totalUncompressedBytes,
    required this.highestCompressionRatio,
  });

  final int compressedBytes;
  final int entryCount;
  final int totalUncompressedBytes;
  final double highestCompressionRatio;
}

class EpubArchiveGuard {
  static const int maxCompressedBytes = 128 * 1024 * 1024;
  static const int maxEntries = 4096;
  static const int maxEntryUncompressedBytes = 64 * 1024 * 1024;
  static const int maxTotalUncompressedBytes = 256 * 1024 * 1024;
  static const int maxCentralDirectoryBytes = 16 * 1024 * 1024;
  static const int maxEntryNameBytes = 1024;
  static const int compressionRatioGraceBytes = 1024 * 1024;
  static const double maxCompressionRatio = 200;

  static const int _endOfCentralDirectorySignature = 0x06054b50;
  static const int _centralDirectorySignature = 0x02014b50;
  static const int _localFileHeaderSignature = 0x04034b50;
  static const int _endOfCentralDirectoryBytes = 22;
  static const int _centralDirectoryHeaderBytes = 46;
  static const int _localFileHeaderBytes = 30;
  static const int _maxZipCommentBytes = 0xffff;

  Future<EpubArchiveReport> inspect(File file) async {
    final reader = await file.open();
    try {
      final fileLength = await reader.length();
      if (fileLength > maxCompressedBytes) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.compressedFileTooLarge,
          'EPUB vượt quá giới hạn 128 MiB của ứng dụng.',
        );
      }
      if (fileLength < _endOfCentralDirectoryBytes) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.endOfCentralDirectoryMissing,
          'EPUB không có thư mục ZIP hoàn chỉnh.',
        );
      }

      final eocd = await _findEndOfCentralDirectory(reader, fileLength);
      final diskNumber = _uint16(eocd.bytes, 4);
      final centralDirectoryDisk = _uint16(eocd.bytes, 6);
      final entriesOnDisk = _uint16(eocd.bytes, 8);
      final entryCount = _uint16(eocd.bytes, 10);
      final centralDirectorySize = _uint32(eocd.bytes, 12);
      final centralDirectoryOffset = _uint32(eocd.bytes, 16);

      if (diskNumber != 0 ||
          centralDirectoryDisk != 0 ||
          entriesOnDisk != entryCount) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.multiDiskArchive,
          'EPUB nhiều phần không được hỗ trợ.',
        );
      }
      if (entryCount == 0xffff ||
          centralDirectorySize == 0xffffffff ||
          centralDirectoryOffset == 0xffffffff) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.zip64Archive,
          'EPUB ZIP64 không được hỗ trợ.',
        );
      }
      if (entryCount > maxEntries) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.tooManyEntries,
          'EPUB chứa quá nhiều tệp con.',
        );
      }
      if (centralDirectorySize > maxCentralDirectoryBytes) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.centralDirectoryTooLarge,
          'Thư mục ZIP của EPUB quá lớn.',
        );
      }

      final centralDirectoryEnd = centralDirectoryOffset + centralDirectorySize;
      if (centralDirectoryOffset < 0 ||
          centralDirectoryEnd != eocd.offset ||
          centralDirectoryEnd > fileLength) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.centralDirectoryTruncated,
          'Thư mục ZIP của EPUB bị thiếu hoặc sai vị trí.',
        );
      }

      final entries = await _readCentralDirectory(
        reader,
        offset: centralDirectoryOffset,
        size: centralDirectorySize,
        entryCount: entryCount,
      );
      await _validateLocalHeaders(reader, entries, centralDirectoryOffset);
      await _validateEpubStructure(reader, entries);

      var totalUncompressedBytes = 0;
      var totalCompressedPayloadBytes = 0;
      var highestCompressionRatio = 1.0;
      for (final entry in entries) {
        totalUncompressedBytes += entry.uncompressedSize;
        totalCompressedPayloadBytes += entry.compressedSize;
        if (entry.uncompressedSize > maxEntryUncompressedBytes) {
          throw const EpubArchiveGuardException(
            EpubArchiveViolation.entryTooLarge,
            'EPUB có một tệp con vượt quá giới hạn 64 MiB.',
          );
        }

        final ratio = _compressionRatio(
          entry.compressedSize,
          entry.uncompressedSize,
        );
        if (ratio > highestCompressionRatio) highestCompressionRatio = ratio;
        if (entry.uncompressedSize >= compressionRatioGraceBytes &&
            ratio > maxCompressionRatio) {
          throw const EpubArchiveGuardException(
            EpubArchiveViolation.compressionRatioTooHigh,
            'EPUB có tỷ lệ nén bất thường.',
          );
        }
      }
      if (totalUncompressedBytes > maxTotalUncompressedBytes) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.expandedArchiveTooLarge,
          'EPUB cần quá nhiều bộ nhớ sau khi giải nén.',
        );
      }
      final totalRatio = _compressionRatio(
        totalCompressedPayloadBytes,
        totalUncompressedBytes,
      );
      if (totalUncompressedBytes >= compressionRatioGraceBytes &&
          totalRatio > maxCompressionRatio) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.compressionRatioTooHigh,
          'EPUB có tỷ lệ nén tổng thể bất thường.',
        );
      }

      return EpubArchiveReport(
        compressedBytes: fileLength,
        entryCount: entryCount,
        totalUncompressedBytes: totalUncompressedBytes,
        highestCompressionRatio: highestCompressionRatio,
      );
    } finally {
      await reader.close();
    }
  }

  Future<_EndOfCentralDirectory> _findEndOfCentralDirectory(
    RandomAccessFile reader,
    int fileLength,
  ) async {
    final tailLength =
        fileLength < _endOfCentralDirectoryBytes + _maxZipCommentBytes
        ? fileLength
        : _endOfCentralDirectoryBytes + _maxZipCommentBytes;
    final tailOffset = fileLength - tailLength;
    await reader.setPosition(tailOffset);
    final tail = await _readExactly(
      reader,
      tailLength,
      EpubArchiveViolation.endOfCentralDirectoryMissing,
    );
    for (
      var index = tail.length - _endOfCentralDirectoryBytes;
      index >= 0;
      index--
    ) {
      if (_uint32(tail, index) != _endOfCentralDirectorySignature) continue;
      final commentLength = _uint16(tail, index + 20);
      final absoluteOffset = tailOffset + index;
      if (absoluteOffset + _endOfCentralDirectoryBytes + commentLength !=
          fileLength) {
        continue;
      }
      return _EndOfCentralDirectory(
        offset: absoluteOffset,
        bytes: Uint8List.sublistView(
          tail,
          index,
          index + _endOfCentralDirectoryBytes,
        ),
      );
    }
    throw const EpubArchiveGuardException(
      EpubArchiveViolation.endOfCentralDirectoryMissing,
      'EPUB không có điểm kết thúc thư mục ZIP hợp lệ.',
    );
  }

  Future<List<_ZipEntry>> _readCentralDirectory(
    RandomAccessFile reader, {
    required int offset,
    required int size,
    required int entryCount,
  }) async {
    final end = offset + size;
    var cursor = offset;
    final entries = <_ZipEntry>[];
    final names = <String>{};

    for (var index = 0; index < entryCount; index++) {
      if (cursor + _centralDirectoryHeaderBytes > end) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.centralDirectoryTruncated,
          'Thư mục ZIP của EPUB bị cắt ngắn.',
        );
      }
      await reader.setPosition(cursor);
      final header = await _readExactly(
        reader,
        _centralDirectoryHeaderBytes,
        EpubArchiveViolation.centralDirectoryTruncated,
      );
      if (_uint32(header, 0) != _centralDirectorySignature) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.centralDirectoryTruncated,
          'EPUB có bản ghi thư mục ZIP không hợp lệ.',
        );
      }

      final flags = _uint16(header, 8);
      final compressionMethod = _uint16(header, 10);
      final compressedSize = _uint32(header, 20);
      final uncompressedSize = _uint32(header, 24);
      final nameLength = _uint16(header, 28);
      final extraLength = _uint16(header, 30);
      final commentLength = _uint16(header, 32);
      final diskStart = _uint16(header, 34);
      final localHeaderOffset = _uint32(header, 42);
      final recordLength =
          _centralDirectoryHeaderBytes +
          nameLength +
          extraLength +
          commentLength;
      if (cursor + recordLength > end) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.centralDirectoryTruncated,
          'Bản ghi thư mục ZIP của EPUB bị cắt ngắn.',
        );
      }
      if (nameLength == 0 || nameLength > maxEntryNameBytes) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.invalidEntryName,
          'EPUB có tên tệp con không hợp lệ.',
        );
      }
      if (diskStart != 0) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.multiDiskArchive,
          'EPUB nhiều phần không được hỗ trợ.',
        );
      }
      if (compressedSize == 0xffffffff ||
          uncompressedSize == 0xffffffff ||
          localHeaderOffset == 0xffffffff) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.zip64Archive,
          'EPUB ZIP64 không được hỗ trợ.',
        );
      }
      if ((flags & 0x0001) != 0) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.encryptedEntry,
          'EPUB có tệp con được mã hóa nên không thể đọc.',
        );
      }
      if (compressionMethod != 0 && compressionMethod != 8) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.unsupportedCompression,
          'EPUB dùng phương thức nén không được hỗ trợ.',
        );
      }

      final nameBytes = await _readExactly(
        reader,
        nameLength,
        EpubArchiveViolation.centralDirectoryTruncated,
      );
      final name = _decodeEntryName(nameBytes, (flags & 0x0800) != 0);
      _validateEntryName(name);
      if (!names.add(name)) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.duplicateEntry,
          'EPUB có nhiều tệp con trùng tên.',
        );
      }
      entries.add(
        _ZipEntry(
          name: name,
          flags: flags,
          compressionMethod: compressionMethod,
          compressedSize: compressedSize,
          uncompressedSize: uncompressedSize,
          localHeaderOffset: localHeaderOffset,
        ),
      );
      cursor += recordLength;
    }
    if (cursor != end) {
      throw const EpubArchiveGuardException(
        EpubArchiveViolation.centralDirectoryTruncated,
        'Kích thước thư mục ZIP của EPUB không khớp.',
      );
    }
    return entries;
  }

  Future<void> _validateLocalHeaders(
    RandomAccessFile reader,
    List<_ZipEntry> entries,
    int centralDirectoryOffset,
  ) async {
    final sortedEntries = List<_ZipEntry>.of(entries)
      ..sort(
        (left, right) =>
            left.localHeaderOffset.compareTo(right.localHeaderOffset),
      );
    var previousDataEnd = 0;
    for (final entry in sortedEntries) {
      if (entry.localHeaderOffset < previousDataEnd ||
          entry.localHeaderOffset + _localFileHeaderBytes >
              centralDirectoryOffset) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.invalidLocalHeader,
          'EPUB có vùng dữ liệu ZIP chồng lấn hoặc sai vị trí.',
        );
      }
      await reader.setPosition(entry.localHeaderOffset);
      final header = await _readExactly(
        reader,
        _localFileHeaderBytes,
        EpubArchiveViolation.invalidLocalHeader,
      );
      if (_uint32(header, 0) != _localFileHeaderSignature) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.invalidLocalHeader,
          'EPUB có đầu tệp ZIP không hợp lệ.',
        );
      }
      final localFlags = _uint16(header, 6);
      final localMethod = _uint16(header, 8);
      final localCompressedSize = _uint32(header, 18);
      final localUncompressedSize = _uint32(header, 22);
      final nameLength = _uint16(header, 26);
      final extraLength = _uint16(header, 28);
      if (nameLength == 0 || nameLength > maxEntryNameBytes) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.invalidLocalHeader,
          'EPUB có tên tệp cục bộ không hợp lệ.',
        );
      }
      final nameBytes = await _readExactly(
        reader,
        nameLength,
        EpubArchiveViolation.invalidLocalHeader,
      );
      final localName = _decodeEntryName(nameBytes, (localFlags & 0x0800) != 0);
      if (localName != entry.name ||
          localFlags != entry.flags ||
          localMethod != entry.compressionMethod) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.invalidLocalHeader,
          'Thông tin tệp cục bộ và thư mục ZIP của EPUB không khớp.',
        );
      }
      final usesDataDescriptor = (localFlags & 0x0008) != 0;
      if (!usesDataDescriptor &&
          (localCompressedSize != entry.compressedSize ||
              localUncompressedSize != entry.uncompressedSize)) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.invalidLocalHeader,
          'Kích thước tệp cục bộ trong EPUB không khớp.',
        );
      }
      if (usesDataDescriptor &&
          ((localCompressedSize != 0 &&
                  localCompressedSize != entry.compressedSize) ||
              (localUncompressedSize != 0 &&
                  localUncompressedSize != entry.uncompressedSize))) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.invalidLocalHeader,
          'Kích thước tệp cục bộ trong EPUB không khớp.',
        );
      }

      final dataOffset =
          entry.localHeaderOffset +
          _localFileHeaderBytes +
          nameLength +
          extraLength;
      final dataEnd = dataOffset + entry.compressedSize;
      if (dataEnd > centralDirectoryOffset) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.invalidLocalHeader,
          'Dữ liệu tệp con vượt ra ngoài vùng ZIP của EPUB.',
        );
      }
      entry.dataOffset = dataOffset;
      previousDataEnd = dataEnd;
    }
  }

  Future<void> _validateEpubStructure(
    RandomAccessFile reader,
    List<_ZipEntry> entries,
  ) async {
    _ZipEntry? mimetype;
    var hasContainer = false;
    for (final entry in entries) {
      if (entry.name == 'mimetype') mimetype = entry;
      if (entry.name == 'META-INF/container.xml') hasContainer = true;
    }
    if (mimetype == null ||
        !hasContainer ||
        mimetype.compressionMethod != 0 ||
        mimetype.compressedSize != 20 ||
        mimetype.uncompressedSize != 20 ||
        mimetype.dataOffset == null) {
      throw const EpubArchiveGuardException(
        EpubArchiveViolation.missingEpubStructure,
        'Tệp ZIP không có cấu trúc EPUB bắt buộc.',
      );
    }
    await reader.setPosition(mimetype.dataOffset!);
    final contents = await _readExactly(
      reader,
      20,
      EpubArchiveViolation.missingEpubStructure,
    );
    if (ascii.decode(contents, allowInvalid: true) != 'application/epub+zip') {
      throw const EpubArchiveGuardException(
        EpubArchiveViolation.missingEpubStructure,
        'Khai báo định dạng EPUB không hợp lệ.',
      );
    }
  }

  static Future<Uint8List> _readExactly(
    RandomAccessFile reader,
    int length,
    EpubArchiveViolation violation,
  ) async {
    final bytes = await reader.read(length);
    if (bytes.length != length) {
      throw EpubArchiveGuardException(
        violation,
        'EPUB bị cắt ngắn hoặc không đọc được.',
      );
    }
    return bytes;
  }

  static String _decodeEntryName(Uint8List bytes, bool isUtf8) {
    try {
      return isUtf8
          ? utf8.decode(bytes, allowMalformed: false)
          : latin1.decode(bytes, allowInvalid: false);
    } on FormatException {
      throw const EpubArchiveGuardException(
        EpubArchiveViolation.invalidEntryName,
        'EPUB có tên tệp con không giải mã được.',
      );
    }
  }

  static void _validateEntryName(String name) {
    if (name.contains('\u0000') ||
        name.contains('\\') ||
        name.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(name) ||
        name.split('/').contains('..')) {
      throw const EpubArchiveGuardException(
        EpubArchiveViolation.invalidEntryName,
        'EPUB có đường dẫn tệp con không an toàn.',
      );
    }
  }

  static double _compressionRatio(int compressed, int uncompressed) {
    if (uncompressed == 0) return 1;
    if (compressed == 0) return double.infinity;
    return uncompressed / compressed;
  }

  static int _uint16(Uint8List bytes, int offset) =>
      ByteData.sublistView(bytes).getUint16(offset, Endian.little);

  static int _uint32(Uint8List bytes, int offset) =>
      ByteData.sublistView(bytes).getUint32(offset, Endian.little);
}

class _EndOfCentralDirectory {
  const _EndOfCentralDirectory({required this.offset, required this.bytes});

  final int offset;
  final Uint8List bytes;
}

class _ZipEntry {
  _ZipEntry({
    required this.name,
    required this.flags,
    required this.compressionMethod,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
  });

  final String name;
  final int flags;
  final int compressionMethod;
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;
  int? dataOffset;
}
