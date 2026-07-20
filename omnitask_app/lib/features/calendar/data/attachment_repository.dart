import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../models/attachment.dart';

/// Adjuntos de una actividad (SPEC-002, §3): sube/lista/descarga/elimina
/// contra `api/v1/activities/{activityId}/attachments`. Mismo patrón que
/// ActivityRepository — un Dio ya autenticado por DioClient.
class AttachmentRepository {
  AttachmentRepository(this._dio);
  final Dio _dio;

  Future<List<Attachment>> list(String activityId) async {
    final response = await _dio.get('/activities/$activityId/attachments');
    return (response.data as List)
        .map((j) => Attachment.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// [fileName] y [contentType] van al backend en el multipart; el servidor
  /// valida tipo/tamaño (SPEC-002 §3 RF7) y responde 4xx si no cumple.
  Future<Attachment> upload({
    required String activityId,
    required String fileName,
    required String contentType,
    required List<int> bytes,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: fileName,
        contentType: DioMediaType.parse(contentType),
      ),
    });
    final response = await _dio.post(
      '/activities/$activityId/attachments',
      data: formData,
    );
    return Attachment.fromJson(response.data as Map<String, dynamic>);
  }

  /// Descarga los bytes íntegros del adjunto (SPEC-002 §3 RF3) para abrirlo
  /// con el visor del sistema.
  Future<List<int>> download(String activityId, String attachmentId) async {
    final response = await _dio.get<List<int>>(
      '/activities/$activityId/attachments/$attachmentId',
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? const <int>[];
  }

  Future<void> delete(String activityId, String attachmentId) =>
      _dio.delete('/activities/$activityId/attachments/$attachmentId');
}

final attachmentRepositoryProvider = Provider<AttachmentRepository>(
  (ref) => AttachmentRepository(ref.watch(dioClientProvider)),
);
