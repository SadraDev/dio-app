import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/candle.dart';

class StorageService {
  static const _storage = FlutterSecureStorage();

  static const _accessKey = "access_token";
  static const _refreshKey = "refresh_token";

  // Cap cached bars so the encrypted blob stays small/fast.
  static const int _maxCachedCandles = 400;

  static Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  static Future<String?> getAccessToken() async {
    return _storage.read(key: _accessKey);
  }

  static Future<String?> getRefreshToken() async {
    return _storage.read(key: _refreshKey);
  }

  static Future<void> clear() async {
    await _storage.deleteAll();
  }

  // ──────────────────────────────────────────────────────────────────
  // Candle cache: lets the chart paint instantly from disk while the
  // fresh data is fetched in the background.
  // ──────────────────────────────────────────────────────────────────
  static String _candleKey(String symbol, String timeframe) =>
      "candles_${symbol}_$timeframe";

  static Future<void> cacheCandles(
      String symbol,
      String timeframe,
      List<Candle> candles,
      ) async {
    if (candles.isEmpty) return;
    final capped = candles.length > _maxCachedCandles
        ? candles.sublist(candles.length - _maxCachedCandles)
        : candles;

    final data = capped
        .map((c) => {
      "time": c.time.toIso8601String(),
      "open": c.open,
      "high": c.high,
      "low": c.low,
      "close": c.close,
      "volume": c.volume,
    })
        .toList();

    try {
      await _storage.write(key: _candleKey(symbol, timeframe), value: jsonEncode(data));
    } catch (_) {
      // caching is best-effort; never block the UI on a write failure
    }
  }

  static Future<List<Candle>> loadCachedCandles(
      String symbol,
      String timeframe,
      ) async {
    try {
      final raw = await _storage.read(key: _candleKey(symbol, timeframe));
      if (raw == null) return [];
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Candle.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
