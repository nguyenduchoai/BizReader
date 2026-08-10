import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/biz_content.dart';
import 'webdav_device_client.dart';

class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<BizWeather> fetch(String city) async {
    final geocoding = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': city,
      'count': '1',
      'language': 'vi',
      'format': 'json',
    });
    final locationResponse = await _client
        .get(geocoding)
        .timeout(const Duration(seconds: 12));
    if (locationResponse.statusCode != 200) {
      throw const DeviceConnectionException('Không lấy được vị trí thời tiết.');
    }
    final locationJson =
        jsonDecode(locationResponse.body) as Map<String, dynamic>;
    final results = locationJson['results'];
    if (results is! List || results.isEmpty || results.first is! Map) {
      throw const DeviceConnectionException('Không tìm thấy địa điểm này.');
    }
    final location = (results.first as Map).cast<String, dynamic>();
    final latitude = location['latitude'] as num?;
    final longitude = location['longitude'] as num?;
    if (latitude == null || longitude == null) {
      throw const DeviceConnectionException('Địa điểm không có tọa độ hợp lệ.');
    }

    final forecast = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$latitude',
      'longitude': '$longitude',
      'current': 'temperature_2m,weather_code',
      'daily': 'temperature_2m_max,temperature_2m_min',
      'timezone': 'auto',
      'forecast_days': '1',
    });
    final weatherResponse = await _client
        .get(forecast)
        .timeout(const Duration(seconds: 12));
    if (weatherResponse.statusCode != 200) {
      throw const DeviceConnectionException('Không lấy được dự báo thời tiết.');
    }
    final weatherJson =
        jsonDecode(weatherResponse.body) as Map<String, dynamic>;
    final current = (weatherJson['current'] as Map?)?.cast<String, dynamic>();
    final daily = (weatherJson['daily'] as Map?)?.cast<String, dynamic>();
    if (current == null || daily == null) {
      throw const DeviceConnectionException('Dữ liệu thời tiết không hợp lệ.');
    }

    int firstRounded(String key) {
      final values = daily[key];
      return values is List && values.isNotEmpty && values.first is num
          ? (values.first as num).round()
          : 0;
    }

    return BizWeather(
      location: location['name'] as String? ?? city,
      condition: _condition((current['weather_code'] as num?)?.toInt() ?? -1),
      temperature: (current['temperature_2m'] as num?)?.round() ?? 0,
      high: firstRounded('temperature_2m_max'),
      low: firstRounded('temperature_2m_min'),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  String _condition(int code) {
    if (code == 0) return 'Trời quang';
    if (code <= 3) return 'Có mây';
    if (code == 45 || code == 48) return 'Sương mù';
    if (code >= 51 && code <= 57) return 'Mưa phùn';
    if (code >= 61 && code <= 67) return 'Mưa';
    if (code >= 71 && code <= 77) return 'Tuyết';
    if (code >= 80 && code <= 82) return 'Mưa rào';
    if (code >= 85 && code <= 86) return 'Tuyết rào';
    if (code >= 95) return 'Dông';
    return 'Chưa xác định';
  }
}
