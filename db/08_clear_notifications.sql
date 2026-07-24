-- OmniTask — migración incremental (aditiva): limpiar historial de notificaciones
-- Aplica sobre la base ya creada por schema.sql en el servidor de producción.
--
-- SPEC-007 (Limpiar historial de notificaciones, RF2): borrado total e
-- irreversible del historial del usuario autenticado. reminder_id tiene
-- ON DELETE SET NULL hacia notification_log, así que borrar aquí no toca
-- reminders ni activities.
--
-- Uso:
--   psql -U omnitask_api -d omnitask -f 08_clear_notifications.sql

CREATE OR REPLACE PROCEDURE sp_clear_notifications(p_user_id UUID) AS $$
BEGIN
    DELETE FROM notification_log WHERE user_id = p_user_id;
END;
$$ LANGUAGE plpgsql;
