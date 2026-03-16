import 'dart:convert';
import 'package:http/http.dart' as http;

class NominatimPlace {
  final String displayName;
  final double lat;
  final double lon;

  const NominatimPlace({
    required this.displayName,
    required this.lat,
    required this.lon,
  });

  factory NominatimPlace.fromJson(Map<String, dynamic> json) {
    return NominatimPlace(
      displayName: json['display_name'] as String? ?? '',
      lat: double.tryParse(json['lat']?.toString() ?? '') ?? 0,
      lon: double.tryParse(json['lon']?.toString() ?? '') ?? 0,
    );
  }
}

class NominatimService {
  static const _baseUrl = 'https://nominatim.openstreetmap.org';
  static const _userAgent = 'Prezio/2.3.0 (noe.gloor@soleco.ch)';
  static const _rateLimitMs = 1100;

  DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _respectRateLimit() async {
    final elapsed = DateTime.now().difference(_lastRequest).inMilliseconds;
    if (elapsed < _rateLimitMs) {
      await Future.delayed(Duration(milliseconds: _rateLimitMs - elapsed));
    }
    _lastRequest = DateTime.now();
  }

  Future<NominatimPlace?> reverseGeocode(double lat, double lon) async {
    await _respectRateLimit();
    try {
      final url = '$_baseUrl/reverse?format=json&lat=$lat&lon=$lon'
          '&zoom=16&addressdetails=1';
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': _userAgent},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data.containsKey('display_name')) {
          return NominatimPlace.fromJson(data);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<List<NominatimPlace>> search(String query) async {
    if (query.trim().length < 3) return [];
    await _respectRateLimit();

    try {
      final url = '$_baseUrl/search?format=json&q=${Uri.encodeComponent(query)}'
          '&limit=5&countrycodes=ch,de,at,fr,it';
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': _userAgent},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> results = jsonDecode(response.body);
        return results
            .map((r) => NominatimPlace.fromJson(r as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }
}
