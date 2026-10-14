-- =====================================================================
-- V3 — Dữ liệu tham chiếu: gói dịch vụ và cấu hình hệ thống.
-- Giá trị có thể thay đổi sau khi triển khai qua gp_admin_upsert_plan()
-- và gp_admin_set_setting().
-- =====================================================================

INSERT INTO plan (code, name, price_vnd_per_month, max_persons, max_members, max_share_links,
                  max_view_policies, max_storage_mb, feature_export_excel, feature_import_excel,
                  feature_kinship, audit_retention_days, is_purchasable, sort_order) VALUES
    ('FREE',     'Miễn phí',   0,       300,   10,   2,   1,  200,   false, false, false, 30,   false, 1),
    ('STANDARD', 'Tiêu chuẩn', 49000,   3000,  100,  20,  10, 5120,  true,  false, true,  365,  true,  2),
    ('PREMIUM',  'Cao cấp',    149000,  20000, 1000, 200, 50, 51200, true,  true,  true,  1825, true,  3);

INSERT INTO system_setting (key, value, description) VALUES
    ('OWNER_INACTIVE_DAYS',   180, 'Số ngày không hoạt động để OWNER được coi là không còn hoạt động'),
    ('TAKEOVER_WAIT_DAYS',    30,  'Thời gian chờ trước khi chuyển giao do người kế nhiệm hoặc đơn khôi phục có hiệu lực'),
    ('TRANSFER_ACCEPT_DAYS',  7,   'Thời hạn người nhận chấp nhận chuyển giao chủ động'),
    ('RECOVERY_ENDORSE_DAYS', 14,  'Thời hạn thu thập xác nhận cho đơn khôi phục');
