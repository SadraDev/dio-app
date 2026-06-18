import 'package:dio/dio.dart';
import 'storage_service.dart';
import 'auth_session.dart';

class ApiClient {
  static final Dio dio = Dio(
    BaseOptions(
      baseUrl: "http://10.0.2.2:8000/api",
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {"Content-Type": "application/json"},
    ),
  );

  static void init() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token =
              AuthSession.accessToken ?? await StorageService.getAccessToken();

          if (token != null && token.trim().isNotEmpty) {
            options.headers["Authorization"] = "Bearer ${token.trim()}";
          }

          handler.next(options);
        },

        onError: (DioException e, handler) async {
          final status = e.response?.statusCode;

          // 🔥 AUTO REFRESH ON 401
          if (status == 401) {
            final refreshed = await _refreshToken();

            if (refreshed) {
              final retryResponse = await dio.fetch(e.requestOptions);
              return handler.resolve(retryResponse);
            }
          }

          handler.next(e);
        },
      ),
    );
  }

  static Future<bool> _refreshToken() async {
    try {
      final refresh =
          AuthSession.refreshToken ?? await StorageService.getRefreshToken();

      if (refresh == null || refresh.isEmpty) {
        return false;
      }

      final response = await dio.post(
        "/auth/refresh/",
        data: {"refresh": refresh},
      );

      final newAccess = response.data["access"];

      if (newAccess == null) return false;

      AuthSession.accessToken = newAccess;

      await StorageService.saveTokens(access: newAccess, refresh: refresh);

      return true;
    } catch (_) {
      AuthSession.clear();
      await StorageService.clear();
      return false;
    }
  }

  static Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await dio.get(path, queryParameters: queryParameters);
      return response.data;
    } on DioException catch (e) {
      final responseData = e.response?.data;
      String message = "Request failed: ${e.response?.statusCode}";

      if (responseData is Map) {
        if (responseData.containsKey('error')) {
          message = responseData['error'].toString();
        } else if (responseData.containsKey('detail')) {
          message = responseData['detail'].toString();
        } else {
          message = responseData.values.map((v) => v.toString()).join(", ");
        }
      } else if (responseData is String) {
        message = responseData;
      } else if (responseData is List) {
        message = responseData.join(", ");
      }

      throw message;
    }
  }

  static Future<dynamic> post(String path, {Map<String, dynamic>? body}) async {
    try {
      final response = await dio.post(path, data: body);
      return response.data;
    } on DioException catch (e) {
      final responseData = e.response?.data;
      String message = "Request failed: ${e.response?.statusCode}";

      if (responseData is Map) {
        if (responseData.containsKey('error')) {
          message = responseData['error'].toString();
        } else if (responseData.containsKey('detail')) {
          message = responseData['detail'].toString();
        } else {
          message = responseData.values.map((v) => v.toString()).join(", ");
        }
      } else if (responseData is String) {
        message = responseData;
      } else if (responseData is List) {
        message = responseData.join(", ");
      }

      throw message;
    }
  }
}
