import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Replace with your Cloudflare Tunnel URL once the Pi is configured.
const String _baseUrl = 'https://api.blablacase.com';

Dio createApiClient() {
  final dio = Dio(BaseOptions(baseUrl: _baseUrl, connectTimeout: const Duration(seconds: 10)));

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final token = await user.getIdToken();
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ),
  );

  return dio;
}
