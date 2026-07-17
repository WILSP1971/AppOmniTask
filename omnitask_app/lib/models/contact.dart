import 'package:freezed_annotation/freezed_annotation.dart';

part 'contact.freezed.dart';
part 'contact.g.dart';

/// Espejo de ContactResponse (API, §6).
@freezed
class Contact with _$Contact {
  const factory Contact({
    required String id,
    required String fullName,
    required String phoneE164,
    String? notes,
  }) = _Contact;

  factory Contact.fromJson(Map<String, dynamic> json) => _$ContactFromJson(json);
}
