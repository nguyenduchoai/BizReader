import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/reader_preferences.dart';

class ReaderPreferencesStore {
  static const _preferencesKey = 'bizreader_reader_preferences_v1';
  static const _bookmarksPrefix = 'bizreader_reader_bookmarks_v1_';

  Future<ReaderPreferences> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_preferencesKey);
    if (encoded == null || encoded.isEmpty) return const ReaderPreferences();
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return const ReaderPreferences();
      return ReaderPreferences.fromJson(decoded.cast<String, Object?>());
    } on Object {
      return const ReaderPreferences();
    }
  }

  Future<void> save(ReaderPreferences value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferencesKey, jsonEncode(value.toJson()));
  }

  Future<List<ReaderBookmark>> loadBookmarks(String bookId) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString('$_bookmarksPrefix$bookId');
    if (encoded == null || encoded.isEmpty) return const [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded.whereType<Map>())
          if (ReaderBookmark.fromJson(item.cast<String, Object?>())
              case final bookmark when bookmark.cfi.isNotEmpty)
            bookmark,
      ];
    } on Object {
      return const [];
    }
  }

  Future<void> saveBookmarks(
    String bookId,
    List<ReaderBookmark> bookmarks,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      '$_bookmarksPrefix$bookId',
      jsonEncode(bookmarks.map((item) => item.toJson()).toList()),
    );
  }
}
