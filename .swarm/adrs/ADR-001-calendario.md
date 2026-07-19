# ADR-001 — Motor de calendario para Home rediseñado

- Estado: PROPUESTA (SPEC-001)
- Fecha: 2026-07-19

## Contexto
El mockup requiere día seleccionado en círculo de color, puntitos por tipo y píldoras
multi-día. SfCalendar dificulta ese look y arrastra un guard anti-bucle de refetch.

## Decisión (recomendada)
Migrar de SfCalendar a `table_calendar` para la vista mensual, usando sus builders
(`calendarBuilders`: selected/marker/range) para lograr círculo + puntitos + píldoras.
La lista/grid inferior filtra por día seleccionado y cubre lo que hacían Day/Week/Schedule.

## Consecuencias
- (+) Look objetivo directo; elimina el guard `skipLoadingOnReload`/`_handleViewChanged`.
- (+) Menos superficie de bucle de refetch (validar con C2).
- (-) Nueva dependencia en pubspec.yaml (requiere aprobación del Lead).
- (-) UX de Week/Day cambia a lista filtrada (mitigado en SPEC-001 R1).

## Alternativa descartada
Mantener SfCalendar personalizando cell/month builder: mayor esfuerzo para igualar el
mockup y hay que conservar el guard anti-bucle tal cual.
