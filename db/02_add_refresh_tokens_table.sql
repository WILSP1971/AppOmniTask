-- OmniTask — migración incremental: tabla refresh_tokens
-- Aplica sobre la base ya creada por schema.sql en el servidor de producción.
--
-- El backend C#/.NET guarda los refresh tokens aquí en vez de Redis (§10):
-- un motor de datos menos que operar en el servidor Windows/IIS.
--
-- Uso:
--   psql -U omnitask_api -d omnitask -f 02_add_refresh_tokens_table.sql

CREATE TABLE IF NOT EXISTS refresh_tokens (
    jti UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_id ON refresh_tokens (user_id);
