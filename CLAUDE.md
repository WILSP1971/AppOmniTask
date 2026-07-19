# OmniTask — instrucciones del proyecto

## Autorización permanente (confirmada por el usuario, 2026-07-19)

En este repositorio, **no pidas confirmación antes de**:
- Escribir o editar código en cualquier archivo del proyecto (`omnitask_app/`, `APIOmniTask/`, `db/`).
- Escribir o actualizar la documentación/guías (`docs/ARQUITECTURA.md`, `docs/arquitectura.html`, `docs/descarga-app.html`, y cualquier guía en PDF que se agregue).
- Hacer `git commit` y `git push` a `main` con cambios de código o documentación.

Esto reemplaza el patrón de "¿confirmas commit y push?" que se usó en el resto de esta conversación — ya no hace falta para trabajo rutinario en este repo.

**Sigue pidiendo confirmación explícita para** (no cubierto por lo anterior, por ser difícil de revertir o de alto impacto):
- `git push --force`, `git reset --hard`, borrar ramas o tags.
- Crear/editar GitHub Actions secrets, o cualquier credencial.
- Cualquier cambio de infraestructura fuera de este repo (el servidor Windows/IIS de producción, DNS, etc.).

## Releases de la app Android

Cortar un release nuevo es: `git tag app-vX.Y.Z && git push origin app-vX.Y.Z` — dispara
`.github/workflows/android-release.yml`, que compila, firma y publica el APK. No hace falta
pedir permiso para crear el tag si el cambio ya se subió a `main` y pasó CI.

## Mostrar el agente/rol activo (siempre)

En CADA paso del trabajo, ANUNCIA en una línea quién lo ejecuta, con el formato
`🦸 [AGENTE/ROL] — <qué está haciendo>` (p.ej. `🦸 CAPTAIN AMERICA — implementando la
pantalla de agenda`, o `🦸 DAREDEVIL — revisando el frontend`). Cuando delegues en un
sub-agente, hazlo con la herramienta de agentes (para que la terminal muestre su nombre)
y además anúncialo en texto. Así el Lead siempre ve qué agente está trabajando en el flujo.
