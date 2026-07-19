import 'package:flutter/material.dart';

/// Tema central de OmniTask (Material 3). Un único lugar para colores, tipografía
/// y formas — así el resto de pantallas hereda el look moderno solo con
/// `Theme.of(context)` / widgets estándar, sin repetir estilos pantalla por
/// pantalla.
abstract final class AppTheme {
  static const _seed = Color(0xFF0E7C72);

  // Paleta oscura (§rediseño visual, referencias agenda2/agenda3): fondo
  // azul-carbón profundo con paneles/tarjetas un tono más claro y acento
  // periwinkle — reemplaza el seed teal solo en brightness.dark para no
  // afectar el ColorScheme.fromSeed que ya usan otras partes del código.
  static const _darkBackground = Color(0xFF1C2733);
  static const _darkSurface = Color(0xFF26313F);
  static const _darkSurfaceHigh = Color(0xFF2A3646);
  static const _darkPrimary = Color(0xFF4A6CF7);
  static const _darkTextPrimary = Color(0xFFF5F7FA);
  static const _darkTextSecondary = Color(0xFF8A97A8);

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
    );
    return _themeFor(colorScheme);
  }

  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _darkPrimary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _darkPrimary,
      onPrimary: Colors.white,
      primaryContainer: _darkPrimary,
      onPrimaryContainer: Colors.white,
      secondary: const Color(0xFF26C6A6),
      tertiary: const Color(0xFFF5A623),
      surface: _darkBackground,
      onSurface: _darkTextPrimary,
      surfaceContainerLow: _darkSurface,
      surfaceContainer: _darkSurface,
      surfaceContainerHigh: _darkSurfaceHigh,
      surfaceContainerHighest: _darkSurfaceHigh,
      onSurfaceVariant: _darkTextSecondary,
      outline: _darkTextSecondary.withValues(alpha: 0.6),
      outlineVariant: _darkTextSecondary.withValues(alpha: 0.24),
      error: const Color(0xFFEF6C6C),
    );
    return _themeFor(colorScheme);
  }

  static ThemeData _themeFor(ColorScheme colorScheme) {
    final base = ThemeData(colorScheme: colorScheme, useMaterial3: true);
    final textTheme = _textTheme(base.textTheme, colorScheme);

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: colorScheme.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        titleTextStyle:
            textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        backgroundColor: colorScheme.surfaceContainerHighest,
        labelStyle: textTheme.labelLarge,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle:
              textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dividerTheme: DividerThemeData(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      drawerTheme: DrawerThemeData(
        backgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
              topRight: Radius.circular(24), bottomRight: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base, ColorScheme colorScheme) {
    return base.copyWith(
      headlineSmall: base.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: base.bodyMedium?.copyWith(height: 1.35),
      labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}
