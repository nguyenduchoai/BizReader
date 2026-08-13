import 'dart:convert';

import 'package:bizreader_connect/src/services/weather_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('loads Vietnamese weather by city name', () async {
    final requests = <http.Request>[];
    final service = WeatherService(
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.host == 'geocoding-api.open-meteo.com') {
          return http.Response.bytes(
            utf8.encode(
              '{"results":[{"name":"Hà Nội","latitude":21.0245,"longitude":105.84117}]}',
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(
          '{"current":{"temperature_2m":28.8,"weather_code":0},'
          '"daily":{"temperature_2m_max":[34.3],"temperature_2m_min":[27.5]}}',
          200,
        );
      }),
    );

    final weather = await service.fetch('Hà Nội');

    expect(requests, hasLength(2));
    expect(requests.first.url.queryParameters['language'], 'vi');
    expect(requests.last.url.queryParameters['forecast_days'], '1');
    expect(weather.location, 'Hà Nội');
    expect(weather.condition, 'Trời quang');
    expect(weather.temperature, 29);
    expect(weather.high, 34);
    expect(weather.low, 28);
  });

  test('uses customer endpoints when a commercial API key is supplied', () async {
    final requests = <http.Request>[];
    final service = WeatherService(
      apiKey: 'commercial-key',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.host == 'customer-geocoding-api.open-meteo.com') {
          return http.Response.bytes(
            utf8.encode(
              '{"results":[{"name":"Huế","latitude":16.46,"longitude":107.59}]}',
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(
          '{"current":{"temperature_2m":27,"weather_code":3},'
          '"daily":{"temperature_2m_max":[30],"temperature_2m_min":[24]}}',
          200,
        );
      }),
    );

    await service.fetch('Huế');

    expect(requests.first.url.host, 'customer-geocoding-api.open-meteo.com');
    expect(requests.last.url.host, 'customer-api.open-meteo.com');
    expect(requests.first.url.queryParameters['apikey'], 'commercial-key');
    expect(requests.last.url.queryParameters['apikey'], 'commercial-key');
  });
}
