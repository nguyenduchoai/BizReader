import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/biz_content.dart';

class ContentPreferences {
  static const _key = 'bizreader_content_v1';

  Future<BizContent> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    if (value == null || value.isEmpty) return const BizContent();
    try {
      return BizContent.fromJson(
        (jsonDecode(value) as Map).cast<String, Object?>(),
      );
    } on Object {
      return const BizContent();
    }
  }

  Future<void> save(BizContent content) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(content.toStorageJson()));
  }
}
