-- Ejecutar como superusuario (psql -U postgres) antes de schema.sql.
-- Cambia la contraseña por una real antes de correrlo.
-- Ver docs/ARQUITECTURA.md §18 para pg_hba.conf y postgresql.conf.

CREATE ROLE omnitask_api WITH LOGIN PASSWORD 'una-contraseña-fuerte-aquí';
CREATE DATABASE omnitask OWNER omnitask_api;
