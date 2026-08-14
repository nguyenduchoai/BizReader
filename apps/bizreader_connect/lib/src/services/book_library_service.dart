import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:epubx/epubx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/local_book.dart';
import 'epub_archive_guard.dart';

class BookImportException implements Exception {
  const BookImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BookLibraryService {
  BookLibraryService({EpubArchiveGuard? archiveGuard})
    : _archiveGuard = archiveGuard ?? EpubArchiveGuard();

  static const _storageKey = 'bizreader_local_books_v1';

  final EpubArchiveGuard _archiveGuard;

  Future<List<LocalBook>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null || encoded.isEmpty) return const [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const [];
      final books = <LocalBook>[];
      for (final item in decoded.whereType<Map>()) {
        try {
          final book = LocalBook.fromJson(item.cast<String, Object?>());
          if (File(book.filePath).existsSync()) books.add(book);
        } on Object {
          // Preserve valid books when one persisted record is malformed.
        }
      }
      return books;
    } on Object {
      return const [];
    }
  }

  Future<LocalBook> importEpub(File source, String originalFilename) async {
    try {
      final bytes = await readEpubBytes(source);
      final digest = sha256.convert(bytes);
      final id = digest.toString();
      final bookRef = await EpubReader.openBook(Future.value(bytes));
      final root = await getApplicationDocumentsDirectory();
      final booksDirectory = Directory('${root.path}/books');
      await booksDirectory.create(recursive: true);
      final safeFilename = _safeFilename(originalFilename);
      final destination = File('${booksDirectory.path}/$id.epub');
      if (!await destination.exists()) await source.copy(destination.path);

      return LocalBook(
        id: id,
        title: bookRef.Title?.trim().isNotEmpty == true
            ? bookRef.Title!.trim()
            : _titleFromFilename(safeFilename),
        author: bookRef.Author?.trim() ?? '',
        filePath: destination.path,
        remoteFilename: safeFilename,
      );
    } on EpubArchiveGuardException catch (error) {
      throw BookImportException(error.message);
    } on FileSystemException {
      throw const BookImportException(
        'Không thể lưu EPUB vào thư viện ứng dụng.',
      );
    } on Object {
      throw const BookImportException(
        'Tệp EPUB không hợp lệ hoặc không thể đọc.',
      );
    }
  }

  Future<Uint8List> readEpubBytes(File source) async {
    final report = await _archiveGuard.inspect(source);
    final bytes = BytesBuilder(copy: false);
    var bytesRead = 0;
    await for (final chunk in source.openRead(0, report.compressedBytes + 1)) {
      bytesRead += chunk.length;
      if (bytesRead > report.compressedBytes) {
        throw const EpubArchiveGuardException(
          EpubArchiveViolation.sourceChanged,
          'Tệp EPUB đã thay đổi trong lúc đang đọc.',
        );
      }
      bytes.add(chunk);
    }
    if (bytesRead != report.compressedBytes) {
      throw const EpubArchiveGuardException(
        EpubArchiveViolation.sourceChanged,
        'Tệp EPUB đã thay đổi trong lúc đang đọc.',
      );
    }
    return bytes.takeBytes();
  }

  Future<void> save(List<LocalBook> books) async {
    final preferences = await SharedPreferences.getInstance();
    final persistent = books
        .where((book) => !book.demo)
        .map((book) => book.toJson())
        .toList();
    await preferences.setString(_storageKey, jsonEncode(persistent));
  }

  String _safeFilename(String value) {
    final normalized = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-').trim();
    if (normalized.toLowerCase().endsWith('.epub')) return normalized;
    return '$normalized.epub';
  }

  String _titleFromFilename(String value) {
    return value
        .replaceFirst(RegExp(r'\.epub$', caseSensitive: false), '')
        .replaceAll('_', ' ')
        .trim();
  }
}
