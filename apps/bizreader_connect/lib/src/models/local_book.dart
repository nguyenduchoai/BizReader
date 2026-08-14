class LocalBook {
  const LocalBook({
    required this.id,
    required this.title,
    required this.author,
    required this.filePath,
    required this.remoteFilename,
    this.progress = 0,
    this.epubCfi,
    this.chapterNumber = 0,
    this.chapterProgress = 0,
    this.pageNumber = 0,
    this.pageCount = 0,
    this.updatedAt = 0,
    this.demo = false,
  });

  final String id;
  final String title;
  final String author;
  final String filePath;
  final String remoteFilename;
  final double progress;
  final String? epubCfi;
  final int chapterNumber;
  final double chapterProgress;
  final int pageNumber;
  final int pageCount;
  final int updatedAt;
  final bool demo;

  LocalBook copyWith({
    String? title,
    String? author,
    String? filePath,
    String? remoteFilename,
    double? progress,
    String? epubCfi,
    bool clearEpubCfi = false,
    int? chapterNumber,
    double? chapterProgress,
    int? pageNumber,
    int? pageCount,
    int? updatedAt,
  }) {
    return LocalBook(
      id: id,
      title: title ?? this.title,
      author: author ?? this.author,
      filePath: filePath ?? this.filePath,
      remoteFilename: remoteFilename ?? this.remoteFilename,
      progress: progress ?? this.progress,
      epubCfi: clearEpubCfi ? null : epubCfi ?? this.epubCfi,
      chapterNumber: chapterNumber ?? this.chapterNumber,
      chapterProgress: chapterProgress ?? this.chapterProgress,
      pageNumber: pageNumber ?? this.pageNumber,
      pageCount: pageCount ?? this.pageCount,
      updatedAt: updatedAt ?? this.updatedAt,
      demo: demo,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'filePath': filePath,
    'remoteFilename': remoteFilename,
    'progress': progress,
    'epubCfi': epubCfi,
    'chapterNumber': chapterNumber,
    'chapterProgress': chapterProgress,
    'pageNumber': pageNumber,
    'pageCount': pageCount,
    'updatedAt': updatedAt,
  };

  factory LocalBook.fromJson(Map<String, Object?> json) {
    return LocalBook(
      id: json['id']! as String,
      title: json['title']! as String,
      author: json['author'] as String? ?? '',
      filePath: json['filePath']! as String,
      remoteFilename: json['remoteFilename']! as String,
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      epubCfi: json['epubCfi'] as String?,
      chapterNumber: (json['chapterNumber'] as num?)?.toInt() ?? 0,
      chapterProgress: (json['chapterProgress'] as num?)?.toDouble() ?? 0,
      pageNumber: (json['pageNumber'] as num?)?.toInt() ?? 0,
      pageCount: (json['pageCount'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  static List<LocalBook> demoLibrary() => const [
    LocalBook(
      id: 'demo-thinking',
      title: 'Thay đổi tư duy',
      author: 'BizReader Editorial',
      filePath: '',
      remoteFilename: 'thay-doi-tu-duy.epub',
      progress: 0.42,
      chapterNumber: 2,
      chapterProgress: 56,
      updatedAt: 1786282200000,
      demo: true,
    ),
    LocalBook(
      id: 'demo-leadership',
      title: 'Dẫn đầu bằng tri thức',
      author: 'Hoài Nguyễn',
      filePath: '',
      remoteFilename: 'dan-dau-bang-tri-thuc.epub',
      progress: 0.18,
      chapterNumber: 1,
      chapterProgress: 72,
      updatedAt: 1786195800000,
      demo: true,
    ),
    LocalBook(
      id: 'demo-focus',
      title: 'Sức mạnh tập trung',
      author: 'BizReader Library',
      filePath: '',
      remoteFilename: 'suc-manh-tap-trung.epub',
      progress: 0.71,
      chapterNumber: 4,
      chapterProgress: 12,
      updatedAt: 1786109400000,
      demo: true,
    ),
    LocalBook(
      id: 'demo-business',
      title: 'Bàn cờ kinh doanh',
      author: 'BizReader Library',
      filePath: '',
      remoteFilename: 'ban-co-kinh-doanh.epub',
      updatedAt: 1786023000000,
      demo: true,
    ),
  ];
}
