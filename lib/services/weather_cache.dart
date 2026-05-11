import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherCache {
  static final WeatherCache _instance = WeatherCache._();
  factory WeatherCache() => _instance;
  WeatherCache._();

  Map<String, dynamic>? _data;
  DateTime? _fetchedAt;
  String? _cacheKey;

  Future<Map<String, dynamic>?> get(double lat, double lon) async {
    final key = '${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}';
    if (_data != null && _cacheKey == key && _fetchedAt != null &&
        DateTime.now().difference(_fetchedAt!).inMinutes < 30) {
      return _data;
    }
    final url = 'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon'
        '&hourly=temperature_2m,relative_humidity_2m,weather_code'
        '&daily=weather_code,temperature_2m_max,temperature_2m_min'
        '&timezone=auto&forecast_days=7';
    for (var i = 0; i < 3; i++) {
      if (i > 0) await Future.delayed(Duration(seconds: i * 2));
      try {
        final resp = await http.get(Uri.parse(url));
        if (resp.statusCode == 200) {
          final d = jsonDecode(resp.body) as Map<String, dynamic>;
          if (d.containsKey('hourly')) {
            _data = d;
            _cacheKey = key;
            _fetchedAt = DateTime.now();
            return _data;
          }
        }
      } catch (_) {}
    }
    return _data; // return stale cache if refresh fails
  }
}
