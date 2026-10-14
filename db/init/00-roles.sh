#!/bin/sh
# Chạy MỘT LẦN khi khởi tạo volume Postgres (docker-entrypoint-initdb.d).
#   gp_owner: chủ CSDL và các bảng; chỉ Flyway dùng để chạy migration.
#   gp_app:   tài khoản của backend; không phải chủ bảng, không BYPASSRLS.
set -eu

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
     -v owner_pw="$GP_OWNER_PASSWORD" -v app_pw="$GP_APP_PASSWORD" <<'EOSQL'
CREATE ROLE gp_owner LOGIN PASSWORD :'owner_pw';
CREATE ROLE gp_app   LOGIN PASSWORD :'app_pw' NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
CREATE DATABASE giapha OWNER gp_owner;
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname giapha <<'EOSQL'
REVOKE ALL ON DATABASE giapha FROM PUBLIC;
GRANT CONNECT ON DATABASE giapha TO gp_owner, gp_app;
ALTER SCHEMA public OWNER TO gp_owner;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO gp_app;
EOSQL
