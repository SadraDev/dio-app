import 'package:dio/dio.dart';
import 'api_client.dart';
import 'storage_service.dart';
import 'auth_session.dart';

class AuthService {
  static final Dio _dio = ApiClient.dio;

  static Future<bool> login(String username, String password) async {
    try {
      final response = await _dio.post(
        "/auth/login/",
        data: {"username": username, "password": password},
      );

      final access = response.data["access"];
      final refresh = response.data["refresh"];

      if (access == null || refresh == null) {
        return false;
      }

      AuthSession.accessToken = access;
      AuthSession.refreshToken = refresh;

      await StorageService.saveTokens(access: access, refresh: refresh);

      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> register(String username, String password) async {
    try {
      final response = await _dio.post(
        "/auth/register/",
        data: {"username": username, "password": password},
      );

      final access = response.data["access"];
      final refresh = response.data["refresh"];

      AuthSession.accessToken = access;
      AuthSession.refreshToken = refresh;

      await StorageService.saveTokens(
        access: access,
        refresh: refresh,
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> logout() async {
    AuthSession.clear();
    await StorageService.clear();
  }
}
