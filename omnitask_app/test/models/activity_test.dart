import 'package:flutter_test/flutter_test.dart';
import 'package:omnitask_app/models/activity.dart';

void main() {
  group('Activity.fromJson', () {
    test('parsea una actividad programada con reminders embebidos', () {
      final activity = Activity.fromJson({
        'id': 'a1',
        'user_id': 'u1',
        'contact_id': 'c1',
        'type': 'appointment',
        'title': 'Control',
        'description': 'Revisión general',
        'status': 'scheduled',
        'starts_at': '2026-07-14T20:00:00Z',
        'ends_at': '2026-07-14T20:30:00Z',
        'timezone': 'America/Bogota',
        'location': 'Consultorio 3',
        'created_at': '2026-07-01T10:00:00Z',
        'updated_at': '2026-07-01T10:00:00Z',
        'reminders': [
          {'id': 'r1', 'remind_at': '2026-07-14T19:00:00Z', 'channel': 'push', 'status': 'pending'},
        ],
      });

      expect(activity.id, 'a1');
      expect(activity.startsAt, DateTime.utc(2026, 7, 14, 20));
      expect(activity.reminders, hasLength(1));
      expect(activity.reminders.single.channel, 'push');
    });

    // "Sin fecha" es un estado de primera clase (§3, §6) — el modelo debe
    // aceptar starts_at/ends_at ausentes sin lanzar, y no inventar un reminder.
    test('parsea una actividad sin fecha (unscheduled) sin reminders', () {
      final activity = Activity.fromJson({
        'id': 'a2',
        'user_id': 'u1',
        'contact_id': null,
        'type': 'task',
        'title': 'Llamar al proveedor',
        'description': null,
        'status': 'unscheduled',
        'starts_at': null,
        'ends_at': null,
        'timezone': 'America/Bogota',
        'location': null,
        'created_at': '2026-07-01T10:00:00Z',
        'updated_at': '2026-07-01T10:00:00Z',
      });

      expect(activity.startsAt, isNull);
      expect(activity.status, 'unscheduled');
      expect(activity.reminders, isEmpty);
    });
  });
}
