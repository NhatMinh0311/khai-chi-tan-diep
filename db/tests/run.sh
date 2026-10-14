#!/bin/sh
# Chạy test RLS trên CSDL tạm giapha_test (không đụng dữ liệu dev).
# Yêu cầu: docker compose up -d db
set -eu
cd "$(dirname "$0")/../.."
DB=giapha_test

psql_as() { user=$1; db=$2; shift 2; docker compose exec -T db psql -v ON_ERROR_STOP=1 -q -U "$user" -d "$db" "$@"; }

psql_as postgres postgres -c "DROP DATABASE IF EXISTS $DB" -c "CREATE DATABASE $DB OWNER gp_owner"
psql_as postgres "$DB" \
    -c "REVOKE ALL ON DATABASE $DB FROM PUBLIC" \
    -c "GRANT CONNECT ON DATABASE $DB TO gp_owner, gp_app" \
    -c "ALTER SCHEMA public OWNER TO gp_owner" \
    -c "REVOKE ALL ON SCHEMA public FROM PUBLIC" \
    -c "GRANT USAGE ON SCHEMA public TO gp_app"

docker compose run --rm -e FLYWAY_URL="jdbc:postgresql://db:5432/$DB" migrate migrate > /dev/null
psql_as gp_owner "$DB" < db/tests/fixtures.sql
psql_as gp_app "$DB" < db/tests/rls_test.sql
psql_as postgres postgres -c "DROP DATABASE $DB"
