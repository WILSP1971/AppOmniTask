-- OmniTask — migración incremental (aditiva): link de reunión en activities
-- Aplica sobre la base ya creada por schema.sql en el servidor de producción.
--
-- SPEC-003 (Link de reunión Meet/Teams, §6): columnas nullables, no rompen
-- actividades existentes. meeting_provider se valida en la aplicación
-- ('meet' | 'teams' | 'other'), no se crea un ENUM nuevo para mantener la
-- migración aditiva y simple.
--
-- Uso:
--   psql -U omnitask_api -d omnitask -f 05_activity_meeting.sql

ALTER TABLE activities ADD COLUMN IF NOT EXISTS meeting_url TEXT;
ALTER TABLE activities ADD COLUMN IF NOT EXISTS meeting_provider TEXT;
