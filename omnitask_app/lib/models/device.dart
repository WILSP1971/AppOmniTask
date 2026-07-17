import 'package:freezed_annotation/freezed_annotation.dart';

part 'device.freezed.dart';
part 'device.g.dart';

/// Espejo de DeviceResponse (API, §8, §16).
@freezed
class Device with _$Device {
  const factory Device({
    required String id,
    required String fcmToken,
    required String platform,
    required DateTime lastSeenAt,
  }) = _Device;

  factory Device.fromJson(Map<String, dynamic> json) => _$DeviceFromJson(json);
}
