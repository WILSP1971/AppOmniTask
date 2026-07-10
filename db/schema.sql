-- OmniTask — esquema inicial de PostgreSQL
-- Ver docs/ARQUITECTURA.md §3 (diseño) y §18 (despliegue en Windows/IIS)
--
-- Uso:
--   psql -U omnitask_api -d omnitask -f schema.sql
--
-- Tras ejecutarlo, marca el esquema como la base de Alembic (§11/§13)
-- con `alembic stamp head` usando una migración inicial equivalente a este
-- DDL, para que las migraciones futuras se apliquen encima sin intentar
-- recrear tablas que ya existen.

-- Extensión para generar UUIDs
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Enums
CREATE TYPE user_role AS ENUM ('admin', 'professional', 'assistant');
CREATE TYPE device_platform AS ENUM ('ios', 'android');
CREATE TYPE activity_type AS ENUM ('meeting', 'appointment', 'task', 'activity');
CREATE TYPE activity_status AS ENUM ('unscheduled', 'scheduled', 'completed', 'cancelled');
CREATE TYPE reminder_channel AS ENUM ('push', 'whatsapp', 'both');
CREATE TYPE reminder_status AS ENUM ('pending', 'processing', 'sent', 'failed');
CREATE TYPE notification_channel AS ENUM ('push', 'whatsapp');
CREATE TYPE notification_status AS ENUM ('queued', 'sent', 'delivered', 'read', 'failed');
CREATE TYPE template_category AS ENUM ('utility', 'marketing', 'authentication');
CREATE TYPE template_approval_status AS ENUM ('pending', 'approved', 'rejected');

-- users
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    phone_e164 TEXT NOT NULL,
    timezone TEXT NOT NULL,
    role user_role NOT NULL DEFAULT 'professional',
    notification_preferences JSONB NOT NULL DEFAULT
        '{"default_channel": "both", "reminder_offsets_minutes": [1440, 60]}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- devices
CREATE TABLE devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    fcm_token TEXT NOT NULL UNIQUE,
    platform device_platform NOT NULL,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_devices_user_id ON devices (user_id);

-- contacts
CREATE TABLE contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    phone_e164 TEXT NOT NULL,
    notes TEXT
);
CREATE INDEX idx_contacts_user_id ON contacts (user_id);

-- whatsapp_templates
CREATE TABLE whatsapp_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    meta_template_name TEXT NOT NULL,
    language_code TEXT NOT NULL,
    category template_category NOT NULL,
    approval_status template_approval_status NOT NULL DEFAULT 'pending',
    variables_schema JSONB NOT NULL DEFAULT '{}'
);

-- activities
CREATE TABLE activities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    contact_id UUID REFERENCES contacts (id) ON DELETE SET NULL,
    type activity_type NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    status activity_status NOT NULL DEFAULT 'scheduled',
    starts_at TIMESTAMPTZ,
    ends_at TIMESTAMPTZ,
    timezone TEXT NOT NULL,
    location TEXT,
    nudge_frequency_days INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_ends_after_starts
        CHECK (ends_at IS NULL OR starts_at IS NULL OR ends_at > starts_at)
);
CREATE INDEX idx_activities_user_id ON activities (user_id);
CREATE INDEX idx_activities_contact_id ON activities (contact_id);
CREATE INDEX idx_activities_starts_at ON activities (starts_at);
-- La bandeja de "pendientes por programar" (§4/§12) filtra por esto constantemente
CREATE INDEX idx_activities_unscheduled ON activities (user_id) WHERE starts_at IS NULL;

-- reminders
CREATE TABLE reminders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    activity_id UUID NOT NULL REFERENCES activities (id) ON DELETE CASCADE,
    remind_at TIMESTAMPTZ NOT NULL,
    channel reminder_channel NOT NULL,
    template_id UUID REFERENCES whatsapp_templates (id),
    status reminder_status NOT NULL DEFAULT 'pending',
    sent_at TIMESTAMPTZ
);
CREATE INDEX idx_reminders_activity_id ON reminders (activity_id);
-- El índice que hace barato el SELECT ... FOR UPDATE SKIP LOCKED de la §8
CREATE INDEX idx_reminders_due ON reminders (remind_at) WHERE status = 'pending';

-- notification_log
CREATE TABLE notification_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reminder_id UUID REFERENCES reminders (id) ON DELETE SET NULL,
    user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    channel notification_channel NOT NULL,
    provider_message_id TEXT,
    status notification_status NOT NULL DEFAULT 'queued',
    summary TEXT NOT NULL,
    error_detail TEXT,
    acknowledged_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_notification_log_user_id ON notification_log (user_id, created_at DESC);
CREATE INDEX idx_notification_log_provider_message_id ON notification_log (provider_message_id);
-- Alimenta /notifications/unread-count (§17) sin escanear toda la tabla
CREATE INDEX idx_notification_log_unread ON notification_log (user_id) WHERE acknowledged_at IS NULL;

-- updated_at al día aunque algo distinto a la API toque la fila directamente
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_activities_updated_at BEFORE UPDATE ON activities
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
