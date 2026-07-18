import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitask_app/features/calendar/data/activity_repository.dart';
import 'package:omnitask_app/models/activity_draft.dart';

/// Captura la petición que Dio armaría, sin llegar a la red — resuelve la
/// respuesta con un eco del cuerpo enviado para poder inspeccionarlo.
class _RecordingInterceptor extends Interceptor {
  RequestOptions? lastRequest;
  final List<RequestOptions> requests = [];

  /// Permite a cada prueba decidir la respuesta según la petición (p.ej. según
  /// `page`) — por defecto, un eco de una sola actividad, como antes.
  Response Function(RequestOptions options)? responseBuilder;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    lastRequest = options;
    requests.add(options);
    final response = responseBuilder?.call(options) ??
        Response(requestOptions: options, statusCode: 200, data: _fakeActivityJson());
    handler.resolve(response);
  }
}

Map<String, dynamic> _fakeActivityJson({String id = 'a1'}) => {
      'id': id,
      'user_id': 'u1',
      'contact_id': null,
      'type': 'appointment',
      'title': 'Control',
      'description': null,
      'status': 'scheduled',
      'starts_at': '2026-07-14T20:00:00Z',
      'ends_at': null,
      'timezone': 'America/Bogota',
      'location': null,
      'created_at': '2026-07-01T10:00:00Z',
      'updated_at': '2026-07-01T10:00:00Z',
    };

void main() {
  late Dio dio;
  late _RecordingInterceptor recorder;
  late ActivityRepository repository;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://test.local/api/v1'));
    recorder = _RecordingInterceptor();
    dio.interceptors.add(recorder);
    repository = ActivityRepository(dio);
  });

  group('fetchActivities — paginación (vistas de Mes/Agenda, §27)', () {
    test('una sola página alcanza para cubrir el total', () async {
      recorder.responseBuilder = (options) => Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'items': [_fakeActivityJson()],
              'page': 1,
              'limit': 100,
              'total': 1,
            },
          );

      final result = await repository.fetchActivities(
        from: DateTime(2026, 7, 1),
        to: DateTime(2026, 7, 8),
      );

      expect(recorder.requests, hasLength(1));
      expect(result.items, hasLength(1));
    });

    test('junta todas las páginas cuando el total supera una sola página', () async {
      recorder.responseBuilder = (options) {
        final page = int.parse(options.queryParameters['page'].toString());
        final items = page == 1
            ? List.generate(100, (i) => _fakeActivityJson(id: 'a$i'))
            : List.generate(50, (i) => _fakeActivityJson(id: 'b$i'));
        return Response(
          requestOptions: options,
          statusCode: 200,
          data: {'items': items, 'page': page, 'limit': 100, 'total': 150},
        );
      };

      final result = await repository.fetchActivities(
        from: DateTime(2026, 7, 1),
        to: DateTime(2026, 8, 1),
      );

      expect(recorder.requests, hasLength(2));
      expect(recorder.requests[0].queryParameters['page'], 1);
      expect(recorder.requests[1].queryParameters['page'], 2);
      expect(result.items, hasLength(150));
      expect(result.total, 150);
    });
  });

  group('create', () {
    test('manda type/title/contact_id y fechas en UTC (§6)', () async {
      final localStart = DateTime(2026, 7, 14, 15); // hora local, no UTC

      await repository.create(ActivityDraft(
        type: 'appointment',
        title: 'Control',
        contactId: 'c1',
        startsAt: localStart,
      ));

      final body = recorder.lastRequest!.data as Map<String, dynamic>;
      expect(recorder.lastRequest!.path, '/activities');
      expect(body['type'], 'appointment');
      expect(body['contact_id'], 'c1');
      expect(body['starts_at'], localStart.toUtc().toIso8601String());
    });
  });

  group('update — clear_starts_at/clear_ends_at (§23)', () {
    // Regresión directa del bug real: un simple starts_at nulo no bastaba
    // para distinguir "no tocar" de "quitar la fecha" (§14, §23).
    test('reprogramar manda la nueva fecha con clear_starts_at en false', () async {
      final newStart = DateTime(2026, 8, 1, 10);

      await repository.update('a1', startsAt: newStart, clearStartsAt: false);

      final body = recorder.lastRequest!.data as Map<String, dynamic>;
      expect(body['starts_at'], newStart.toUtc().toIso8601String());
      expect(body['clear_starts_at'], false);
    });

    test('quitar la fecha manda clear_starts_at en true y sin starts_at', () async {
      await repository.update('a1', clearStartsAt: true, clearEndsAt: true);

      final body = recorder.lastRequest!.data as Map<String, dynamic>;
      expect(body.containsKey('starts_at'), isFalse);
      expect(body.containsKey('ends_at'), isFalse);
      expect(body['clear_starts_at'], true);
      expect(body['clear_ends_at'], true);
    });

    test('una edición que no toca la fecha manda ambos flags en false', () async {
      await repository.update('a1', title: 'Nuevo título');

      final body = recorder.lastRequest!.data as Map<String, dynamic>;
      expect(body['title'], 'Nuevo título');
      expect(body.containsKey('starts_at'), isFalse);
      expect(body['clear_starts_at'], false);
      expect(body['clear_ends_at'], false);
    });
  });

  test('cancel llama DELETE /activities/{id} (soft delete, §6)', () async {
    await repository.cancel('a1');
    expect(recorder.lastRequest!.method, 'DELETE');
    expect(recorder.lastRequest!.path, '/activities/a1');
  });
}
