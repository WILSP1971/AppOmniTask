import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../models/device.dart';
import '../../notifications/data/device_repository.dart';

part 'devices_provider.g.dart';

@riverpod
Future<List<Device>> myDevices(MyDevicesRef ref) {
  return ref.watch(deviceRepositoryProvider).fetchAll();
}

@riverpod
Future<String?> currentFcmToken(CurrentFcmTokenRef ref) {
  return FirebaseMessaging.instance.getToken();
}
