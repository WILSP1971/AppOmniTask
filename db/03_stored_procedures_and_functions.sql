-- OmniTask — funciones y procedimientos almacenados
--
-- Encapsulan en PostgreSQL las reglas de negocio ya documentadas en
-- docs/ARQUITECTURA.md (§6, §7, §8, §9, §16, §17). La API en C#
-- (APIOmniTask/, ver §22/§23) invoca esto directamente en vez de construir
-- las consultas con un ORM — el contrato de los endpoints no cambia.
--
-- Convención de códigos de error personalizados (SQLSTATE), para que la
-- capa C# traduzca sin depender del texto del mensaje:
--   OT001 = recurso no encontrado   -> 404
--   OT002 = conflicto               -> 409
--   OT003 = validación inválida     -> 422
--
-- Uso: psql -U omnitask_api -d omnitask -f 03_stored_procedures_and_functions.sql

-- ============================================================
-- AUTH (§10, §16)
-- ============================================================

-- El chequeo de unicidad y el INSERT ocurren en el mismo statement/función:
-- si dos registros con el mismo correo llegan a la vez, el UNIQUE de la
-- tabla es la última palabra — sin la carrera que tendría un check-then-insert
-- hecho desde la aplicación.
CREATE OR REPLACE FUNCTION fn_register_user(
    p_full_name TEXT,
    p_email TEXT,
    p_password_hash TEXT,
    p_phone_e164 TEXT,
    p_timezone TEXT
) RETURNS SETOF users AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM users WHERE email = p_email) THEN
        RAISE EXCEPTION 'Ya existe una cuenta con ese correo.' USING ERRCODE = 'OT002';
    END IF;

    RETURN QUERY
    INSERT INTO users (full_name, email, password_hash, phone_e164, timezone)
    VALUES (p_full_name, p_email, p_password_hash, p_phone_e164, p_timezone)
    RETURNING *;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Ya existe una cuenta con ese correo.' USING ERRCODE = 'OT002';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_get_user_by_email(p_email TEXT)
RETURNS SETOF users AS $$
    SELECT * FROM users WHERE email = p_email;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION fn_get_user_by_id(p_id UUID)
RETURNS SETOF users AS $$
    SELECT * FROM users WHERE id = p_id;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE PROCEDURE sp_create_refresh_token(
    p_jti UUID, p_user_id UUID, p_expires_at TIMESTAMPTZ
) AS $$
BEGIN
    INSERT INTO refresh_tokens (jti, user_id, expires_at) VALUES (p_jti, p_user_id, p_expires_at);
END;
$$ LANGUAGE plpgsql;

-- Revoca el jti (si seguía vigente) y devuelve el user_id en el mismo golpe
-- atómico (§10): si dos /auth/refresh llegan a la vez con el mismo token,
-- solo uno de los dos recibe una fila de vuelta — el otro ve la sesión como
-- expirada, en vez de que ambos reciban tokens nuevos válidos.
CREATE OR REPLACE FUNCTION fn_rotate_refresh_token(p_jti UUID)
RETURNS TABLE(user_id UUID) AS $$
    UPDATE refresh_tokens
    SET revoked_at = now()
    WHERE jti = p_jti AND revoked_at IS NULL AND expires_at > now()
    RETURNING refresh_tokens.user_id;
$$ LANGUAGE sql;

CREATE OR REPLACE PROCEDURE sp_revoke_refresh_token(p_jti UUID) AS $$
BEGIN
    UPDATE refresh_tokens SET revoked_at = now() WHERE jti = p_jti AND revoked_at IS NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_update_user_profile(
    p_user_id UUID,
    p_full_name TEXT,
    p_phone_e164 TEXT,
    p_timezone TEXT,
    p_notification_preferences JSONB
) RETURNS SETOF users AS $$
    UPDATE users SET
        full_name = COALESCE(p_full_name, full_name),
        phone_e164 = COALESCE(p_phone_e164, phone_e164),
        timezone = COALESCE(p_timezone, timezone),
        notification_preferences = COALESCE(p_notification_preferences, notification_preferences)
    WHERE id = p_user_id
    RETURNING *;
$$ LANGUAGE sql;


-- ============================================================
-- ACTIVITIES (§6, §9)
-- ============================================================

