import 'package:freezed_annotation/freezed_annotation.dart';

part 'attachment.freezed.dart';
part 'attachment.g.dart';

/// Espejo de AttachmentResponse (API, SPEC-002 §6): solo metadatos, nunca los
/// bytes del archivo (esos se piden aparte con el endpoint de descarga).
@freezed
class Attachment with _$Attachment {
  const factory Attachment({
    required String id,
    required String activityId,
    required String fileName,
    required String contentType,
    required int sizeBytes,
    required DateTime uploadedAt,
  }) = _Attachment;

  factory Attachment.fromJson(Map<String, dynamic> json) =>
      _$AttachmentFromJson(json);
}
