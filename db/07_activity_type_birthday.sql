-- OmniTask — migración incremental (aditiva): tipo de actividad "cumpleaños"
-- Aplica sobre la base ya creada por schema.sql en el servidor de producción.
--
-- SPEC-006 (Tipo de actividad Cumpleaños, RF1): Postgres no permite usar un
-- valor de enum recién agregado dentro de la misma transacción en la que se
-- agrega — este script va SOLO, sin combinarse con otros cambios, y sin
-- envolverse en un BEGIN/COMMIT explícito (cada sentencia de psql corre en su
-- propia transacción implícita salvo que se indique lo contrario).
--
-- Uso:
--   psql -U omnitask_api -d omnitask -f 07_activity_type_birthday.sql

ALTER TYPE activity_type ADD VALUE IF NOT EXISTS 'birthday';