-- Crea la actividad y, si trae fecha, genera los reminders automáticos según
-- las preferencias del usuario — todo en una sola transacción de base de datos.
CREATE OR REPLACE FUNCTION fn_create_activity(
    p_user_id UUID,
    p_contact_id UUID,
    p_type activity_type,
    p_title TEXT,
    p_description TEXT,
    p_starts_at TIMESTAMPTZ,
    p_ends_at TIMESTAMPTZ,
    p_location TEXT
) RETURNS SETOF activities AS $$
DECLARE
    v_activity_id UUID;
    v_timezone TEXT;
    v_preferences JSONB;
    v_offset INT;
BEGIN
    IF p_ends_at IS NOT NULL AND p_starts_at IS NOT NULL AND p_ends_at <= p_starts_at THEN
        RAISE EXCEPTION 'ends_at debe ser posterior a starts_at' USING ERRCODE = 'OT003';
    END IF;

    SELECT timezone, notification_preferences INTO v_timezone, v_preferences
    FROM users WHERE id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Usuario no encontrado' USING ERRCODE = 'OT001';
    END IF;

    INSERT INTO activities (
        user_id, contact_id, type, title, description, status, starts_at, ends_at, timezone, location
    ) VALUES (
        p_user_id, p_contact_id, p_type, p_title, p_description,
        -- NULL en starts_at fuerza unscheduled sin importar lo que envíe el cliente (§6).
        CASE WHEN p_starts_at IS NULL THEN 'unscheduled' ELSE 'scheduled' END::activity_status,
        p_starts_at, p_ends_at, v_timezone, p_location
    )
    RETURNING id INTO v_activity_id;

    IF p_starts_at IS NOT NULL THEN
        FOR v_offset IN SELECT jsonb_array_elements_text(v_preferences->'reminder_offsets_minutes')::INT
        LOOP
            INSERT INTO reminders (activity_id, remind_at, channel, status)
            VALUES (
                v_activity_id,
                p_starts_at - (v_offset || ' minutes')::INTERVAL,
                (v_preferences->>'default_channel')::reminder_channel,
                'pending'
            );
        END LOOP;
    END IF;

    RETURN QUERY SELECT * FROM activities WHERE id = v_activity_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_list_activities(
    p_user_id UUID,
    p_from TIMESTAMPTZ,
    p_to TIMESTAMPTZ,
    p_type activity_type,
    p_status activity_status,
    p_page INT,
    p_limit INT
) RETURNS TABLE(
    id UUID, user_id UUID, contact_id UUID, type activity_type, title TEXT, description TEXT,
    status activity_status, starts_at TIMESTAMPTZ, ends_at TIMESTAMPTZ, timezone TEXT,
    location TEXT, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ, total_count BIGINT
) AS $$
    SELECT
        a.id, a.user_id, a.contact_id, a.type, a.title, a.description, a.status,
        a.starts_at, a.ends_at, a.timezone, a.location, a.created_at, a.updated_at,
        COUNT(*) OVER() AS total_count
    FROM activities a
    WHERE a.user_id = p_user_id
      AND (p_from IS NULL OR a.starts_at >= p_from)
      AND (p_to IS NULL OR a.starts_at <= p_to)
      AND (p_type IS NULL OR a.type = p_type)
      AND (p_status IS NULL OR a.status = p_status)
    ORDER BY a.starts_at
    OFFSET (GREATEST(p_page, 1) - 1) * p_limit
    LIMIT p_limit;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION fn_list_unscheduled_activities(p_user_id UUID)
RETURNS SETOF activities AS $$
    SELECT * FROM activities WHERE user_id = p_user_id AND starts_at IS NULL ORDER BY created_at DESC;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION fn_get_activity_by_id(p_user_id UUID, p_activity_id UUID)
RETURNS SETOF activities AS $$
    SELECT * FROM activities WHERE id = p_activity_id AND user_id = p_user_id;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION fn_list_reminders_for_activity(p_activity_id UUID)
RETURNS SETOF reminders AS $$
    SELECT * FROM reminders WHERE activity_id = p_activity_id ORDER BY remind_at;
$$ LANGUAGE sql STABLE;

