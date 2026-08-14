import 'package:bizreader_connect/src/models/local_book.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy library records default missing page position to zero', () {
    final book = LocalBook.fromJson(const {
      'id': 'legacy-book',
      'title': 'Sách cũ',
      'author': 'Tác giả',
      'filePath': '/tmp/legacy.epub',
      'remoteFilename': 'legacy.epub',
      'progress': 0.3,
    });

    expect(book.pageNumber, 0);
    expect(book.pageCount, 0);
  });

  test('page position survives local library JSON roundtrip', () {
    const original = LocalBook(
      id: 'book',
      title: 'Sách',
      author: 'Tác giả',
      filePath: '/tmp/book.epub',
      remoteFilename: 'book.epub',
      progress: 0.42,
      pageNumber: 84,
      pageCount: 201,
      updatedAt: 1234,
    );

    final restored = LocalBook.fromJson(original.toJson());

    expect(restored.pageNumber, 84);
    expect(restored.pageCount, 201);
    expect(restored.progress, 0.42);
  });
}
