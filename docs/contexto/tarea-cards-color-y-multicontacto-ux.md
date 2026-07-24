# Tarea: (A) fondo de tarjetas con color del día + (B) BUG: búsqueda de contactos atascada

## A) El fondo de la tarjeta NO usa el color del día
`omnitask_app/lib/features/calendar/presentation/widgets/appointment_card.dart`: el `Container` usa
`decoration: BoxDecoration(color: colorScheme.surfaceContainerLow)` (oscuro fijo). El color del día
(`typeColor`, que llega por `AppointmentCard.color` desde `AppointmentsSection.dayColor`, SPEC-005)
SOLO se usa en el badge de fecha y una barrita.
Fix: pintar el **FONDO de la tarjeta con `typeColor`** (color del día) — sólido/tinte fuerte al estilo
de `docs/contexto/agenda2.jpg` / `agenda3.jpg`, con texto legible (título blanco/negrita). Aplicar en
"Mis citas" Y en "Pendientes por programar". Reutilizar el color ya calculado (`colorForDay` en
calendar_screen.dart), no recalcular.

## B) BUG (confirmado): la búsqueda de contactos muestra spinner infinito y NO lista resultados
Reproducción: usuario con ≥1 contacto llamado "Jorge" → en "Nueva actividad", campo "Contactos",
escribe "Jorge" → aparece el spinner y **nunca** muestra la lista (aunque hay 3 contactos "Jorge").

Ya diagnosticado (NO es el backend):
- `GET /api/v1/contacts?search=Jorge` responde **200** con la lista (fn_list_contacts filtra con
  ILIKE). La app llama bien el endpoint (`contact_repository.search` -> GET /contacts?search=).
- `build.yaml` tiene `field_rename: snake` global, así que `Contact.fromJson` mapea snake_case.
- Causa raíz en `contact_picker_field.dart` -> `_onQueryChanged`: NO tiene try/catch. Si `search()`
  lanza una excepción (DioException/timeout/parse/lo que sea), el `await` corta ANTES de
  `setState(() => _isSearching = false)` → el spinner queda encendido para siempre y `_results`
  vacío. Por eso "muestra loading pero no lista".

Fix:
1. Envolver la búsqueda en try/catch/finally: en `finally` SIEMPRE `setState(_isSearching=false)`;
   en `catch` dejar un estado de error visible ("No se pudo buscar, reintenta") en vez de spinner
   colgado.
2. Diagnosticar y corregir la EXCEPCIÓN real que lanza `search()` para cuentas con contactos
   (reproducir con `adb logcat` mientras se escribe en el campo; revisar la respuesta y el parseo).
3. Asegurar que la lista de resultados se **renderice y sea visible** (que el teclado no la tape;
   considerar un overlay/dropdown ancla al campo).
4. Diferenciar "sin resultados" (lista vacía, ok) de "error" (falló la búsqueda).
5. Verificar el flujo completo: escribir un nombre -> ver resultados -> tocar para agregar varios
   como chips -> guardar (el backend multi-contacto ya funciona; `POST /activities` con `contact_ids`
   validado).

## Restricciones
- Solo frontend (`omnitask_app/**`); NO tocar backend/BD.
- snake_case; mantener el diseño oscuro + paleta (agenda2/agenda3), anti-bucle del calendario y
  la localización en español.

## Entrega
- Plan breve al Lead (pantallazo antes/después de la tarjeta) antes de terminar.
- flutter analyze + test verdes. Release por tag (siguiente app-vX.Y.Z).