-- La función más cargada de reglas de negocio del archivo. p_clear_starts_at /
-- p_clear_ends_at existen porque un parámetro NULL por sí solo es ambiguo
-- ("no lo toques" vs. "bórralo") — con el flag, el cliente puede pedir
-- explícitamente "quitar la fecha" (devolver la actividad al backlog), algo
-- que la versión anterior de este endpoint no podía expresar.
CREATE OR REPLACE FUNCTION fn_update_activity(
    p_user_id UUID,
    p_activity_id UUID,
    p_title TEXT,
    p_description TEXT,
    p_starts_at TIMESTAMPTZ,
    p_clear_starts_at BOOLEAN,
    p_ends_at TIMESTAMPTZ,
    p_clear_ends_at BOOLEAN,
    p_status activity_status,
    p_location TEXT
) RETURNS SETOF activities AS $$
DECLARE
    v_activity activities;
    v_old_starts_at TIMESTAMPTZ;
    v_new_starts_at TIMESTAMPTZ;
    v_new_ends_at TIMESTAMPTZ;
    v_new_status activity_status;
    v_reschedule BOOLEAN;
    v_closing BOOLEAN;
    v_preferences JSONB;
    v_offset INT;
BEGIN
    SELECT * INTO v_activity FROM activities WHERE id = p_activity_id AND user_id = p_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Actividad no encontrada' USING ERRCODE = 'OT001';
    END IF;

    v_old_starts_at := v_activity.starts_at;

    -- Limpiar gana sobre asignar, que gana sobre no tocar.
    v_new_starts_at := CASE
        WHEN p_clear_starts_at THEN NULL
        WHEN p_starts_at IS NOT NULL THEN p_starts_at
        ELSE v_old_starts_at
    END;
    v_new_ends_at := CASE
        WHEN p_clear_ends_at THEN NULL
        WHEN p_ends_at IS NOT NULL THEN p_ends_at
        ELSE v_activity.ends_at
    END;

    IF v_new_starts_at IS NOT NULL AND v_new_ends_at IS NOT NULL AND v_new_ends_at <= v_new_starts_at THEN
        RAISE EXCEPTION 'ends_at debe ser posterior a starts_at' USING ERRCODE = 'OT003';
    END IF;

    v_reschedule := v_new_starts_at IS DISTINCT FROM v_old_starts_at;

    -- Si el cliente no especifica status explícito, se resincroniza con la
    -- fecha: asignar fecha por primera vez -> scheduled; quitarla -> unscheduled.
    -- Cierra el hueco donde "Programar" (§14) dejaba el status desincronizado.
    v_new_status := CASE
        WHEN p_status IS NOT NULL THEN p_status
        WHEN v_reschedule THEN
            CASE WHEN v_new_starts_at IS NULL THEN 'unscheduled' ELSE 'scheduled' END::activity_status
        ELSE v_activity.status
    END;

    v_closing := v_new_status IN ('completed', 'cancelled');

    UPDATE activities SET
        title = COALESCE(p_title, title),
        description = COALESCE(p_description, description),
        location = COALESCE(p_location, location),
        starts_at = v_new_starts_at,
        ends_at = v_new_ends_at,
        status = v_new_status
    WHERE id = p_activity_id;

    IF v_reschedule OR v_closing THEN
        -- Reprogramar o cerrar cancela los reminders pendientes sin enviarlos (§6).
        UPDATE reminders SET status = 'failed' WHERE activity_id = p_activity_id AND status = 'pending';

        IF v_reschedule AND NOT v_closing AND v_new_starts_at IS NOT NULL THEN
            SELECT notification_preferences INTO v_preferences FROM users WHERE id = p_user_id;

            FOR v_offset IN SELECT jsonb_array_elements_text(v_preferences->'reminder_offsets_minutes')::INT
            LOOP
                INSERT INTO reminders (activity_id, remind_at, channel, status)
                VALUES (
                    p_activity_id,
                    v_new_starts_at - (v_offset || ' minutes')::INTERVAL,
                    (v_preferences->>'default_channel')::reminder_channel,
                    'pending'
                );
            END LOOP;
        END IF;
    END IF;

    RETURN QUERY SELECT * FROM activities WHERE id = p_activity_id;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- CONTACTS (§6)
-- ============================================================

CREATE OR REPLACE FUNCTION fn_create_contact(p_user_id UUID, p_full_name TEXT, p_phone_e164 TEXT, p_notes TEXT)
RETURNS SETOF contacts AS $$
    INSERT INTO contacts (user_id, full_name, phone_e164, notes)
    VALUES (p_user_id, p_full_name, p_phone_e164, p_notes)
    RETURNING *;
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION fn_list_contacts(p_user_id UUID, p_search TEXT)
RETURNS SETOF contacts AS $$
    SELECT * FROM contacts
    WHERE user_id = p_user_id AND (p_search IS NULL OR full_name ILIKE '%' || p_search || '%')
    ORDER BY full_name;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION fn_get_contact_by_id(p_user_id UUID, p_contact_id UUID)
