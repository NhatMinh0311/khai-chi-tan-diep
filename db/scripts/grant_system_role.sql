-- Cấp hoặc thu hồi vai trò hệ thống cho một tài khoản. Chạy bằng gp_owner; không có API tương ứng.
--   docker compose exec -T db psql -U gp_owner -d giapha \
--       -v email=admin@example.vn -v role=SYSTEM_ADMIN < db/scripts/grant_system_role.sql
-- Thu hồi: -v role=NONE
\set ON_ERROR_STOP 1
BEGIN;
UPDATE app_user
SET system_role = NULLIF(:'role', 'NONE')
WHERE email = lower(:'email');
INSERT INTO admin_audit_log (actor_user_id, action, target_type, target_id, detail)
SELECT NULL, 'SYSTEM_ROLE_SET', 'user', id::text, jsonb_build_object('role', :'role', 'via', 'db-script')
FROM app_user WHERE email = lower(:'email');
SELECT id, email, system_role FROM app_user WHERE email = lower(:'email');
COMMIT;
