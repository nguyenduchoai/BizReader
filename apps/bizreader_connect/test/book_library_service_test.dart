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
}
