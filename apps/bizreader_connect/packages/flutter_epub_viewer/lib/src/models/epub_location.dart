import 'package:json_annotation/json_annotation.dart';

part 'epub_location.g.dart';

@JsonSerializable(explicitToJson: true)
class EpubLocation {
  /// Start cfi string of the page
  String startCfi;

  /// End cfi string of the page
  String endCfi;

  /// Start xpath/XPointer string of the page
  String? startXpath;

  /// End xpath/XPointer string of the page
  String? endXpath;

  /// Progress percentage of location, value between 0.0 and 1.0
  double progress;

  /// Package-relative href of the current EPUB spine item.
  @JsonKey(defaultValue: '')
  String href;

  /// Zero-based index of the current EPUB spine item.
  @JsonKey(defaultValue: 0)
  int spineIndex;

  /// Zero-based page number within the current spine item.
  @JsonKey(defaultValue: 0)
  int pageNumber;

  /// Number of displayed pages in the current spine item.
  @JsonKey(defaultValue: 1)
  int pageCount;

  EpubLocation({
    required this.startCfi,
    required this.endCfi,
    this.startXpath,
    this.endXpath,
    required this.progress,
    this.href = '',
    this.spineIndex = 0,
    this.pageNumber = 0,
    this.pageCount = 1,
  });
  factory EpubLocation.fromJson(Map<String, dynamic> json) =>
      _$EpubLocationFromJson(json);
  Map<String, dynamic> toJson() => _$EpubLocationToJson(this);
}
