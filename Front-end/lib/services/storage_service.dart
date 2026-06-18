import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static const _storage = FlutterSecureStorage();

  static const _accessKey = "access_token";
  static const _refreshKey = "refresh_token";

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
}