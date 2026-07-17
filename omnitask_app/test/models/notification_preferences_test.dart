import 'package:flutter_test/flutter_test.dart';
import 'package:omnitask_app/models/notification_preferences.dart';

void main() {
  group('NotificationPreferences', () {
    test('fromJson/toJson son simétricos en snake_case (§16)', () {
      final json = {
        'default_channel': 'whatsapp',
        'reminder_offsets_minutes': [1440, 60, 15],
      };

      final preferences = NotificationPreferences.fromJson(json);
      expect(preferences.defaultChannel, 'whatsapp');
      expect(preferences.reminderOffsetsMinutes, [1440, 60, 15]);
      expect(preferences.toJson(), json);
    });

    test('usa los valores por defecto documentados si faltan en el JSON', () {
      final preferences = NotificationPreferences.fromJson(const {});
      expect(preferences.defaultChannel, 'both');
      expect(preferences.reminderOffsetsMinutes, [1440, 60]);
    });
  });
}
