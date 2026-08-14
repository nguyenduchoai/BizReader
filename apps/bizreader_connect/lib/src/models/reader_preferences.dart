import 'package:flutter/material.dart';

class ReaderThemeSpec {
  const ReaderThemeSpec({
    required this.id,
    required this.name,
    required this.background,
    required this.text,
    required this.secondary,
    required this.muted,
    required this.surface,
    required this.accent,
  });

  final String id;
  final String name;
  final Color background;
  final Color text;
  final Color secondary;
  final Color muted;
  final Color surface;
  final Color accent;
}

const readerThemes = <ReaderThemeSpec>[
  ReaderThemeSpec(
    id: 'light',
    name: 'Sáng',
    background: Color(0xFFFFFFFF),
    text: Color(0xFF1A1A1A),
    secondary: Color(0xFF666666),
    muted: Color(0xFF999999),
    surface: Color(0xF2FFFFFF),
    accent: Color(0xFF0068FF),
  ),
  ReaderThemeSpec(
    id: 'paper',
    name: 'Giấy',
    background: Color(0xFFF5F1EB),
    text: Color(0xFF3D3029),
    secondary: Color(0xFF7A6B5D),
    muted: Color(0xFFA89888),
    surface: Color(0xF2F5F1EB),
    accent: Color(0xFF8B5E3C),
  ),
  ReaderThemeSpec(
    id: 'sepia',
    name: 'Vàng',
    background: Color(0xFFF4ECD8),
    text: Color(0xFF5B4636),
    secondary: Color(0xFF8B7355),
    muted: Color(0xFFB09978),
    surface: Color(0xF2F4ECD8),
    accent: Color(0xFFA0714A),
  ),
  ReaderThemeSpec(
    id: 'dark',
    name: 'Tối',
    background: Color(0xFF1C1C1E),
    text: Color(0xFFE5E5E7),
    secondary: Color(0xFF98989D),
    muted: Color(0xFF636366),
    surface: Color(0xF22C2C2E),
    accent: Color(0xFF64A0FF),
  ),
  ReaderThemeSpec(
    id: 'black',
    name: 'Đen',
    background: Color(0xFF000000),
    text: Color(0xFFD1D1D6),
    secondary: Color(0xFF8E8E93),
    muted: Color(0xFF636366),
    surface: Color(0xF21C1C1E),
    accent: Color(0xFF5A9AFF),
  ),
  ReaderThemeSpec(
    id: 'green',
    name: 'Xanh',
    background: Color(0xFFE8F0E4),
    text: Color(0xFF2D3A28),
    secondary: Color(0xFF5A6B52),
    muted: Color(0xFF8A9A80),
    surface: Color(0xF2E8F0E4),
    accent: Color(0xFF4C8B38),
  ),
];

class ReaderPreferences {
  const ReaderPreferences({
    this.themeId = 'light',
    this.fontFamily = 'serif',
    this.fontSize = 18,
    this.lineHeight = 1.6,
    this.margin = 24,
    this.textAlign = 'justify',
  });

  final String themeId;
  final String fontFamily;
  final double fontSize;
  final double lineHeight;
  final double margin;
  final String textAlign;

  ReaderThemeSpec get theme => readerThemes.firstWhere(
    (item) => item.id == themeId,
    orElse: () => readerThemes.first,
  );

  String get cssFontFamily => switch (fontFamily) {
    'sans' => 'Arial, Helvetica, sans-serif',
    'system' => '-apple-system, BlinkMacSystemFont, sans-serif',
    _ => 'Georgia, "Times New Roman", serif',
  };

  String? get flutterFontFamily => switch (fontFamily) {
    'sans' => 'Arial',
    'system' => null,
    _ => 'Georgia',
  };

  ReaderPreferences copyWith({
    String? themeId,
    String? fontFamily,
    double? fontSize,
    double? lineHeight,
    double? margin,
    String? textAlign,
  }) {
    return ReaderPreferences(
      themeId: themeId ?? this.themeId,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: (fontSize ?? this.fontSize).clamp(14, 24),
      lineHeight: (lineHeight ?? this.lineHeight).clamp(1.35, 2.05),
      margin: (margin ?? this.margin).clamp(16, 40),
      textAlign: textAlign ?? this.textAlign,
    );
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'themeId': themeId,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'margin': margin,
    'textAlign': textAlign,
  };

  factory ReaderPreferences.fromJson(Map<String, Object?> json) {
    final themeId = json['themeId'] as String? ?? 'light';
    final fontFamily = json['fontFamily'] as String? ?? 'serif';
    final textAlign = json['textAlign'] as String? ?? 'justify';
    return ReaderPreferences(
      themeId: readerThemes.any((item) => item.id == themeId)
          ? themeId
          : 'light',
      fontFamily: const {'serif', 'sans', 'system'}.contains(fontFamily)
          ? fontFamily
          : 'serif',
      fontSize: ((json['fontSize'] as num?)?.toDouble() ?? 18).clamp(14, 24),
      lineHeight: ((json['lineHeight'] as num?)?.toDouble() ?? 1.6).clamp(
        1.35,
        2.05,
      ),
      margin: ((json['margin'] as num?)?.toDouble() ?? 24).clamp(16, 40),
      textAlign: const {'left', 'justify'}.contains(textAlign)
          ? textAlign
          : 'justify',
    );
  }
}

class ReaderBookmark {
  const ReaderBookmark({
    required this.cfi,
    required this.progress,
    required this.chapterTitle,
    required this.createdAt,
  });

  final String cfi;
  final double progress;
  final String chapterTitle;
  final int createdAt;

  Map<String, Object?> toJson() => {
    'cfi': cfi,
    'progress': progress,
    'chapterTitle': chapterTitle,
    'createdAt': createdAt,
  };

  factory ReaderBookmark.fromJson(Map<String, Object?> json) {
    return ReaderBookmark(
      cfi: json['cfi'] as String? ?? '',
      progress: ((json['progress'] as num?)?.toDouble() ?? 0).clamp(0, 1),
      chapterTitle: json['chapterTitle'] as String? ?? '',
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    );
  }
}
