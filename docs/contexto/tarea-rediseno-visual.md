# Tarea: REDISEÑAR el frontend/vistas de OmniTask con el DISEÑO Y COLORES de las imágenes

## Corrección importante
El release v1.0.8 SOLO aplicó tema oscuro; NO es lo pedido. Se requiere
**reconstruir el LAYOUT y los COMPONENTES de las vistas** para que se vean como
los mockups (con sus colores), usando los datos reales de OmniTask. No es cambiar
colores nada más.

## Referencias (ABRIRLAS con la herramienta de lectura de imágenes) y qué tomar de cada una
- docs/contexto/agenda2.jpg = **calendario mensual + las actividades de cada día**:
  rejilla del mes con día seleccionado en CÍRCULO de color y PUNTITOS de color bajo
  los días con actividades; debajo, sección "Mis citas" en LISTA, cada fila con un
  BADGE de fecha (día grande + mes) coloreado + título + lugar + hora + menú 3 puntos.
- docs/contexto/agenda3.jpg = **el MENÚ inferior + variante de tarjetas**: barra de
  navegación inferior con FAB central (+) destacado; calendario con rangos de color
  (píldoras multi-día); "Mis citas" como GRID de tarjetas con ícono de color por tipo.

## Diseño objetivo (combinar ambas) — pantalla principal (Home/Agenda)
1. Encabezado: mes en color de acento con navegación ‹ ›; a la derecha buscar,
   notificaciones (campana con badge) y ajustes/filtros.
2. CALENDARIO mensual (arriba): día seleccionado = CÍRCULO relleno de color; hoy
   marcado; PUNTITOS de color bajo días con actividades (color por tipo); opcional:
   píldoras multi-día (agenda3). Sugerencia: el paquete **table_calendar** logra este
   look fácil, alimentado por los providers actuales (el equipo elige table_calendar
   vs custom vs SfCalendar personalizado; lo que importa es que SE VEA como la imagen).
3. "MIS CITAS" (abajo) con título + "+ Agregar": muestra las actividades del DÍA
   SELECCIONADO. Estilo LISTA con badge de fecha (agenda2) y/o GRID con ícono por
   tipo (agenda3). Estado vacío elegante.
4. BARRA INFERIOR con FAB central (+) como agenda3; sus ítems navegan a las rutas
   EXISTENTES (calendario, pendientes/backlog, notificaciones, ajustes) sin romper
   go_router ni el drawer.

## Colores/estilo
- Tema oscuro (fondos ~#1C2733/#202A38; tarjetas ~#26313F); texto blanco/gris.
- Acentos: azul #4A6CF7, púrpura FAB #5B6EF5, rosa #EC4899, teal #26C6A6, ámbar #F5A623.
- Esquinas muy redondeadas, badges/íconos de color POR TIPO (meeting/appointment/task)
  vía activity_colors.dart.
- Aplicar el mismo lenguaje visual a detalle/edición, backlog, notificaciones, login, settings.

## Datos: usar los reales (providers/repos existentes: activitiesForRange, unscheduled).
## Restricciones DURAS
- CERO backend (APIOmniTask/**, db/**). No tocar modelos/JSON (snake_case), repos en
  **/data/** (endpoints/params/paginación) ni la lógica de providers (solo consumir).
- Si se sigue con SfCalendar preservar el anti-bucle (skipLoadingOnReload + guard del
  rango); si se cambia a table_calendar/custom, garantizar que NO haya bucle.
- Mantener toda la funcionalidad y la localización en español. Contraste accesible.

## Entrega
- Plan breve al Lead (idealmente un pantallazo/preview) antes de terminar; iterar hasta
  parecerse a las imágenes. flutter analyze + test verdes. commit + push a main y
  cortar release app-v1.0.9.
