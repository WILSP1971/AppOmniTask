import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitask_app/features/calendar/data/attachment_repository.dart';

/// Mismo patrón que activity_repository_test.dart: un interceptor que
/// captura la petición sin llegar a la red, y decide la respuesta según lo
/// que necesite cada prueba (SPEC-002 §3 RF1-RF4).
class _RecordingInterceptor extends Interceptor {
  RequestOptions? lastRequest;
  final List<RequestOptions> requests = [];
  Response Function(RequestOptions options)? responseBuilder;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    lastRequest = options;
    requests.add(options);
    final response = responseBuilder?.call(options) ??
        Response(requestOptions: options, statusCode: 200, data: _fakeAttachmentJson());
    handler.resolve(response);
  }
}

Map<String, dynamic> _fakeAttachmentJson({String id = 'att1'}) => {
      'id': id,
      'activity_id': 'a1',
      'file_name': 'informe.pdf',
      'content_type': 'application/pdf',
      'size_bytes': 2048,
      'uploaded_at': '2026-07-20T10:00:00Z',
    };

void main() {
  late Dio dio;
  late _RecordingInterceptor recorder;
  late AttachmentRepository repository;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://test.local/api/v1'));
    recorder = _RecordingInterceptor();
    dio.interceptors.add(recorder);
    repository = AttachmentRepository(dio);
  });

  test('list — GET a /activities/{id}/attachments y mapea la lista (CA2)', () async {
    recorder.responseBuilder = (options) => Response(
          requestOptions: options,
          statusCode: 200,
          data: [_fakeAttachmentJson(id: 'att1'), _fakeAttachmentJson(id: 'att2')],
        );

    final result = await repository.list('a1');

    expect(recorder.lastRequest!.method, 'GET');
    expect(recorder.lastRequest!.path, '/activities/a1/attachments');
    expect(result, hasLength(2));
    expect(result.first.fileName, 'informe.pdf');
    expect(result.first.contentType, 'application/pdf');
  });

  test('upload — POST multipart con el campo file y devuelve el DTO (RF1)', () async {
    final result = await repository.upload(
      activityId: 'a1',
      fileName: 'foto.jpg',
      contentType: 'image/jpeg',
      bytes: [1, 2, 3, 4],
    );

    expect(recorder.lastRequest!.method, 'POST');
    expect(recorder.lastRequest!.path, '/activities/a1/attachments');
    final formData = recorder.lastRequest!.data as FormData;
    expect(formData.files, hasLength(1));
    expect(formData.files.single.key, 'file');
    expect(formData.files.single.value.filename, 'foto.jpg');
    expect(result.fileName, 'informe.pdf'); // eco de la respuesta fake
  });

  test('download — GET con responseType bytes al endpoint de descarga (RF3)', () async {
    recorder.responseBuilder = (options) => Response(
          requestOptions: options,
          statusCode: 200,
          data: [10, 20, 30],
        );

    final bytes = await repository.download('a1', 'att1');

    expect(recorder.lastRequest!.method, 'GET');
    expect(recorder.lastRequest!.path, '/activities/a1/attachments/att1');
    expect(recorder.lastRequest!.responseType, ResponseType.bytes);
    expect(bytes, [10, 20, 30]);
  });

  test('delete — DELETE al adjunto correcto (RF4)', () async {
    await repository.delete('a1', 'att1');

    expect(recorder.lastRequest!.method, 'DELETE');
    expect(recorder.lastRequest!.path, '/activities/a1/attachments/att1');
  });
}
