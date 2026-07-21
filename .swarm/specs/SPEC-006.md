# SPEC-006 — Tipo de actividad "Cumpleaños"

- ID: SPEC-006
- Estado: PROPUESTA (pendiente aprobación explícita del Lead)
- Autor: DOCTOR STRANGE (la aprobación es del Lead humano, nunca del autor)
- Fecha: 2026-07-21
- Responsable de implementación: CAPTAIN AMERICA
- Colaboradores / revisores: BLACK PANTHER (backend/BD), DAREDEVIL (frontend),
  WOLVERINE (calidad), HAWKEYE (pruebas)
- Fuente: pedido directo del Lead ("Optimiza los siguientes modificaciones",
  punto 5).

---

## 1. Objetivo

Agregar "Cumpleaños" como un tipo de actividad más, al mismo nivel que
reunión/cita/tarea — mismo ciclo de vida, mismos recordatorios, sin campos
especiales adicionales (no es una entidad nueva, es un valor más del enum
existente).

## 2. Contexto

- `db/schema.sql` L18: `CREATE TYPE activity_type AS ENUM ('meeting',
  'appointment', 'task', 'activity')`.
- `APIOmniTask/src/OmniTask.Domain/Enums.cs`: `ActivityType { Meeting,
  Appointment, Task, Activity }`, mapeado 1:1 al enum de Postgres vía
  `NpgsqlDataSourceBuilder.MapEnum` en `Program.cs`.
- `activity_edit_screen.dart` tiene el `DropdownButtonFormField` con las 3
  opciones actuales (`meeting`/`appointment`/`task`) — el valor `'activity'` del
  enum de BD no se expone hoy en la UI (uso interno/legado).
- `activity_colors.dart::colorForActivityType` y el ícono nuevo de SPEC-005
  necesitan un `case 'birthday'`.

## 3. Requisitos funcionales

- **RF1 — Nuevo valor de enum, aditivo.** Script nuevo `db/07_*.sql`:
  `ALTER TYPE activity_type ADD VALUE 'birthday'` — Postgres no permite este
  `ALTER TYPE` dentro de la misma transacción en la que luego se usa el valor,
  así que el script va solo, sin combinarse con otros cambios en el mismo
  archivo/transacción.
- **RF2 — Backend.** Agregar `Birthday` a `OmniTask.Domain.Enums.ActivityType`.
  Sin cambios de contrato (mismo campo `type` en el JSON, ahora acepta
  `"birthday"` además de los valores existentes) — `EnumParsing.Parse<ActivityType>`
  ya maneja cualquier valor nuevo del enum sin tocarlo.
- **RF3 — Frontend.** `activity_edit_screen.dart`: agregar
  `DropdownMenuItem(value: 'birthday', child: Text('Cumpleaños'))` a la lista de
  tipos. `activity_colors.dart`: color propio para `'birthday'` (no reutilizar
  ninguno de los 3 existentes, para que se distinga en el calendario/tarjetas).

## 4. Requisitos no funcionales

- **RNF1 — Aditivo, sin romper datos existentes.** Las actividades ya creadas
  con los 4 valores actuales del enum siguen funcionando igual — `ALTER TYPE ...
  ADD VALUE` no reescribe filas existentes.
- **RNF2 — No regresión.** Cero cambios en la lógica del calendario
  (`allowedViews`/`initialDisplayDate`/`skipLoadingOnReload`/`table_calendar`) ni
  en el resto de endpoints de `/activities`.
- **RNF3 — Consistencia de capas.** Mismo patrón que los 3 tipos existentes en
  todas las capas — no se crea una tabla ni un servicio nuevo para "cumpleaños".

## 5. Criterios de aceptación verificables

- [ ] CA1: Se puede crear una actividad con `type: "birthday"` desde la app
      (dropdown "Cumpleaños") y desde la API directamente (ver
      `docs/pruebas-api.html`).
- [ ] CA2: La actividad de tipo cumpleaños se lista, edita, reprograma y cancela
      igual que cualquier otra (mismos endpoints, sin 500 ni comportamiento
      especial).
- [ ] CA3: Tiene su propio color e ícono, distintos de reunión/cita/tarea, en
      calendario y tarjetas.
- [ ] CA4 (transversal): `dotnet test`/`flutter test`/`flutter analyze` en verde;
      migración aplicada sin error contra Postgres real (CI).
- [ ] C-NR (no regresión): actividades existentes con los 4 valores previos del
      enum siguen funcionando en `list`/`get`/`patch` sin cambios.

## 6. Riesgos y dependencias

- **R1 — `ALTER TYPE ... ADD VALUE` y transacciones.** Si el pipeline de CI o de
  despliegue intenta aplicar este script dentro de la misma transacción que otro
  `ALTER`/`INSERT` que ya use el valor nuevo, Postgres lo rechaza. El script debe
  aplicarse solo, como los anteriores `db/0N_*.sql` incrementales.
- **R2 — Depende de SPEC-005** para el ícono/color final (pueden implementarse en
  cualquier orden; si SPEC-005 ya agregó el `case 'birthday'` de forma
  anticipada, aquí solo se confirma que compila con el valor real del enum).

## 7. Alcance EXCLUIDO (explícito)

- Recurrencia automática (repetir cada año): fuera — un cumpleaños se crea como
  cualquier otra actividad puntual, sin repetición automática.
- Campos especiales (nombre del cumpleañero si es distinto del contacto, edad,
  etc.): fuera — usa los mismos campos que cualquier actividad (`title`,
  `contact_id`, `starts_at`, etc.).
