import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omnitask_app/core/storage/secure_token_storage.dart';
import 'package:omnitask_app/features/auth/data/auth_repository.dart';
import 'package:omnitask_app/features/auth/presentation/login_screen.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockSecureTokenStorage extends Mock implements SecureTokenStorage {}

void main() {
  testWidgets('la validación de correo bloquea el envío antes de llamar al backend', (tester) async {
    final storage = MockSecureTokenStorage();
    when(() => storage.readRefreshToken()).thenAnswer((_) async => null);
    final authRepository = MockAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureTokenStorageProvider.overrideWithValue(storage),
          authRepositoryProvider.overrideWithValue(authRepository),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Correo'), 'correo-sin-arroba');
    await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña'), 'lo-que-sea');
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pump();

    expect(find.text('Correo inválido'), findsOneWidget);
    verifyNever(() => authRepository.login(any(), any()));
  });
}
