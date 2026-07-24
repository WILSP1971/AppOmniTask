-- OmniTask — migración incremental: varios contactos por actividad
-- Aplica sobre la base ya creada por schema.sql en el servidor de producción.
--
-- SPEC-008 (varios contactos por actividad, WhatsApp a todos): agrega la
-- tabla puente activity_contacts como fuente de verdad de "los contactos de
-- una actividad" (RF1/RF3), migra los datos existentes de
-- activities.contact_id (RF2), y recrea fn_create_activity/fn_update_activity/
-- fn_get_activity_by_id/fn_list_activities/fn_list_unscheduled_activities/
-- fn_get_reminder_dispatch_info para leer/escribir contra la tabla puente.
--
-- Debe aplicarse DESPUES de db/06_stored_procedures_attachments_and_meeting.sql
-- (orden garantizado por el prefijo numérico): fn_create_activity/
-- fn_update_activity cambian de aridad respecto a la firma vigente ahí
-- (p_contact_id UUID -> p_contact_ids UUID[]), y Postgres identifica una
-- función por nombre + firma de parámetros — CREATE OR REPLACE por sí solo
-- crearía una sobrecarga en vez de reemplazar (R1), por eso cada función
-- cambiada de aridad lleva su DROP FUNCTION IF EXISTS con la firma vigente
-- antes del CREATE.
--
-- Uso:
--   psql -U omnitask_api -d omnitask -f 09_activity_contacts.sql

-- ============================================================
-- RF1 — Tabla puente activity_contacts
-- ============================================================

CREATE TABLE IF NOT EXISTS activity_contacts (
    activity_id UUID NOT NULL REFERENCES activities (id) ON DELETE CASCADE,
    contact_id  UUID NOT NULL REFERENCES contacts (id)   ON DELETE CASCADE,
    PRIMARY KEY (activity_id, contact_id)
);
-- La PK compuesta ya crea índice por activity_id; se agrega el índice por
-- contact_id para el borrado en cascada y para consultas por contacto.
CREATE INDEX IF NOT EXISTS idx_activity_contacts_contact_id
    ON activity_contacts (contact_id);


-- ============================================================
-- RF2 — Migración de datos existentes (idempotente)
-- ============================================================

INSERT INTO activity_contacts (activity_id, contact_id)
SELECT id, contact_id FROM activities WHERE contact_id IS NOT NULL
ON CONFLICT DO NOTHING;


-- ============================================================
-- RF3 — activities.contact_id: se conserva, queda deprecada
-- ============================================================
--
-- La columna activities.contact_id y su índice idx_activities_contact_id se
-- CONSERVAN (no se borran en esta migración) para no romper un rollback ni
-- las lecturas legadas, pero quedan DEPRECADAS como fuente de verdad: desde
-- esta migración, fn_create_activity/fn_update_activity dejan de escribir
-- activities.contact_id y la fuente de verdad de "los contactos de una
-- actividad" pasa a ser activity_contacts. Su limpieza definitiva (DROP
-- COLUMN) es una SPEC futura, fuera de alcance aquí (SPEC-008 §8).
COMMENT ON COLUMN activities.contact_id IS
    'DEPRECADO (SPEC-008): ya no se escribe. La fuente de verdad de los '
    'contactos de una actividad es activity_contacts. Se conserva solo por '
    'compatibilidad de lectura legada; el DROP de esta columna es una SPEC futura.';


-- ============================================================
-- RF4 — fn_create_activity acepta p_contact_ids UUID[]
-- ============================================================
--
-- Reemplaza p_contact_id UUID por p_contact_ids UUID[] (los demás parámetros
-- y la generación de reminders quedan igual). Tras insertar la actividad,
-- sincroniza activity_contacts con el conjunto recibido, ignorando ids
-- nulos/duplicados y filtrando por dueño (RNF2): un contact_id que no
-- pertenezca a p_user_id simplemente no se asocia (no se rechaza con error).
-- No escribe activities.contact_id (RF3).

DROP FUNCTION IF EXISTS fn_create_activity(
    UUID, UUID, activity_type, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT
);

CREATE OR REPLACE FUNCTION fn_create_activity(
    p_user_id UUID,
    p_contact_ids UUID[],
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
        user_id, type, title, description, status, starts_at, ends_at, timezone, location,
        meeting_url, meeting_provider
    ) VALUES (
        p_user_id, p_type, p_title, p_description,
        -- NULL en starts_at fuerza unscheduled sin importar lo que envíe el cliente (§6).
        CASE WHEN p_starts_at IS NULL THEN 'unscheduled' ELSE 'scheduled' END::activity_status,
        p_starts_at, p_ends_at, v_timezone, p_location,
        p_meeting_url, p_meeting_provider
    )
    RETURNING id INTO v_activity_id;

    -- Sincroniza activity_contacts con el conjunto recibido: ids nulos se
    -- descartan (unnest + WHERE), duplicados se descartan (DISTINCT), y solo
    -- se asocian los contactos que pertenecen al dueño de la actividad (RNF2)
    -- — un contact_id de otro usuario se ignora en silencio, sin error 500.
    INSERT INTO activity_contacts (activity_id, contact_id)
    SELECT v_activity_id, c.id
    FROM (SELECT DISTINCT unnest(p_contact_ids) AS contact_id) ids
    JOIN contacts c ON c.id = ids.contact_id AND c.user_id = p_user_id
    WHERE ids.contact_id IS NOT NULL
    ON CONFLICT DO NOTHING;

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