RETURNS SETOF contacts AS $$
    SELECT * FROM contacts WHERE id = p_contact_id AND user_id = p_user_id;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION fn_update_contact(
    p_user_id UUID, p_contact_id UUID, p_full_name TEXT, p_phone_e164 TEXT, p_notes TEXT
) RETURNS SETOF contacts AS $$
    UPDATE contacts SET full_name = p_full_name, phone_e164 = p_phone_e164, notes = p_notes
    WHERE id = p_contact_id AND user_id = p_user_id
    RETURNING *;
$$ LANGUAGE sql;

CREATE OR REPLACE PROCEDURE sp_delete_contact(p_user_id UUID, p_contact_id UUID) AS $$
DECLARE
    v_activity_count INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM contacts WHERE id = p_contact_id AND user_id = p_user_id) THEN
        RAISE EXCEPTION 'Contacto no encontrado' USING ERRCODE = 'OT001';
    END IF;

    SELECT COUNT(*) INTO v_activity_count FROM activities WHERE contact_id = p_contact_id;
    IF v_activity_count > 0 THEN
        RAISE EXCEPTION 'Este contacto tiene actividades asociadas' USING ERRCODE = 'OT002';
    END IF;

    DELETE FROM contacts WHERE id = p_contact_id AND user_id = p_user_id;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- DEVICES (§8)
-- ============================================================

-- Upsert nativo de Postgres: dos registros simultáneos del mismo fcm_token
-- ya no pueden crear filas duplicadas, a diferencia del "select y luego
-- inserta o actualiza" que hacía antes la capa de aplicación.
CREATE OR REPLACE FUNCTION fn_upsert_device(p_user_id UUID, p_fcm_token TEXT, p_platform device_platform)
RETURNS SETOF devices AS $$
    INSERT INTO devices (user_id, fcm_token, platform, last_seen_at)
    VALUES (p_user_id, p_fcm_token, p_platform, now())
    ON CONFLICT (fcm_token) DO UPDATE SET
        user_id = EXCLUDED.user_id, platform = EXCLUDED.platform, last_seen_at = now()
    RETURNING *;
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION fn_list_devices(p_user_id UUID)
RETURNS SETOF devices AS $$
    SELECT * FROM devices WHERE user_id = p_user_id ORDER BY last_seen_at DESC;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE PROCEDURE sp_delete_device(p_user_id UUID, p_device_id UUID) AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM devices WHERE id = p_device_id AND user_id = p_user_id) THEN
        RAISE EXCEPTION 'Dispositivo no encontrado' USING ERRCODE = 'OT001';
    END IF;
    DELETE FROM devices WHERE id = p_device_id AND user_id = p_user_id;
END;
$$ LANGUAGE plpgsql;

-- Sin scoping por usuario: la usa internamente el job de recordatorios
-- cuando Firebase reporta un token vencido (§8), el llamador ya resolvió
-- el dispositivo a través de la actividad/usuario.
CREATE OR REPLACE PROCEDURE sp_delete_device_by_id(p_device_id UUID) AS $$
BEGIN
    DELETE FROM devices WHERE id = p_device_id;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- NOTIFICATIONS (§17)
-- ============================================================

CREATE OR REPLACE FUNCTION fn_list_notifications(p_user_id UUID, p_unread_only BOOLEAN, p_page INT, p_limit INT)
RETURNS TABLE(
    id UUID, channel notification_channel, status notification_status, summary TEXT,
    activity_id UUID, created_at TIMESTAMPTZ, acknowledged_at TIMESTAMPTZ, total_count BIGINT
) AS $$
    SELECT
        n.id, n.channel, n.status, n.summary, r.activity_id, n.created_at, n.acknowledged_at,
        COUNT(*) OVER() AS total_count
    FROM notification_log n
    LEFT JOIN reminders r ON r.id = n.reminder_id
    WHERE n.user_id = p_user_id AND (NOT p_unread_only OR n.acknowledged_at IS NULL)
    ORDER BY n.created_at DESC
    OFFSET (GREATEST(p_page, 1) - 1) * p_limit
    LIMIT p_limit;
$$ LANGUAGE sql STABLE;

