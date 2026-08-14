import 'package:bizreader_connect/src/models/reader_preferences.dart';
import 'package:bizreader_connect/src/services/reader_preferences_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('reader preferences roundtrip and clamp unsafe values', () async {
    final store = ReaderPreferencesStore();
    const saved = ReaderPreferences(
      themeId: 'green',
      fontFamily: 'sans',
      fontSize: 22,
      lineHeight: 1.85,
      margin: 32,
      textAlign: 'left',
    );

    await store.save(saved);
    final loaded = await store.load();

    expect(loaded.themeId, 'green');
    expect(loaded.fontFamily, 'sans');
    expect(loaded.fontSize, 22);
    expect(loaded.lineHeight, 1.85);
    expect(loaded.margin, 32);
    expect(loaded.textAlign, 'left');

    final clamped = ReaderPreferences.fromJson({
      'themeId': 'unknown',
      'fontFamily': 'remote-font',
      'fontSize': 99,
      'lineHeight': 0,
      'margin': 100,
      'textAlign': 'center',
    });
    expect(clamped.themeId, 'light');
    expect(clamped.fontFamily, 'serif');
    expect(clamped.fontSize, 24);
    expect(clamped.lineHeight, 1.35);
    expect(clamped.margin, 40);
    expect(clamped.textAlign, 'justify');
  });

  test('bookmarks persist separately for each book', () async {
    final store = ReaderPreferencesStore();
    const bookmark = ReaderBookmark(
      cfi: 'epubcfi(/6/4)',
      progress: 0.42,
      chapterTitle: 'Chương 2',
      createdAt: 1234,
    );

    await store.saveBookmarks('book-a', const [bookmark]);

    expect(await store.loadBookmarks('book-a'), hasLength(1));
    expect((await store.loadBookmarks('book-a')).single.cfi, bookmark.cfi);
    expect(await store.loadBookmarks('book-b'), isEmpty);
  });
}