-- ============================================================
-- RF5 — fn_update_activity acepta p_contact_ids UUID[] + p_sync_contacts
-- ============================================================
--
-- Un array NULL es ambiguo ("no tocar los contactos" vs. "quitar todos"),
-- por eso se agrega el flag explícito p_sync_contacts: cuando es false, los
-- contactos no se tocan (mismo criterio "NULL = no lo toques" que ya usan
-- title/meeting_url); cuando es true, se reemplaza el conjunto completo por
-- p_contact_ids (delete + insert), que puede venir vacío para dejar la
-- actividad sin contactos.

DROP FUNCTION IF EXISTS fn_update_activity(
    UUID, UUID, TEXT, TEXT, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, BOOLEAN, activity_status, TEXT, TEXT, TEXT
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
    p_meeting_provider TEXT DEFAULT NULL,
    p_contact_ids UUID[] DEFAULT NULL,
    p_sync_contacts BOOLEAN DEFAULT FALSE
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

    -- p_sync_contacts = false -> no se toca activity_contacts (RF5). true ->
    -- se reemplaza el conjunto completo: delete + insert filtrado por dueño
    -- (RNF2), ids nulos/duplicados descartados igual que en fn_create_activity.
    IF p_sync_contacts THEN
        DELETE FROM activity_contacts WHERE activity_id = p_activity_id;

        INSERT INTO activity_contacts (activity_id, contact_id)
        SELECT p_activity_id, c.id
        FROM (SELECT DISTINCT unnest(p_contact_ids) AS contact_id) ids
        JOIN contacts c ON c.id = ids.contact_id AND c.user_id = p_user_id
        WHERE ids.contact_id IS NOT NULL
        ON CONFLICT DO NOTHING;
    END IF;

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
-- RF6 — Lecturas devuelven la lista de contactos (columna contacts JSONB)
-- ============================================================

-- fn_get_activity_by_id pasa de SELECT * (SETOF activities) a RETURNS TABLE
-- con todas las columnas de activities más "contacts JSONB": arreglo de
-- {id, full_name, phone_e164} de los contactos de la actividad (jsonb_agg
-- sobre activity_contacts JOIN contacts, '[]'::jsonb si no hay ninguno).
-- Postgres no permite CREATE OR REPLACE si cambia el tipo de retorno (aquí
-- pasa de SETOF activities a RETURNS TABLE) — requiere DROP explícito primero
-- (mismo motivo que el DROP de fn_list_unscheduled_activities más abajo).
DROP FUNCTION IF EXISTS fn_get_activity_by_id(UUID, UUID);

CREATE OR REPLACE FUNCTION fn_get_activity_by_id(p_user_id UUID, p_activity_id UUID)
RETURNS TABLE(
    id UUID, user_id UUID, contact_id UUID, type activity_type, title TEXT, description TEXT,
    status activity_status, starts_at TIMESTAMPTZ, ends_at TIMESTAMPTZ, timezone TEXT,
    location TEXT, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ,
    meeting_url TEXT, meeting_provider TEXT, contacts JSONB
) AS $$
    SELECT
        a.id, a.user_id, a.contact_id, a.type, a.title, a.description, a.status,
        a.starts_at, a.ends_at, a.timezone, a.location, a.created_at, a.updated_at,
        a.meeting_url, a.meeting_provider,
        COALESCE(
            (SELECT jsonb_agg(jsonb_build_object('id', c.id, 'full_name', c.full_name, 'phone_e164', c.phone_e164))
             FROM activity_contacts ac
             JOIN contacts c ON c.id = ac.contact_id
             WHERE ac.activity_id = a.id),
            '[]'::jsonb
        ) AS contacts
    FROM activities a
    WHERE a.id = p_activity_id AND a.user_id = p_user_id;
$$ LANGUAGE sql STABLE;

-- fn_list_unscheduled_activities: misma columna contacts JSONB, pasa a
-- RETURNS TABLE (antes era SETOF activities + SELECT *).
DROP FUNCTION IF EXISTS fn_list_unscheduled_activities(UUID);

CREATE OR REPLACE FUNCTION fn_list_unscheduled_activities(p_user_id UUID)
RETURNS TABLE(
    id UUID, user_id UUID, contact_id UUID, type activity_type, title TEXT, description TEXT,
    status activity_status, starts_at TIMESTAMPTZ, ends_at TIMESTAMPTZ, timezone TEXT,
    location TEXT, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ,
    meeting_url TEXT, meeting_provider TEXT, contacts JSONB
) AS $$
    SELECT
        a.id, a.user_id, a.contact_id, a.type, a.title, a.description, a.status,
        a.starts_at, a.ends_at, a.timezone, a.location, a.created_at, a.updated_at,
        a.meeting_url, a.meeting_provider,
        COALESCE(
            (SELECT jsonb_agg(jsonb_build_object('id', c.id, 'full_name', c.full_name, 'phone_e164', c.phone_e164))
             FROM activity_contacts ac
             JOIN contacts c ON c.id = ac.contact_id
             WHERE ac.activity_id = a.id),
            '[]'::jsonb
        ) AS contacts
    FROM activities a
    WHERE a.user_id = p_user_id AND a.starts_at IS NULL
    ORDER BY a.created_at DESC;
$$ LANGUAGE sql STABLE;

-- fn_list_activities: se agrega la columna contacts JSONB al final del
-- RETURNS TABLE (después de total_count), sin romper el orden de las
-- columnas existentes que MapActivity lee por nombre (no por posición).
DROP FUNCTION IF EXISTS fn_list_activities(
    UUID, TIMESTAMPTZ, TIMESTAMPTZ, activity_type, activity_status, INT, INT
);

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
    location TEXT, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ,
    meeting_url TEXT, meeting_provider TEXT, total_count BIGINT, contacts JSONB
) AS $$
    SELECT
        a.id, a.user_id, a.contact_id, a.type, a.title, a.description, a.status,
        a.starts_at, a.ends_at, a.timezone, a.location, a.created_at, a.updated_at,
        a.meeting_url, a.meeting_provider,
        COUNT(*) OVER() AS total_count,
        COALESCE(
            (SELECT jsonb_agg(jsonb_build_object('id', c.id, 'full_name', c.full_name, 'phone_e164', c.phone_e164))
             FROM activity_contacts ac
             JOIN contacts c ON c.id = ac.contact_id
             WHERE ac.activity_id = a.id),
            '[]'::jsonb
        ) AS contacts
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