-- Endpoint propio y liviano (§17): un escalar, no toda la lista, para
-- alimentar el badge de la campana sin cargar el listado completo.
CREATE OR REPLACE FUNCTION fn_unread_notification_count(p_user_id UUID)
RETURNS BIGINT AS $$
    SELECT COUNT(*) FROM notification_log WHERE user_id = p_user_id AND acknowledged_at IS NULL;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE PROCEDURE sp_acknowledge_notification(p_user_id UUID, p_notification_id UUID) AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM notification_log WHERE id = p_notification_id AND user_id = p_user_id) THEN
        RAISE EXCEPTION 'Notificación no encontrada' USING ERRCODE = 'OT001';
    END IF;
    UPDATE notification_log SET acknowledged_at = now()
    WHERE id = p_notification_id AND user_id = p_user_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE sp_acknowledge_all_notifications(p_user_id UUID) AS $$
BEGIN
    UPDATE notification_log SET acknowledged_at = now()
    WHERE user_id = p_user_id AND acknowledged_at IS NULL;
END;
$$ LANGUAGE plpgsql;

-- Llamado desde el webhook de WhatsApp (§7) para reflejar sent/delivered/read/failed.
CREATE OR REPLACE PROCEDURE sp_update_notification_delivery_status(
    p_provider_message_id TEXT, p_status notification_status
) AS $$
BEGIN
    UPDATE notification_log SET status = p_status WHERE provider_message_id = p_provider_message_id;
END;
$$ LANGUAGE plpgsql;

-- Usado por el job de recordatorios (send_reminder) al momento de enviar,
-- para dejar el texto capturado en el momento (§17) — nunca reconstruido
-- después a partir de una actividad que puede haber cambiado.
CREATE OR REPLACE FUNCTION fn_log_notification(
    p_reminder_id UUID,
    p_user_id UUID,
    p_channel notification_channel,
    p_status notification_status,
    p_summary TEXT,
    p_provider_message_id TEXT
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO notification_log (reminder_id, user_id, channel, status, summary, provider_message_id)
    VALUES (p_reminder_id, p_user_id, p_channel, p_status, p_summary, p_provider_message_id)
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- REMINDERS Y JOBS DE FONDO (§8, Hangfire)
-- ============================================================

-- SELECT ... FOR UPDATE SKIP LOCKED + marcar processing en un solo statement
-- atómico — evita que dos ejecuciones solapadas de ReminderDispatchJob envíen
-- el mismo recordatorio dos veces.
CREATE OR REPLACE FUNCTION fn_claim_due_reminders(p_limit INT)
RETURNS SETOF reminders AS $$
    WITH due AS (
        SELECT id FROM reminders
        WHERE remind_at <= now() AND status = 'pending'
        ORDER BY remind_at
        LIMIT p_limit
        FOR UPDATE SKIP LOCKED
    )
    UPDATE reminders SET status = 'processing'
    WHERE id IN (SELECT id FROM due)
    RETURNING reminders.*;
$$ LANGUAGE sql;

-- Todo lo que send_reminder necesita para decidir y ejecutar el envío, en una sola fila.
CREATE OR REPLACE FUNCTION fn_get_reminder_dispatch_info(p_reminder_id UUID)
RETURNS TABLE(
    reminder_id UUID,
    channel reminder_channel,
    activity_id UUID,
    activity_title TEXT,
    activity_starts_at TIMESTAMPTZ,
    user_id UUID,
    contact_id UUID,
    contact_full_name TEXT,
    contact_phone_e164 TEXT
) AS $$
    SELECT r.id, r.channel, a.id, a.title, a.starts_at, a.user_id, c.id, c.full_name, c.phone_e164
    FROM reminders r
    JOIN activities a ON a.id = r.activity_id
    LEFT JOIN contacts c ON c.id = a.contact_id
    WHERE r.id = p_reminder_id;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE PROCEDURE sp_mark_reminder_sent(p_reminder_id UUID) AS $$
BEGIN
    UPDATE reminders SET status = 'sent', sent_at = now() WHERE id = p_reminder_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE sp_mark_reminder_failed(p_reminder_id UUID) AS $$
BEGIN
    UPDATE reminders SET status = 'failed' WHERE id = p_reminder_id;
END;
$$ LANGUAGE plpgsql;

-- Resumen diario de actividades sin fecha, agrupado por usuario (Fase 5, §4).
CREATE OR REPLACE FUNCTION fn_unscheduled_digest_counts()
RETURNS TABLE(user_id UUID, activity_count BIGINT) AS $$
    SELECT a.user_id, COUNT(*) AS activity_count
    FROM activities a
    WHERE a.starts_at IS NULL AND a.status = 'unscheduled'
    GROUP BY a.user_id;
$$ LANGUAGE sql STABLE;
