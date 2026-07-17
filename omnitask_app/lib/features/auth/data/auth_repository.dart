import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../models/notification_preferences.dart';
import '../../../models/user.dart';

/// Los cinco endpoints de /auth (§6, §10, §15).
class AuthRepository {
  AuthRepository(this._dio);
  final Dio _dio;

  Future<(User, String, String)> register({
    required String fullName,
    required String email,
    required String password,
    required String phoneE164,
    required String timezone,
  }) async {
    final response = await _dio.post('/auth/register', data: {
      'full_name': fullName,
      'email': email,
      'password': password,
      'phone_e164': phoneE164,
      'timezone': timezone,
    });
    return (
      User.fromJson(response.data['user'] as Map<String, dynamic>),
      response.data['access_token'] as String,
      response.data['refresh_token'] as String,
    );
  }

  Future<(String, String)> login(String email, String password) async {
    final response = await _dio.post('/auth/login', data: {
      'email': email,
      'password': password,
    });
    return (response.data['access_token'] as String, response.data['refresh_token'] as String);
  }

  Future<(String, String)> refresh(String refreshToken) async {
    final response = await _dio.post('/auth/refresh', data: {'refresh_token': refreshToken});
    return (response.data['access_token'] as String, response.data['refresh_token'] as String);
  }

  Future<void> logout(String refreshToken) =>
      _dio.post('/auth/logout', data: {'refresh_token': refreshToken});

  Future<User> fetchMe() async {
    final response = await _dio.get('/auth/me');
    return User.fromJson(response.data as Map<String, dynamic>);
  }

  Future<User> updateProfile({
    String? fullName,
    String? phoneE164,
    String? timezone,
    NotificationPreferences? preferences,
  }) async {
    final response = await _dio.patch('/auth/me', data: {
      if (fullName != null) 'full_name': fullName,
      if (phoneE164 != null) 'phone_e164': phoneE164,
      if (timezone != null) 'timezone': timezone,
      if (preferences != null) 'notification_preferences': preferences.toJson(),
    });
    return User.fromJson(response.data as Map<String, dynamic>);
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(dioClientProvider)),
);