-- ============================================================
-- RF7 — fn_get_reminder_dispatch_info pasa a SETOF (una fila por contacto)
-- ============================================================
--
-- LEFT JOIN a activity_contacts/contacts en vez de LEFT JOIN directo a
-- contacts por a.contact_id: una actividad con 2+ contactos produce una fila
-- por contacto; una actividad sin contactos produce una única fila con
-- contact_* en NULL (los datos de reminder/actividad no se pierden). El job
-- trata contact_id IS NULL como "sin destinatario de WhatsApp en esa fila".
DROP FUNCTION IF EXISTS fn_get_reminder_dispatch_info(UUID);

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
    LEFT JOIN activity_contacts ac ON ac.activity_id = a.id
    LEFT JOIN contacts c ON c.id = ac.contact_id
    WHERE r.id = p_reminder_id;
$$ LANGUAGE sql STABLE;


-- ============================================================
-- RF8 — GRANTs
-- ============================================================
--
-- Igual que en db/04..08, el rol propietario que corre el script (omnitask_api,
-- ver el "Uso" al inicio de este archivo) ya es dueño de las tablas/funciones
-- y no necesita GRANT sobre sí mismo; ninguna migración previa (04/05/07/08)
-- otorga permisos explícitos por esta razón. Se deja, de todas formas, un
-- GRANT explícito y defensivo condicionado a que el rol exista, para cubrir
-- despliegues donde la API corre con un rol de aplicación distinto del
-- dueño de los objetos (p. ej. producción con separación dueño/aplicación),
-- sin que este script falle en entornos (como CI) donde omnitask_api no existe.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'omnitask_api') THEN
        GRANT SELECT, INSERT, DELETE ON activity_contacts TO omnitask_api;
        GRANT EXECUTE ON FUNCTION fn_create_activity(
            UUID, UUID[], activity_type, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT
        ) TO omnitask_api;
        GRANT EXECUTE ON FUNCTION fn_update_activity(
            UUID, UUID, TEXT, TEXT, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, BOOLEAN, activity_status, TEXT, TEXT, TEXT, UUID[], BOOLEAN
        ) TO omnitask_api;
        GRANT EXECUTE ON FUNCTION fn_get_activity_by_id(UUID, UUID) TO omnitask_api;
        GRANT EXECUTE ON FUNCTION fn_list_activities(
            UUID, TIMESTAMPTZ, TIMESTAMPTZ, activity_type, activity_status, INT, INT
        ) TO omnitask_api;
        GRANT EXECUTE ON FUNCTION fn_list_unscheduled_activities(UUID) TO omnitask_api;
        GRANT EXECUTE ON FUNCTION fn_get_reminder_dispatch_info(UUID) TO omnitask_api;
    END IF;
END;
$$ LANGUAGE plpgsql;
