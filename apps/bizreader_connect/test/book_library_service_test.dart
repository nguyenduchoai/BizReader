import 'dart:convert';
import 'dart:io';

import 'package:bizreader_connect/src/services/book_library_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('a malformed record does not hide the rest of the library', () async {
    final directory = await Directory.systemTemp.createTemp('bizreader-books');
    addTearDown(() => directory.delete(recursive: true));
    final bookFile = File('${directory.path}/valid.epub');
    await bookFile.writeAsBytes(const [1, 2, 3]);
    SharedPreferences.setMockInitialValues({
      'bizreader_local_books_v1': jsonEncode([
        {'id': 'broken'},
        {
          'id': 'valid',
          'title': 'Sách còn nguyên',
          'author': 'Tác giả',
          'filePath': bookFile.path,
          'remoteFilename': 'valid.epub',
        },
      ]),
    });

    final books = await BookLibraryService().load();

    expect(books, hasLength(1));
    expect(books.single.id, 'valid');
  });

  group('clampRemoteFilename', () {
    test('leaves short names untouched', () {
      expect(
        BookLibraryService.clampRemoteFilename('sách hay.epub'),
        'sách hay.epub',
      );
    });

    test(
      'clamps a long Vietnamese title to 180 UTF-8 bytes at a character '
      'boundary and preserves the extension',
      () {
        final title = 'Đắc nhân tâm và nghệ thuật đối nhân xử thế ' * 8;
        final clamped = BookLibraryService.clampRemoteFilename('$title.epub');

        expect(
          utf8.encode(clamped).length,
          lessThanOrEqualTo(BookLibraryService.maxRemoteFilenameBytes),
        );
        expect(clamped, endsWith('.epub'));
        // Cut at a character boundary: the stem must be a prefix of the
        // original title (no half-encoded multi-byte character survives).
        final stem = clamped.substring(0, clamped.length - '.epub'.length);
        expect(title.startsWith(stem), isTrue);
        // The clamp keeps as much of the title as fits.
        expect(utf8.encode(clamped).length, greaterThan(160));
      },
    );

    test('never splits a multi-byte character mid-sequence', () {
      // 'ế' is 3 UTF-8 bytes; force budgets that land inside it.
      final clamped = BookLibraryService.clampRemoteFilename(
        '${'ế' * 100}.epub',
      );
      expect(
        utf8.encode(clamped).length,
        lessThanOrEqualTo(BookLibraryService.maxRemoteFilenameBytes),
      );
      // Round-trips through UTF-8 unchanged, so no broken sequence exists.
      expect(utf8.decode(utf8.encode(clamped)), clamped);
      expect(clamped, endsWith('ế.epub'));
    });
  });
}
