// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'epub_location.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EpubLocation _$EpubLocationFromJson(Map<String, dynamic> json) => EpubLocation(
  startCfi: json['startCfi'] as String,
  endCfi: json['endCfi'] as String,
  startXpath: json['startXpath'] as String?,
  endXpath: json['endXpath'] as String?,
  progress: (json['progress'] as num).toDouble(),
  href: json['href'] as String? ?? '',
  spineIndex: (json['spineIndex'] as num?)?.toInt() ?? 0,
  pageNumber: (json['pageNumber'] as num?)?.toInt() ?? 0,
  pageCount: (json['pageCount'] as num?)?.toInt() ?? 1,
);

Map<String, dynamic> _$EpubLocationToJson(EpubLocation instance) =>
    <String, dynamic>{
      'startCfi': instance.startCfi,
      'endCfi': instance.endCfi,
      'startXpath': instance.startXpath,
      'endXpath': instance.endXpath,
      'progress': instance.progress,
      'href': instance.href,
      'spineIndex': instance.spineIndex,
      'pageNumber': instance.pageNumber,
      'pageCount': instance.pageCount,
    };
