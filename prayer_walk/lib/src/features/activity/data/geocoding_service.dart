import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/app_logger.dart';

/// Turns a coordinate into a place name — "Antipolo", "Kreuzberg", "Mile End".
///
/// The **only** file that knows the app geocodes with Mapbox, in the same
/// spirit as [LocationService] owning `geolocator` and [RouteMapView] owning
/// `flutter_map`. Callers get a `String?` and never learn where it came from.
///
/// Everything here fails soft, on purpose. A place name is a nicety on top of a
/// walk; a walk that refuses to save because a geocoding endpoint was slow is a
/// far worse product than a walk called "Morning walk".
class GeocodingService {
  GeocodingService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _tag = 'PW-GEO';

  /// Past this we give up and return null. Nothing waits on this call, but the
  /// save flow does hold it briefly, so it must not hold it for long.
  static const _timeout = Duration(seconds: 4);

  /// Resolved names, keyed by a coarsened coordinate.
  ///
  /// Rounding to three decimals is roughly a 100 m grid. Two walks that start
  /// on the same street therefore share one lookup, which matters because the
  /// answer at that resolution is a neighbourhood name that does not change
  /// between them.
  final Map<String, String?> _cache = {};

  /// The place [point] is in, or null if it cannot be determined.
  ///
  /// Never throws.
  Future<String?> reverseGeocode(LatLng point) async {
    if (!AppConfig.hasMapboxToken) return null;

    final key = _cacheKey(point);
    if (_cache.containsKey(key)) return _cache[key];

    try {
      final uri = Uri.https(
        'api.mapbox.com',
        // Longitude first — the opposite order to every other coordinate in
        // this codebase, and a reliable source of positions in the wrong
        // hemisphere if it is ever "tidied up".
        '/geocoding/v5/mapbox.places/'
            '${point.longitude},${point.latitude}.json',
        {
          'access_token': AppConfig.mapboxAccessToken,
          // Neighbourhood-to-town granularity: "Antipolo" reads like a place a
          // person walked, where a full street address reads like surveillance.
          'types': 'neighborhood,locality,place',
          'limit': '1',
        },
      );

      final response = await _client.get(uri).timeout(_timeout);
      if (response.statusCode != 200) {
        AppLogger.debug(_tag, 'reverse geocode HTTP ${response.statusCode}');
        return _remember(key, null);
      }

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return _remember(key, null);

      final features = body['features'];
      if (features is! List || features.isEmpty) return _remember(key, null);

      final first = features.first;
      if (first is! Map) return _remember(key, null);

      final name = first['text'];
      if (name is! String || name.trim().isEmpty) return _remember(key, null);

      return _remember(key, name.trim());
    } catch (error) {
      // Offline, DNS failure, timeout, malformed JSON — all the same answer.
      AppLogger.debug(_tag, 'reverse geocode failed: $error');
      return _remember(key, null);
    }
  }

  String? _remember(String key, String? value) {
    _cache[key] = value;
    return value;
  }

  static String _cacheKey(LatLng point) =>
      '${point.latitude.toStringAsFixed(3)},'
      '${point.longitude.toStringAsFixed(3)}';

  void dispose() => _client.close();
}

final geocodingServiceProvider = Provider<GeocodingService>((ref) {
  final service = GeocodingService();
  ref.onDispose(service.dispose);
  return service;
});
