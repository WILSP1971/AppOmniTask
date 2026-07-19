-- OmniTask — funciones y procedimientos: adjuntos de actividad y link de reunión
--
-- Complementa db/03_stored_procedures_and_functions.sql con las funciones que
-- necesita la capa C# para SPEC-002 (adjuntos, db/04_activity_attachments.sql)
-- y SPEC-003 (link de reunión, db/05_activity_meeting.sql). Mismo estilo y
-- convención de códigos de error (SQLSTATE) que 03_*.sql:
--   OT001 = recurso no encontrado   -> 404
--   OT002 = conflicto               -> 409
--   OT003 = validación inválida     -> 422
--
-- Uso: psql -U omnitask_api -d omnitask -f 06_stored_procedures_attachments_and_meeting.sql

-- ============================================================
-- ACTIVITY ATTACHMENTS (SPEC-002, §6)
-- ============================================================

-- Verifica dueño y crea el registro de metadatos en un solo golpe: si la
-- actividad no existe o es de otro usuario, nunca se llega a insertar el
-- adjunto (evita una carrera entre "verificar" e "insertar" hecha en dos
-- pasos desde la aplicación).
CREATE OR REPLACE FUNCTION fn_create_activity_attachment(
    p_user_id UUID,
    p_activity_id UUID,
    p_file_name TEXT,
    p_content_type TEXT,
    p_size_bytes BIGINT,
    p_storage_path TEXT
) RETURNS SETOF activity_attachments AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM activities WHERE id = p_activity_id AND user_id = p_user_id) THEN
        RAISE EXCEPTION 'Actividad no encontrada' USING ERRCODE = 'OT001';
    END IF;

    RETURN QUERY
    INSERT INTO activity_attachments (activity_id, file_name, content_type, size_bytes, storage_path)
    VALUES (p_activity_id, p_file_name, p_content_type, p_size_bytes, p_storage_path)
    RETURNING *;
END;
$$ LANGUAGE plpgsql;

-- Lista de metadatos (sin bytes), solo si la actividad pertenece al usuario.
CREATE OR REPLACE FUNCTION fn_list_activity_attachments(p_user_id UUID, p_activity_id UUID)
RETURNS SETOF activity_attachments AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM activities WHERE id = p_activity_id AND user_id = p_user_id) THEN
        RAISE EXCEPTION 'Actividad no encontrada' USING ERRCODE = 'OT001';
    END IF;

    RETURN QUERY
    SELECT * FROM activity_attachments
    WHERE activity_id = p_activity_id
    ORDER BY uploaded_at;
END;
$$ LANGUAGE plpgsql STABLE;

-- Usada tanto para descargar (RF3) como para borrar (RF4): resuelve el
-- adjunto solo si la actividad dueña es del usuario autenticado; en
-- cualquier otro caso (adjunto de otra actividad/usuario, o inexistente) no
-- devuelve fila, para que la capa C# responda 404 sin filtrar existencia.
CREATE OR REPLACE FUNCTION fn_get_activity_attachment(
    p_user_id UUID, p_activity_id UUID, p_attachment_id UUID
) RETURNS SETOF activity_attachments AS $$
    SELECT aa.*
    FROM activity_attachments aa
    JOIN activities a ON a.id = aa.activity_id
    WHERE aa.id = p_attachment_id
      AND aa.activity_id = p_activity_id
      AND a.user_id = p_user_id;
$$ LANGUAGE sql STABLE;

-- Borra el registro de metadatos y devuelve storage_path para que la capa
-- C# borre el archivo físico (best-effort, fuera de la transacción de BD).
-- Si no hay fila que coincida (dueño distinto o no existe), OT001.
CREATE OR REPLACE FUNCTION fn_delete_activity_attachment(
    p_user_id UUID, p_activity_id UUID, p_attachment_id UUID
) RETURNS TABLE(storage_path TEXT) AS $$
DECLARE
    v_storage_path TEXT;
BEGIN
    SELECT aa.storage_path INTO v_storage_path
    FROM activity_attachments aa
    JOIN activities a ON a.id = aa.activity_id
    WHERE aa.id = p_attachment_id AND aa.activity_id = p_activity_id AND a.user_id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Adjunto no encontrado' USING ERRCODE = 'OT001';
    END IF;

    DELETE FROM activity_attachments WHERE id = p_attachment_id;

    RETURN QUERY SELECT v_storage_path;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- MEETING LINK (SPEC-003, §6)
-- ============================================================
--
-- No se agregan funciones nuevas para crear/editar: SPEC-003 reusa
-- fn_create_activity / fn_update_activity ya existentes en
-- db/03_stored_procedures_and_functions.sql, extendidas con los parámetros
-- p_meeting_url / p_meeting_provider. Postgres identifica una función por
-- nombre + firma de parámetros: como aquí cambia la cantidad de parámetros,
-- CREATE OR REPLACE por sí solo crearía una SOBRECARGA nueva en vez de
-- reemplazar la de 03_*.sql (ambigüedad al llamar con 8 argumentos). Por
-- eso se hace DROP explícito de la firma vieja antes de crear la nueva. Este
-- script debe aplicarse DESPUÉS de 03_*.sql (orden ya garantizado por el
-- prefijo 06_).

DROP FUNCTION IF EXISTS fn_create_activity(
    UUID, UUID, activity_type, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TEXT
);

CREATE OR REPLACE FUNCTION fn_create_activity(
    p_user_id UUID,
    p_contact_id UUID,
    p_type activity_type,
    p_title TEXT,
    p_description TEXT,
    p_starts_at TIMESTAMPTZ,
    p_ends_at TIMESTAMPTZ,
    p_location TEXT,
    p_meeting_url TEXT DEFAULT NULL,
    p_meeting_provider TEXT DEFAULT NULL
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
        user_id, contact_id, type, title, description, status, starts_at, ends_at, timezone, location,
        meeting_url, meeting_provider
    ) VALUES (
        p_user_id, p_contact_id, p_type, p_title, p_description,
        -- NULL en starts_at fuerza unscheduled sin importar lo que envíe el cliente (§6).
        CASE WHEN p_starts_at IS NULL THEN 'unscheduled' ELSE 'scheduled' END::activity_status,
        p_starts_at, p_ends_at, v_timezone, p_location,
        p_meeting_url, p_meeting_provider
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

-- Misma función fn_update_activity, con p_meeting_url / p_meeting_provider
-- agregados al final (COALESCE, mismo criterio que title/description/location:
-- NULL = "no lo toques"). No hay flag de "limpiar" dedicado para el link
-- porque no fue pedido por la SPEC (RF1 solo exige nulos permitidos en
-- creación); si se necesita "quitar el link" explícitamente, es una SPEC aparte.
DROP FUNCTION IF EXISTS fn_update_activity(
    UUID, UUID, TEXT, TEXT, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, BOOLEAN, activity_status, TEXT
);

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
    p_location TEXT,
    p_meeting_url TEXT DEFAULT NULL,
    p_meeting_provider TEXT DEFAULT NULL
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
        status = v_new_status,
        meeting_url = COALESCE(p_meeting_url, meeting_url),
        meeting_provider = COALESCE(p_meeting_provider, meeting_provider)
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
