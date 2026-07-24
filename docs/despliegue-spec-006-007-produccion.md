# Despliegue de SPEC-006 (Cumpleaños) y SPEC-007 (limpiar notificaciones) en producción

Checklist operativo para llevar estos dos cambios de BD + backend al servidor
Windows/IIS de producción (`https://appsintranet.esculapiosis.com/APIOmniTask`,
`docs/ARQUITECTURA.md` §18-19). Sin este paso, la app ya muestra "Cumpleaños"
en el formulario (viene del cliente Flutter, ya publicado en el release), pero
**crear una actividad de ese tipo falla contra el servidor real** — el enum
`activity_type` de la base de datos en producción todavía no tiene el valor
`'birthday'`, y el backend desplegado ahí todavía no reconoce
`ActivityType.Birthday` ni el endpoint `DELETE /notifications`.

## 1. Aplicar las dos migraciones SQL contra Postgres de producción

En el servidor, con el rol `omnitask_api` (o el superusuario que ya se use para
migraciones anteriores, mismo patrón que `db/02_*.sql` en adelante):

```powershell
psql -U omnitask_api -d omnitask -f db\07_activity_type_birthday.sql
psql -U omnitask_api -d omnitask -f db\08_clear_notifications.sql
```

**Por qué van en dos pasos y en este orden:**
- `07_activity_type_birthday.sql` hace `ALTER TYPE activity_type ADD VALUE` —
  Postgres no permite usar un valor de enum recién agregado en la misma
  transacción en la que se agrega, por eso es un script propio, no se combina
  con otros cambios.
- `08_clear_notifications.sql` (el procedimiento `sp_clear_notifications`) no
  depende de `07`, pero se aplica junto porque ambos SPEC quedaron listos en
  el mismo commit.

**Verificación:**

```sql
SELECT enum_range(NULL::activity_type);
-- debe incluir 'birthday' en la lista
\df sp_clear_notifications
-- debe existir
```

## 2. Republicar el backend (`OmniTask.Api`)

Mismo procedimiento que ya se usa para cualquier otro cambio de backend en
este servidor (no cambia por esta SPEC):

1. `dotnet publish APIOmniTask/src/OmniTask.Api -c Release -o <carpeta-de-publicación>`
   desde un commit que incluya `840a2bc` o posterior (donde vive
   `ActivityType.Birthday` y `NotificationsController.ClearAll`).
2. Copiar la publicación a la carpeta que sirve la sub-aplicación IIS
   `/APIOmniTask` en el servidor.
3. Reciclar el Application Pool de `OmniTask.Api` en IIS Manager.

## 3. Validar en producción

- Crear una actividad de tipo "Cumpleaños" con fecha desde la app real (o
  con `docs/pruebas-api.html`, `POST /activities` con `"type": "birthday"`) y
  confirmar que responde `201` y aparece en el calendario.
- `DELETE /api/v1/notifications` (o el botón "Limpiar historial" en la app)
  responde `204` y deja la bandeja vacía.

## Resumen en orden

1. `psql ... -f db/07_activity_type_birthday.sql`
2. `psql ... -f db/08_clear_notifications.sql`
3. Verificar `enum_range(NULL::activity_type)` y `\df sp_clear_notifications`.
4. `dotnet publish` del backend actualizado, copiar al servidor.
5. Reciclar el Application Pool.
6. Probar crear un "Cumpleaños" con fecha y "Limpiar historial" desde la app.
