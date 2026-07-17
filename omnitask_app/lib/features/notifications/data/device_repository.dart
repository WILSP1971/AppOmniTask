import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../models/device.dart';

class DeviceRepository {
  DeviceRepository(this._dio);
  final Dio _dio;

  Future<void> register({required String fcmToken, required String platform}) =>
      _dio.post('/devices', data: {'fcm_token': fcmToken, 'platform': platform});

  Future<List<Device>> fetchAll() async {
    final response = await _dio.get('/devices');
    return (response.data as List).map((j) => Device.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<void> delete(String id) => _dio.delete('/devices/$id');
}

final deviceRepositoryProvider = Provider<DeviceRepository>(
  (ref) => DeviceRepository(ref.watch(dioClientProvider)),
);
