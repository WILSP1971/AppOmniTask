-- OmniTask — migración incremental: tabla activity_attachments
-- Aplica sobre la base ya creada por schema.sql en el servidor de producción.
--
-- SPEC-002 (Adjuntos en actividades, §6): la BD guarda solo metadatos y la
-- ruta relativa dentro de Attachments:RootPath; el binario vive en el
-- filesystem del servidor. storage_path usa un nombre físico GUID, nunca el
-- nombre original del cliente (defensa contra path traversal / colisiones).
--
-- Uso:
--   psql -U omnitask_api -d omnitask -f 04_activity_attachments.sql

CREATE TABLE IF NOT EXISTS activity_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    activity_id UUID NOT NULL REFERENCES activities (id) ON DELETE CASCADE,
    file_name TEXT NOT NULL,          -- nombre original mostrado al usuario
    content_type TEXT NOT NULL,       -- MIME validado en el servidor
    size_bytes BIGINT NOT NULL,
    storage_path TEXT NOT NULL,       -- ruta relativa dentro de RootPath (GUID)
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_activity_attachments_activity_id ON activity_attachments (activity_id);
