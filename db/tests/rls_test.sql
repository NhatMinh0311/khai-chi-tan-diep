-- =====================================================================
-- Kiểm thử RLS, ràng buộc toàn vẹn và hàm nghiệp vụ. Chạy bằng gp_app
-- (đúng quyền của backend). Mỗi test in "PASS Txx"; test hỏng dừng ngay.
-- Kịch bản đặt ngữ cảnh ở mức session; backend đặt ngữ cảnh theo
-- transaction bằng set_config(..., true).
-- =====================================================================
\set ON_ERROR_STOP 1
\o /dev/null

\set C1 'c1000000-0000-0000-0000-000000000001'
\set C2 'c2000000-0000-0000-0000-000000000002'
\set C3 'c3000000-0000-0000-0000-000000000003'
\set C4 'c4000000-0000-0000-0000-000000000004'
\set OWNER1 'a0000000-0000-0000-0000-000000000001'
\set EDITOR1 'a0000000-0000-0000-0000-000000000002'
\set MEMBER1 'a0000000-0000-0000-0000-000000000003'
\set OWNER2 'a0000000-0000-0000-0000-000000000004'
\set NEWCOMER 'a0000000-0000-0000-0000-000000000005'
\set LOCKED 'a0000000-0000-0000-0000-000000000006'
\set MEMBER2 'a0000000-0000-0000-0000-000000000007'
\set MEMBER3 'a0000000-0000-0000-0000-000000000008'
\set ADMIN 'a0000000-0000-0000-0000-000000000009'
\set SUPPORT 'a0000000-0000-0000-0000-000000000010'
\set UNVERIFIED 'a0000000-0000-0000-0000-000000000011'
\set SUCCESSOR3 'a0000000-0000-0000-0000-000000000013'
\set EDITOR4A 'a0000000-0000-0000-0000-000000000015'
\set EDITOR4B 'a0000000-0000-0000-0000-000000000016'
\set LINK_OK '50000000-0000-0000-0000-000000000001'
\set LINK_EXPIRED '50000000-0000-0000-0000-000000000002'
\set LINK_PERPETUAL '50000000-0000-0000-0000-000000000003'

-- ---------------------------------------------------------------- T01
SELECT set_config('app.user_id', '', false), set_config('app.clan_id', '', false), set_config('app.share_link_id', '', false);
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM person;          ASSERT n = 0, 'T01 person without context';
    SELECT count(*) INTO n FROM clan;            ASSERT n = 0, 'T01 clan without context';
    SELECT count(*) INTO n FROM family_union;    ASSERT n = 0, 'T01 union without context';
    SELECT count(*) INTO n FROM clan_membership; ASSERT n = 0, 'T01 membership without context';
    SELECT count(*) INTO n FROM view_policy;     ASSERT n = 0, 'T01 policy without context';
    RAISE NOTICE 'PASS T01 thiếu ngữ cảnh: không trả về dữ liệu (fail-closed)';
END $$;

-- ---------------------------------------------------------------- T02
SELECT set_config('app.user_id', :'OWNER1', false), set_config('app.clan_id', :'C1', false);
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM person;   -- cố ý không lọc clan_id
    ASSERT n = 10, format('T02 owner1 should see 10 persons of clan 1, saw %s', n);
    SELECT count(*) INTO n FROM person WHERE clan_id = 'c2000000-0000-0000-0000-000000000002';
    ASSERT n = 0, 'T02 owner1 must not see clan 2';
    SELECT count(*) INTO n FROM clan; ASSERT n = 1, 'T02 owner1 sees only own clan';
    RAISE NOTICE 'PASS T02 OWNER thấy toàn bộ dòng họ mình, không thấy dòng họ khác dù truy vấn thiếu điều kiện lọc';
END $$;

-- ---------------------------------------------------------------- T03
SELECT set_config('app.user_id', :'OWNER2', false), set_config('app.clan_id', :'C1', false);
DO $$
DECLARE n int;
BEGIN
    ASSERT app_principal_role() IS NULL, 'T03 owner2 has no role in clan 1';
    SELECT count(*) INTO n FROM person; ASSERT n = 0, 'T03 non-member sees nothing';
    SELECT count(*) INTO n FROM audit_log; ASSERT n = 0, 'T03 non-member sees no audit';
    BEGIN
        INSERT INTO person (clan_id, full_name) VALUES ('c1000000-0000-0000-0000-000000000001', 'Kẻ lạ');
        RAISE EXCEPTION 'T03 non-member insert should fail';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    RAISE NOTICE 'PASS T03 đặt clan_id của dòng họ khác vẫn bị chặn';
END $$;

-- ---------------------------------------------------------------- T04
SELECT set_config('app.user_id', :'EDITOR1', false), set_config('app.clan_id', :'C1', false);
DO $$
DECLARE ids text; n int;
BEGIN
    SELECT string_agg(right(id::text, 2), ',' ORDER BY id) INTO ids FROM person;
    ASSERT ids = '21,24,31,32', format('T04 editor1 scope should be Bình,Hoa,Đức,Em; got %s', ids);
    UPDATE person SET occupation = 'Giáo viên' WHERE id = '10000000-0000-0000-0000-000000000031';
    GET DIAGNOSTICS n = ROW_COUNT; ASSERT n = 1, 'T04 editor updates in-scope person';
    UPDATE person SET occupation = 'x' WHERE id = '10000000-0000-0000-0000-000000000011';
    GET DIAGNOSTICS n = ROW_COUNT; ASSERT n = 0, 'T04 editor cannot update out-of-scope person';
    SELECT count(*) INTO n FROM family_union; ASSERT n = 1, format('T04 editor sees 1 union, got %s', n);
    RAISE NOTICE 'PASS T04 EDITOR chỉ thấy và sửa người trong nhánh được giao';
END $$;

-- ---------------------------------------------------------------- T05
DO $$
DECLARE n int;
BEGIN
    BEGIN
        INSERT INTO invitation (clan_id, email, role, token_hash, expires_at, created_by)
        VALUES ('c1000000-0000-0000-0000-000000000001', 'x@test.vn', 'MEMBER',
                sha256(convert_to('t05a', 'UTF8')), now() + interval '1 day', 'a0000000-0000-0000-0000-000000000002');
        RAISE EXCEPTION 'T05 editor must not invite anyone';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    SELECT count(*) INTO n FROM invitation;      ASSERT n = 0, 'T05 editor sees no invitations';
    SELECT count(*) INTO n FROM clan_membership; ASSERT n = 1, 'T05 editor sees only own membership';
    SELECT count(*) INTO n FROM share_link;      ASSERT n = 0, 'T05 editor sees no share links';
    SELECT count(*) INTO n FROM view_policy;     ASSERT n = 0, 'T05 editor sees no view policies';
    UPDATE clan_membership SET role = 'OWNER' WHERE user_id = 'a0000000-0000-0000-0000-000000000002';
    GET DIAGNOSTICS n = ROW_COUNT; ASSERT n = 0, 'T05 editor must not change memberships';
    RAISE NOTICE 'PASS T05 EDITOR chỉ ghi sử: không mời, không xem danh sách thành viên, lời mời, link, chế độ xem';
END $$;

-- ---------------------------------------------------------------- T06
SELECT set_config('app.user_id', :'MEMBER1', false), set_config('app.clan_id', :'C1', false);
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM person; ASSERT n = 10, 'T06 member with default CLAN policy sees whole clan';
    BEGIN
        INSERT INTO person (clan_id, full_name) VALUES ('c1000000-0000-0000-0000-000000000001', 'x');
        RAISE EXCEPTION 'T06 member insert should fail';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    UPDATE person SET occupation = 'x';
    GET DIAGNOSTICS n = ROW_COUNT; ASSERT n = 0, 'T06 member cannot update';
    DELETE FROM person;
    GET DIAGNOSTICS n = ROW_COUNT; ASSERT n = 0, 'T06 member cannot delete';
    SELECT count(*) INTO n FROM clan_membership; ASSERT n = 1, 'T06 member sees only own membership';
    SELECT count(*) INTO n FROM share_link;      ASSERT n = 0, 'T06 member sees no share links';
    SELECT count(*) INTO n FROM view_policy;     ASSERT n = 0, 'T06 member sees no view policies';
    RAISE NOTICE 'PASS T06 MEMBER chỉ đọc';
END $$;

-- ---------------------------------------------------------------- T07
SELECT set_config('app.user_id', :'LOCKED', false), set_config('app.clan_id', :'C1', false);
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM person; ASSERT n = 0, 'T07 locked account sees nothing';
    RAISE NOTICE 'PASS T07 tài khoản bị khóa mất quyền tức thời';
END $$;

-- ---------------------------------------------------------------- T08
SELECT set_config('app.user_id', '', false), set_config('app.clan_id', :'C1', false),
       set_config('app.share_link_id', :'LINK_OK', false);
DO $$
DECLARE ids text; n int;
BEGIN
    ASSERT app_principal_role() = 'GUEST', 'T08 guest role';
    SELECT string_agg(right(id::text, 2), ',' ORDER BY id) INTO ids FROM person;
    ASSERT ids = '11,21,22,23', format('T08 guest scope should be An,Bình,Chi,Dũng; got %s', ids);
    ASSERT app_visible_field_groups() = ARRAY['BASIC'], 'T08 guest field groups';
    SELECT count(*) INTO n FROM clan;            ASSERT n = 1, 'T08 guest sees the clan';
    SELECT count(*) INTO n FROM clan_membership; ASSERT n = 0, 'T08 guest sees no members';
    SELECT count(*) INTO n FROM share_link;      ASSERT n = 0, 'T08 guest sees no links';
    SELECT count(*) INTO n FROM audit_log;       ASSERT n = 0, 'T08 guest sees no audit';
    RAISE NOTICE 'PASS T08 khách chỉ thấy người và nhóm trường trong chế độ xem của link';
END $$;

-- ---------------------------------------------------------------- T09
SELECT set_config('app.share_link_id', '', false), set_config('app.user_id', :'OWNER1', false);
UPDATE share_link SET revoked_at = now() WHERE id = :'LINK_OK';
SELECT set_config('app.user_id', '', false), set_config('app.share_link_id', :'LINK_OK', false);
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM person; ASSERT n = 0, 'T09 revoked link sees nothing';
    RAISE NOTICE 'PASS T09 thu hồi link có hiệu lực tức thời với phiên khách đang mở';
END $$;

-- ---------------------------------------------------------------- T10
SELECT set_config('app.share_link_id', :'LINK_EXPIRED', false);
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM person; ASSERT n = 0, 'T10 expired link sees nothing';
    BEGIN
        PERFORM * FROM gp_resolve_share_link(sha256(convert_to('guest-token-expired', 'UTF8')));
        RAISE EXCEPTION 'T10 expired token should not resolve';
    EXCEPTION WHEN SQLSTATE 'GP001' THEN NULL;
    END;
    RAISE NOTICE 'PASS T10 link hết hạn không sử dụng được';
END $$;

-- ---------------------------------------------------------------- T11
SELECT set_config('app.share_link_id', '', false), set_config('app.user_id', :'OWNER1', false),
       set_config('app.clan_id', :'C1', false);
DO $$
BEGIN
    BEGIN
        INSERT INTO union_child (clan_id, union_id, child_id)
        VALUES ('c1000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000004',
                '90000000-0000-0000-0000-000000000001');
        RAISE EXCEPTION 'T11 cross-clan child should fail';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO family_union (clan_id, partner_a_id, partner_b_id)
        VALUES ('c1000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000033',
                '90000000-0000-0000-0000-000000000001');
        RAISE EXCEPTION 'T11 cross-clan union should fail';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO person (clan_id, full_name) VALUES ('c2000000-0000-0000-0000-000000000002', 'x');
        RAISE EXCEPTION 'T11 insert into other clan should fail';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
        UPDATE person SET clan_id = 'c2000000-0000-0000-0000-000000000002'
        WHERE id = '10000000-0000-0000-0000-000000000033';
        RAISE EXCEPTION 'T11 moving person across clans should fail';
    EXCEPTION WHEN check_violation OR insufficient_privilege THEN NULL;
    END;
    RAISE NOTICE 'PASS T11 không tạo được tham chiếu hoặc dữ liệu chéo dòng họ, kể cả với OWNER';
END $$;

-- ---------------------------------------------------------------- T12
DO $$
DECLARE c text;
BEGIN
    BEGIN
        INSERT INTO union_child (clan_id, union_id, child_id, relation)
        VALUES ('c1000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000003',
                '10000000-0000-0000-0000-000000000011', 'ADOPTED');
        RAISE EXCEPTION 'T12 cycle should fail';
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS c = CONSTRAINT_NAME;
        ASSERT c = 'person_no_ancestry_cycle', format('T12 wrong constraint %s', c);
    END;
    RAISE NOTICE 'PASS T12 chặn quan hệ tổ tiên vòng';
END $$;

-- ---------------------------------------------------------------- T13
DO $$
DECLARE n int;
BEGIN
    BEGIN
        INSERT INTO union_child (clan_id, union_id, child_id, relation)
        VALUES ('c1000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000004',
                '10000000-0000-0000-0000-000000000031', 'BIOLOGICAL');
        RAISE EXCEPTION 'T13 second biological family should fail';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    INSERT INTO union_child (clan_id, union_id, child_id, relation)
    VALUES ('c1000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000004',
            '10000000-0000-0000-0000-000000000031', 'ADOPTED');
    SELECT depth INTO n FROM person_closure
    WHERE ancestor_id = '10000000-0000-0000-0000-000000000022' AND descendant_id = '10000000-0000-0000-0000-000000000031';
    ASSERT n = 1, 'T13 closure updated after adoption';
    DELETE FROM union_child WHERE union_id = '20000000-0000-0000-0000-000000000004'
                              AND child_id = '10000000-0000-0000-0000-000000000031';
    SELECT count(*) INTO n FROM person_closure
    WHERE ancestor_id = '10000000-0000-0000-0000-000000000022' AND descendant_id = '10000000-0000-0000-0000-000000000031';
    ASSERT n = 0, 'T13 closure updated after removal';
    RAISE NOTICE 'PASS T13 một gia đình đẻ, nhiều gia đình nuôi; closure tự cập nhật';
END $$;

-- ---------------------------------------------------------------- T14
DO $$
DECLARE n int;
BEGIN
    SELECT depth INTO n FROM person_closure
    WHERE ancestor_id = '10000000-0000-0000-0000-000000000011' AND descendant_id = '10000000-0000-0000-0000-000000000031';
    ASSERT n = 2, 'T14 An -> Đức is 2 generations';
    BEGIN
        DELETE FROM person WHERE id = '10000000-0000-0000-0000-000000000031';
        RAISE EXCEPTION 'T14 deleting person with relations should fail';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;
    RAISE NOTICE 'PASS T14 số đời đúng; không xóa được người còn quan hệ';
END $$;

-- ---------------------------------------------------------------- T15
DO $$
DECLARE id_ uuid;
BEGIN
    BEGIN
        INSERT INTO person (clan_id, full_name, birth_solar_precision, birth_solar_year, birth_solar_month, birth_solar_day)
        VALUES ('c1000000-0000-0000-0000-000000000001', 'x', 'DAY', 1990, 2, 30);
        RAISE EXCEPTION 'T15 30/02 should fail';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO person (clan_id, full_name, birth_lunar_precision, birth_lunar_year, birth_lunar_leap)
        VALUES ('c1000000-0000-0000-0000-000000000001', 'x', 'YEAR', 1890, true);
        RAISE EXCEPTION 'T15 leap month with YEAR precision should fail';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO person (clan_id, full_name, birth_solar_precision, birth_solar_year, birth_solar_month)
        VALUES ('c1000000-0000-0000-0000-000000000001', 'x', 'DAY', 1990, 2);
        RAISE EXCEPTION 'T15 DAY without day should fail';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO person (clan_id, full_name, birth_solar_approx) VALUES ('c1000000-0000-0000-0000-000000000001', 'x', true);
        RAISE EXCEPTION 'T15 approximate UNKNOWN should fail';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO person (clan_id, full_name, is_living, death_solar_precision, death_solar_year)
        VALUES ('c1000000-0000-0000-0000-000000000001', 'x', true, 'YEAR', 2000);
        RAISE EXCEPTION 'T15 living person with death date should fail';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    INSERT INTO person (id, clan_id, full_name, is_living,
                        death_lunar_precision, death_lunar_year, death_lunar_month, death_lunar_day, death_lunar_leap,
                        death_solar_precision, death_solar_year, death_solar_approx)
    VALUES (gen_random_uuid(), 'c1000000-0000-0000-0000-000000000001', 'Cụ Tổ', false,
            'DAY', 1890, 4, 30, true, 'YEAR', 1890, true)
    RETURNING id INTO id_;
    DELETE FROM person WHERE id = id_;
    RAISE NOTICE 'PASS T15 ràng buộc ngày âm lịch, dương lịch có độ chính xác';
END $$;

-- ---------------------------------------------------------------- T16
SELECT set_config('app.user_id', :'MEMBER1', false);
DO $$
DECLARE n int;
BEGIN
    PERFORM gp_audit('PERSON_VIEW_SENSITIVE', 'person', '10000000-0000-0000-0000-000000000031');
    SELECT count(*) INTO n FROM audit_log; ASSERT n = 0, 'T16 member cannot read audit';
    BEGIN
        INSERT INTO audit_log (clan_id, actor_user_id, action)
        VALUES ('c1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'PERSON_DELETE');
        RAISE EXCEPTION 'T16 direct audit insert should fail';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    RAISE NOTICE 'PASS T16a audit ghi qua hàm; không ghi trực tiếp, không giả mạo được';
END $$;
SELECT set_config('app.user_id', :'OWNER1', false);
DO $$
DECLARE actor uuid;
BEGIN
    SELECT actor_user_id INTO actor FROM audit_log WHERE action = 'PERSON_VIEW_SENSITIVE';
    ASSERT actor = 'a0000000-0000-0000-0000-000000000003', 'T16 actor comes from session';
    BEGIN
        DELETE FROM audit_log;
        RAISE EXCEPTION 'T16 audit delete should fail';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
        UPDATE audit_log SET action = 'X';
        RAISE EXCEPTION 'T16 audit update should fail';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    RAISE NOTICE 'PASS T16b OWNER đọc được audit; không ai sửa, xóa được';
END $$;

-- ---------------------------------------------------------------- T17
DO $$
DECLARE c text;
BEGIN
    BEGIN
        SET CONSTRAINTS clan_membership_owner_guard IMMEDIATE;
        DELETE FROM clan_membership WHERE user_id = 'a0000000-0000-0000-0000-000000000001'
                                      AND clan_id = 'c1000000-0000-0000-0000-000000000001';
        RAISE EXCEPTION 'T17 removing the owner should fail';
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS c = CONSTRAINT_NAME;
        ASSERT c = 'clan_must_have_owner', format('T17 wrong constraint %s', c);
    END;
    RAISE NOTICE 'PASS T17 không xóa được OWNER của dòng họ';
END $$;

-- ---------------------------------------------------------------- T18
SELECT set_config('app.clan_id', '', false), set_config('app.user_id', :'MEMBER1', false);
DO $$
BEGIN
    BEGIN
        PERFORM gp_accept_invitation(sha256(convert_to('invite-token-1', 'UTF8')));
        RAISE EXCEPTION 'T18 wrong email should fail';
    EXCEPTION WHEN SQLSTATE 'GP002' THEN NULL;
    END;
    RAISE NOTICE 'PASS T18a lời mời chỉ dùng được với đúng email';
END $$;
SELECT set_config('app.user_id', :'UNVERIFIED', false);
DO $$
BEGIN
    BEGIN
        PERFORM gp_accept_invitation(sha256(convert_to('invite-token-2', 'UTF8')));
        RAISE EXCEPTION 'T18 unverified email should fail';
    EXCEPTION WHEN SQLSTATE 'GP007' THEN NULL;
    END;
    BEGIN
        PERFORM gp_create_clan('Họ chưa xác minh');
        RAISE EXCEPTION 'T18 unverified user must not create clans';
    EXCEPTION WHEN SQLSTATE 'GP007' THEN NULL;
    END;
    RAISE NOTICE 'PASS T18b email chưa xác minh không nhận lời mời, không tạo dòng họ được';
END $$;
SELECT set_config('app.user_id', :'NEWCOMER', false);
DO $$
DECLARE c uuid; p uuid;
BEGIN
    c := gp_accept_invitation(sha256(convert_to('invite-token-1', 'UTF8')));
    ASSERT c = 'c1000000-0000-0000-0000-000000000001', 'T18 accept returns clan';
    PERFORM set_config('app.clan_id', c::text, true);
    SELECT person_id INTO p FROM clan_membership WHERE user_id = 'a0000000-0000-0000-0000-000000000005';
    ASSERT p = '10000000-0000-0000-0000-000000000033', 'T18 invitation links the account to Giang';
    BEGIN
        PERFORM gp_accept_invitation(sha256(convert_to('invite-token-1', 'UTF8')));
        RAISE EXCEPTION 'T18 reuse should fail';
    EXCEPTION WHEN SQLSTATE 'GP001' THEN NULL;
    END;
    RAISE NOTICE 'PASS T18c nhận lời mời một lần, tài khoản được gắn với hồ sơ chỉ định';
END $$;

-- ---------------------------------------------------------------- T19
SELECT set_config('app.user_id', '', false), set_config('app.clan_id', '', false);
DO $$
BEGIN
    BEGIN
        PERFORM gp_create_clan('Không ai tạo');
        RAISE EXCEPTION 'T19 anonymous create should fail';
    EXCEPTION WHEN SQLSTATE 'GP004' THEN NULL;
    END;
    BEGIN
        PERFORM gp_rebuild_person_closure('c1000000-0000-0000-0000-000000000001');
        RAISE EXCEPTION 'T19 app must not call internal functions';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
        PERFORM gp_swap_owner('c1000000-0000-0000-0000-000000000001',
                              'a0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000003');
        RAISE EXCEPTION 'T19 app must not swap owners directly';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
        PERFORM gp_purge_expired_data();
        RAISE EXCEPTION 'T19 app must not purge audit';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
        INSERT INTO person_closure VALUES ('c1000000-0000-0000-0000-000000000001',
            '10000000-0000-0000-0000-000000000033', '10000000-0000-0000-0000-000000000011', 1);
        RAISE EXCEPTION 'T19 app must not write closure';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    ASSERT gp_search_key('Nguyễn Văn Đức') = 'nguyen van duc', 'T19 search key';
    RAISE NOTICE 'PASS T19 hàm nội bộ, closure và tác vụ bảo trì nằm ngoài quyền của ứng dụng';
END $$;

-- ---------------------------------------------------------------- T20
SELECT set_config('app.user_id', :'EDITOR1', false), set_config('app.clan_id', :'C1', false);
DO $$
DECLARE n int;
BEGIN
    BEGIN
        INSERT INTO person (clan_id, full_name) VALUES ('c1000000-0000-0000-0000-000000000001', 'x') RETURNING id INTO n;
        RAISE EXCEPTION 'T20 scoped editor RETURNING should fail';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    INSERT INTO person (id, clan_id, full_name, gender)
    VALUES ('10000000-0000-0000-0000-000000000041', 'c1000000-0000-0000-0000-000000000001', 'Nguyễn Văn Phúc', 'MALE');
    INSERT INTO union_child (clan_id, union_id, child_id, birth_order)
    VALUES ('c1000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000003',
            '10000000-0000-0000-0000-000000000041', 3);
    SELECT count(*) INTO n FROM person WHERE id = '10000000-0000-0000-0000-000000000041';
    ASSERT n = 1, 'T20 new child visible to editor after linking';
    RAISE NOTICE 'PASS T20 EDITOR có phạm vi thêm được con trong nhánh theo luồng sinh UUID và gắn ngay';
END $$;

-- ---------------------------------------------------------------- T21
DO $$
DECLARE n int;
BEGIN
    DELETE FROM person WHERE id = '10000000-0000-0000-0000-000000000031';
    GET DIAGNOSTICS n = ROW_COUNT; ASSERT n = 0, 'T21 editor must not delete persons';
    SELECT count(*) INTO n FROM audit_log; ASSERT n = 0, 'T21 editor must not read audit';
    RAISE NOTICE 'PASS T21 chỉ OWNER xóa người; EDITOR không đọc audit';
END $$;

-- ---------------------------------------------------------------- T22
DO $$
BEGIN
    ASSERT app_visible_field_groups() = ARRAY['BASIC', 'LIFE_EVENTS', 'BIOGRAPHY', 'LIVING_BIRTH_DATE', 'CONTACT', 'ADOPTION'],
        'T22 editor field groups';
    RAISE NOTICE 'PASS T22a EDITOR thấy mọi nhóm trường trừ giấy tờ';
END $$;
SELECT set_config('app.user_id', :'OWNER1', false);
DO $$ BEGIN ASSERT app_visible_field_groups() = gp_all_field_groups(), 'T22 owner field groups'; END $$;
SELECT set_config('app.user_id', :'MEMBER1', false);
DO $$ BEGIN ASSERT app_visible_field_groups() = ARRAY['BASIC', 'LIFE_EVENTS', 'BIOGRAPHY'], 'T22 member default groups'; END $$;
SELECT set_config('app.user_id', :'MEMBER2', false);
DO $$
BEGIN
    ASSERT app_visible_field_groups() = ARRAY['BASIC', 'LIFE_EVENTS'], 'T22 member override groups';
    RAISE NOTICE 'PASS T22b nhóm trường theo OWNER, chế độ mặc định và chế độ riêng của MEMBER';
END $$;

-- ---------------------------------------------------------------- T23
SELECT set_config('app.user_id', :'OWNER1', false);
UPDATE view_policy SET scope_mode = 'BRANCH', root_person_id = '10000000-0000-0000-0000-000000000021',
       depth_down = 1, depth_up = 0, field_groups = ARRAY['BASIC', 'CONTACT']
WHERE id = '70000000-0000-0000-0000-000000000001';
SELECT set_config('app.user_id', :'MEMBER1', false);
DO $$
DECLARE ids text;
BEGIN
    SELECT string_agg(right(id::text, 2), ',' ORDER BY id) INTO ids FROM person;
    ASSERT ids = '21,24,31,32,41', format('T23 default policy change applies to member; got %s', ids);
    ASSERT app_visible_field_groups() = ARRAY['BASIC', 'CONTACT'], 'T23 field groups follow default policy';
    RAISE NOTICE 'PASS T23 sửa chế độ xem mặc định áp dụng ngay cho toàn bộ MEMBER';
END $$;
SELECT set_config('app.user_id', :'OWNER1', false);
UPDATE view_policy SET scope_mode = 'CLAN', root_person_id = NULL, depth_down = NULL, depth_up = NULL,
       field_groups = ARRAY['BASIC', 'LIFE_EVENTS', 'BIOGRAPHY']
WHERE id = '70000000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------- T24
SELECT set_config('app.user_id', :'MEMBER2', false);
DO $$
DECLARE ids text; n int;
BEGIN
    -- Đức: 1 đời lên (Bình, Hoa) và hậu duệ tới 1 đời dưới thế hệ Đức
    SELECT string_agg(right(id::text, 2), ',' ORDER BY id) INTO ids FROM person;
    ASSERT ids = '21,24,31,32,41', format('T24 relative scope of member2; got %s', ids);
    PERFORM set_config('app.user_id', 'a0000000-0000-0000-0000-000000000008', false);
    SELECT count(*) INTO n FROM person;
    ASSERT n = 0, 'T24 unlinked member under relative policy sees nothing';
    RAISE NOTICE 'PASS T24 phạm vi tương đối theo hồ sơ của người xem; chưa gắn hồ sơ thì không có phạm vi';
END $$;

-- ---------------------------------------------------------------- T25
SELECT set_config('app.user_id', :'OWNER1', false);
DO $$
DECLARE c text;
BEGIN
    INSERT INTO view_policy (id, clan_id, name, scope_mode, field_groups)
    VALUES ('70000000-0000-0000-0000-000000000006', 'c1000000-0000-0000-0000-000000000001', 'Có liên hệ', 'CLAN',
            ARRAY['BASIC', 'CONTACT']);
    BEGIN
        INSERT INTO share_link (clan_id, token_hash, view_policy_id, created_by)
        VALUES ('c1000000-0000-0000-0000-000000000001', sha256(convert_to('t25a', 'UTF8')),
                '70000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000001');
        RAISE EXCEPTION 'T25 link with CONTACT should fail';
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS c = CONSTRAINT_NAME;
        ASSERT c = 'share_link_policy_ceiling', format('T25 wrong constraint %s', c);
    END;
    BEGIN
        INSERT INTO share_link (clan_id, token_hash, view_policy_id, created_by)
        VALUES ('c1000000-0000-0000-0000-000000000001', sha256(convert_to('t25b', 'UTF8')),
                '70000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001');
        RAISE EXCEPTION 'T25 link with RELATIVE policy should fail';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        UPDATE view_policy SET field_groups = ARRAY['BASIC', 'LIVING_BIRTH_DATE']
        WHERE id = '70000000-0000-0000-0000-000000000005';
        RAISE EXCEPTION 'T25 widening a policy used by a link should fail';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO view_policy (clan_id, name, scope_mode, field_groups)
        VALUES ('c1000000-0000-0000-0000-000000000001', 'Giấy tờ', 'CLAN', ARRAY['BASIC', 'IDENTITY_DOCS']);
        RAISE EXCEPTION 'T25 IDENTITY_DOCS in a policy should fail';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    RAISE NOTICE 'PASS T25 trần an toàn của link công khai và của chế độ xem';
END $$;

-- ---------------------------------------------------------------- T26
SELECT set_config('app.user_id', '', false), set_config('app.share_link_id', :'LINK_PERPETUAL', false);
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM person; ASSERT n = 11, format('T26 perpetual CLAN link sees the clan, saw %s', n);
    ASSERT app_visible_field_groups() = ARRAY['BASIC', 'LIFE_EVENTS'], 'T26 link field groups';
    RAISE NOTICE 'PASS T26a link không thời hạn hoạt động';
END $$;
SELECT set_config('app.share_link_id', '', false), set_config('app.user_id', :'OWNER1', false);
UPDATE share_link SET deleted_at = now() WHERE id = :'LINK_PERPETUAL';
SELECT set_config('app.user_id', '', false), set_config('app.share_link_id', :'LINK_PERPETUAL', false);
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM person; ASSERT n = 0, 'T26 deleted link sees nothing';
    BEGIN
        PERFORM * FROM gp_resolve_share_link(sha256(convert_to('guest-token-perpetual', 'UTF8')));
        RAISE EXCEPTION 'T26 deleted link should not resolve';
    EXCEPTION WHEN SQLSTATE 'GP001' THEN NULL;
    END;
    RAISE NOTICE 'PASS T26b link đã xóa mất hiệu lực tức thời';
END $$;

-- ---------------------------------------------------------------- T27
SELECT set_config('app.share_link_id', '', false), set_config('app.user_id', :'OWNER1', false);
DO $$
DECLARE c text;
BEGIN
    BEGIN
        UPDATE clan_membership SET role = 'OWNER' WHERE user_id = 'a0000000-0000-0000-0000-000000000003';
        RAISE EXCEPTION 'T27 second OWNER should fail';
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS c = CONSTRAINT_NAME;
        ASSERT c = 'clan_membership_one_owner_uk', format('T27 wrong constraint %s', c);
    END;
    RAISE NOTICE 'PASS T27 mỗi dòng họ có đúng một OWNER; đổi trưởng tộc phải qua chuyển giao';
END $$;

-- ---------------------------------------------------------------- T28
DO $$
BEGIN
    BEGIN
        UPDATE clan_membership SET person_id = '10000000-0000-0000-0000-000000000031'
        WHERE user_id = 'a0000000-0000-0000-0000-000000000008';
        RAISE EXCEPTION 'T28 linking a person twice should fail';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    RAISE NOTICE 'PASS T28 một hồ sơ gắn với tối đa một tài khoản';
END $$;

-- ---------------------------------------------------------------- T29
SELECT set_config('app.user_id', :'MEMBER3', false);
DO $$
BEGIN
    BEGIN
        PERFORM gp_claim_person('10000000-0000-0000-0000-000000000032');
        RAISE EXCEPTION 'T29 claiming an invisible person should fail';
    EXCEPTION WHEN SQLSTATE 'GP009' THEN NULL;
    END;
END $$;
SELECT set_config('app.user_id', :'MEMBER1', false);
SELECT set_config('test.claim_id', gp_claim_person('10000000-0000-0000-0000-000000000032', 'Đây là tôi')::text, false);
DO $$
BEGIN
    BEGIN
        PERFORM gp_claim_person('10000000-0000-0000-0000-000000000021');
        RAISE EXCEPTION 'T29 second pending claim should fail';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
END $$;
SELECT set_config('app.user_id', :'EDITOR1', false);
DO $$
BEGIN
    BEGIN
        PERFORM gp_decide_claim(current_setting('test.claim_id')::uuid, true, 'x');
        RAISE EXCEPTION 'T29 editor must not approve claims';
    EXCEPTION WHEN SQLSTATE 'GP005' THEN NULL;
    END;
END $$;
SELECT set_config('app.user_id', :'OWNER1', false);
DO $$
DECLARE p uuid;
BEGIN
    PERFORM gp_decide_claim(current_setting('test.claim_id')::uuid, true, 'Đã xác minh');
    SELECT person_id INTO p FROM clan_membership WHERE user_id = 'a0000000-0000-0000-0000-000000000003';
    ASSERT p = '10000000-0000-0000-0000-000000000032', 'T29 claim approved links the account';
    RAISE NOTICE 'PASS T29 yêu cầu nhận hồ sơ: chỉ hồ sơ trong phạm vi, một yêu cầu chờ, chỉ OWNER duyệt';
END $$;

-- ---------------------------------------------------------------- T30
SELECT set_config('app.user_id', :'MEMBER1', false);
DO $$
DECLARE n int;
BEGIN
    PERFORM gp_update_own_profile('0900000000', 'em@test.vn', 'Hà Nội', true);
    UPDATE person SET phone = 'x' WHERE id = '10000000-0000-0000-0000-000000000032';
    GET DIAGNOSTICS n = ROW_COUNT; ASSERT n = 0, 'T30 member cannot update the person table directly';
END $$;
SELECT set_config('app.user_id', :'OWNER1', false);
DO $$
DECLARE r record;
BEGIN
    SELECT phone, is_restricted INTO r FROM person WHERE id = '10000000-0000-0000-0000-000000000032';
    ASSERT r.phone = '0900000000' AND r.is_restricted, 'T30 self-service update applied';
    RAISE NOTICE 'PASS T30 người đã gắn hồ sơ tự sửa liên hệ và cờ hạn chế của mình';
END $$;

-- ---------------------------------------------------------------- T31
DO $$
DECLARE v1 bigint; v2 bigint;
BEGIN
    SELECT data_version INTO v1 FROM clan WHERE id = 'c1000000-0000-0000-0000-000000000001';
    UPDATE person SET occupation = 'Nông dân' WHERE id = '10000000-0000-0000-0000-000000000011';
    SELECT data_version INTO v2 FROM clan WHERE id = 'c1000000-0000-0000-0000-000000000001';
    ASSERT v2 > v1, 'T31 data_version increases on change';
    RAISE NOTICE 'PASS T31 phiên bản dữ liệu dòng họ tăng khi dữ liệu thay đổi (khóa cache)';
END $$;

-- ---------------------------------------------------------------- T32
SELECT set_config('app.user_id', :'OWNER2', false), set_config('app.clan_id', :'C2', false);
DO $$
DECLARE n int;
BEGIN
    BEGIN
        INSERT INTO view_policy (clan_id, name, scope_mode) VALUES ('c2000000-0000-0000-0000-000000000002', 'Thứ hai', 'CLAN');
        RAISE EXCEPTION 'T32 FREE plan allows one view policy';
    EXCEPTION WHEN SQLSTATE 'GP010' THEN NULL;
    END;
    INSERT INTO share_link (clan_id, token_hash, view_policy_id, created_by) VALUES
        ('c2000000-0000-0000-0000-000000000002', sha256(convert_to('t32a', 'UTF8')),
         '70000000-0000-0000-0000-000000000021', 'a0000000-0000-0000-0000-000000000004'),
        ('c2000000-0000-0000-0000-000000000002', sha256(convert_to('t32b', 'UTF8')),
         '70000000-0000-0000-0000-000000000021', 'a0000000-0000-0000-0000-000000000004');
    BEGIN
        INSERT INTO share_link (clan_id, token_hash, view_policy_id, created_by)
        VALUES ('c2000000-0000-0000-0000-000000000002', sha256(convert_to('t32c', 'UTF8')),
                '70000000-0000-0000-0000-000000000021', 'a0000000-0000-0000-0000-000000000004');
        RAISE EXCEPTION 'T32 FREE plan allows two share links';
    EXCEPTION WHEN SQLSTATE 'GP010' THEN NULL;
    END;
    SELECT used_share_links INTO n FROM gp_clan_entitlements(); ASSERT n = 2, 'T32 usage reported';
    RAISE NOTICE 'PASS T32 hạn mức gói FREE được áp dụng tại cơ sở dữ liệu';
END $$;

-- ---------------------------------------------------------------- T33
DO $$
DECLARE r record; st text; e1 timestamptz; e2 timestamptz;
BEGIN
    BEGIN
        PERFORM * FROM gp_create_payment('FREE', 1);
        RAISE EXCEPTION 'T33 FREE plan is not purchasable';
    EXCEPTION WHEN SQLSTATE 'GP022' THEN NULL;
    END;
    SELECT * INTO r FROM gp_create_payment('STANDARD', 3);
    ASSERT r.amount_vnd = 147000, format('T33 amount computed server-side, got %s', r.amount_vnd);
    BEGIN
        PERFORM gp_confirm_payment(r.txn_ref, 1000, true);
        RAISE EXCEPTION 'T33 amount mismatch should fail';
    EXCEPTION WHEN SQLSTATE 'GP021' THEN NULL;
    END;
    BEGIN
        PERFORM gp_confirm_payment('UNKNOWN123', 147000, true);
        RAISE EXCEPTION 'T33 unknown transaction should fail';
    EXCEPTION WHEN SQLSTATE 'GP020' THEN NULL;
    END;
    st := gp_confirm_payment(r.txn_ref, 147000, true, 'VNP001');
    ASSERT st = 'SUCCEEDED', 'T33 payment succeeded';
    SELECT current_period_end INTO e1 FROM gp_clan_entitlements();
    ASSERT (SELECT plan_code FROM gp_clan_entitlements()) = 'STANDARD', 'T33 plan upgraded';
    st := gp_confirm_payment(r.txn_ref, 147000, true, 'VNP001');
    SELECT current_period_end INTO e2 FROM gp_clan_entitlements();
    ASSERT st = 'SUCCEEDED' AND e1 = e2, 'T33 IPN replay is idempotent';
    INSERT INTO view_policy (clan_id, name, scope_mode) VALUES ('c2000000-0000-0000-0000-000000000002', 'Thứ hai', 'CLAN');
    RAISE NOTICE 'PASS T33 thanh toán: số tiền do máy chủ tính, kiểm tra số tiền, IPN idempotent, nâng gói có hiệu lực ngay';
END $$;
SELECT set_config('app.user_id', :'EDITOR1', false), set_config('app.clan_id', :'C1', false);
DO $$
BEGIN
    BEGIN
        PERFORM * FROM gp_create_payment('STANDARD', 1);
        RAISE EXCEPTION 'T33 only OWNER can pay';
    EXCEPTION WHEN SQLSTATE 'GP005' THEN NULL;
    END;
END $$;

-- ---------------------------------------------------------------- T34
SELECT set_config('app.user_id', :'ADMIN', false), set_config('app.clan_id', :'C1', false);
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM person; ASSERT n = 0, 'T34 system admin cannot read genealogy data';
    SELECT count(*) INTO n FROM gp_admin_list_clans(); ASSERT n = 4, format('T34 admin lists clan metadata, got %s', n);
    BEGIN
        PERFORM gp_admin_set_user_status('a0000000-0000-0000-0000-000000000009', 'LOCKED', 'test');
        RAISE EXCEPTION 'T34 admin must not lock self';
    EXCEPTION WHEN SQLSTATE 'GP008' THEN NULL;
    END;
    PERFORM gp_admin_set_clan_status('c2000000-0000-0000-0000-000000000002', 'SUSPENDED', 'Vi phạm điều khoản');
END $$;
SELECT set_config('app.user_id', :'SUPPORT', false);
DO $$
BEGIN
    BEGIN
        PERFORM gp_admin_set_clan_status('c2000000-0000-0000-0000-000000000002', 'ACTIVE', 'x');
        RAISE EXCEPTION 'T34 support must not change clan status';
    EXCEPTION WHEN SQLSTATE 'GP005' THEN NULL;
    END;
END $$;
SELECT set_config('app.user_id', :'MEMBER1', false);
DO $$
BEGIN
    BEGIN
        PERFORM gp_admin_list_clans();
        RAISE EXCEPTION 'T34 regular users must not call admin functions';
    EXCEPTION WHEN SQLSTATE 'GP005' THEN NULL;
    END;
END $$;
SELECT set_config('app.user_id', :'OWNER2', false), set_config('app.clan_id', :'C2', false);
DO $$
DECLARE n int; st text;
BEGIN
    SELECT count(*) INTO n FROM person; ASSERT n = 0, 'T34 suspended clan hides data from its owner';
    SELECT status INTO st FROM clan WHERE id = 'c2000000-0000-0000-0000-000000000002';
    ASSERT st = 'SUSPENDED', 'T34 owner still sees the clan status';
    BEGIN
        PERFORM * FROM gp_resolve_share_link(sha256(convert_to('t32a', 'UTF8')));
        RAISE EXCEPTION 'T34 links of a suspended clan must not resolve';
    EXCEPTION WHEN SQLSTATE 'GP001' THEN NULL;
    END;
    RAISE NOTICE 'PASS T34 quản trị nền tảng: không đọc được gia phả, phân quyền SYSTEM_ADMIN/SUPPORT, tạm ngưng dòng họ';
END $$;
SELECT set_config('app.user_id', :'ADMIN', false);
SELECT gp_admin_set_clan_status(:'C2', 'ACTIVE', 'Đã xử lý');

-- ---------------------------------------------------------------- T35
SELECT set_config('app.user_id', :'MEMBER1', false), set_config('app.clan_id', :'C1', false);
DO $$
BEGIN
    BEGIN
        INSERT INTO app_user (email, password_hash, display_name, system_role) VALUES ('x@test.vn', 'x', 'x', 'SYSTEM_ADMIN');
        RAISE EXCEPTION 'T35 app must not set system_role';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
        UPDATE app_user SET system_role = 'SYSTEM_ADMIN' WHERE id = 'a0000000-0000-0000-0000-000000000003';
        RAISE EXCEPTION 'T35 app must not grant system roles';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
        UPDATE app_user SET last_active_at = now() - interval '1000 days' WHERE id = 'a0000000-0000-0000-0000-000000000001';
        RAISE EXCEPTION 'T35 app must not forge activity';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
        UPDATE clan SET status = 'ACTIVE', successor_user_id = NULL;
        RAISE EXCEPTION 'T35 app must not write clan status or successor directly';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    RAISE NOTICE 'PASS T35 quyền theo cột: ứng dụng không ghi được vai trò hệ thống, hoạt động, trạng thái dòng họ';
END $$;

-- ---------------------------------------------------------------- T36
SELECT set_config('app.user_id', :'OWNER1', false);
SELECT set_config('test.transfer_id', gp_transfer_request(:'EDITOR1', 'Nghỉ hưu')::text, false);
DO $$
BEGIN
    BEGIN
        PERFORM gp_transfer_request('a0000000-0000-0000-0000-000000000003');
        RAISE EXCEPTION 'T36 only one active transfer per clan';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
END $$;
SELECT set_config('app.user_id', :'MEMBER1', false);
DO $$
BEGIN
    BEGIN
        PERFORM gp_transfer_accept(current_setting('test.transfer_id')::uuid);
        RAISE EXCEPTION 'T36 only the recipient can accept';
    EXCEPTION WHEN SQLSTATE 'GP009' THEN NULL;
    END;
END $$;
SELECT set_config('app.user_id', :'EDITOR1', false);
SELECT gp_transfer_accept(current_setting('test.transfer_id')::uuid);
DO $$
DECLARE r1 text; r2 text;
BEGIN
    SELECT role INTO r1 FROM clan_membership WHERE user_id = 'a0000000-0000-0000-0000-000000000002';
    SELECT role INTO r2 FROM clan_membership WHERE user_id = 'a0000000-0000-0000-0000-000000000001';
    ASSERT r1 = 'OWNER' AND r2 = 'EDITOR', 'T36 roles swapped';
END $$;
-- Hoàn nguyên để giữ nguyên dữ liệu mẫu.
SELECT set_config('test.transfer_id', gp_transfer_request(:'OWNER1')::text, false);
SELECT set_config('app.user_id', :'OWNER1', false);
SELECT gp_transfer_accept(current_setting('test.transfer_id')::uuid);
DO $$
DECLARE r text;
BEGIN
    SELECT role INTO r FROM clan_membership WHERE user_id = 'a0000000-0000-0000-0000-000000000001';
    ASSERT r = 'OWNER', 'T36 ownership transferred back';
    RAISE NOTICE 'PASS T36 chuyển giao chủ động: một yêu cầu đang xử lý, chỉ người nhận chấp nhận, hoán đổi vai trò';
END $$;

-- ---------------------------------------------------------------- T37
SELECT set_config('app.user_id', :'MEMBER1', false);
DO $$
BEGIN
    BEGIN
        PERFORM gp_takeover_request('x');
        RAISE EXCEPTION 'T37 only the successor can request a takeover';
    EXCEPTION WHEN SQLSTATE 'GP005' THEN NULL;
    END;
END $$;
SELECT set_config('app.user_id', :'SUCCESSOR3', false), set_config('app.clan_id', :'C3', false);
SELECT gp_takeover_request('Trưởng tộc mất liên lạc');
SELECT gp_process_due_transfers();
DO $$
DECLARE r text; s uuid;
BEGIN
    SELECT role INTO r FROM clan_membership WHERE user_id = 'a0000000-0000-0000-0000-000000000013';
    ASSERT r = 'OWNER', 'T37 successor became OWNER after the waiting period';
    SELECT successor_user_id INTO s FROM clan WHERE id = 'c3000000-0000-0000-0000-000000000003';
    ASSERT s IS NULL, 'T37 successor designation cleared';
    RAISE NOTICE 'PASS T37 người kế nhiệm tiếp quản khi OWNER không hoạt động, sau thời gian chờ';
END $$;

-- ---------------------------------------------------------------- T38
SELECT set_config('app.user_id', :'EDITOR4A', false), set_config('app.clan_id', :'C4', false);
SELECT set_config('test.recovery_id', gp_recovery_request(:'EDITOR4A', 'Trưởng tộc đã mất')::text, false);
DO $$
DECLARE st text;
BEGIN
    SELECT status INTO st FROM ownership_transfer WHERE id = current_setting('test.recovery_id')::uuid;
    ASSERT st = 'PENDING_ENDORSEMENT', format('T38 needs 2 of 2 editors, status %s', st);
END $$;
SELECT set_config('app.user_id', :'EDITOR4B', false);
SELECT gp_recovery_endorse(current_setting('test.recovery_id')::uuid);
SELECT gp_process_due_transfers();
DO $$
DECLARE st text;
BEGIN
    SELECT status INTO st FROM ownership_transfer WHERE id = current_setting('test.recovery_id')::uuid;
    ASSERT st = 'PENDING_REVIEW', format('T38 recovery awaits support review, status %s', st);
END $$;
SELECT set_config('app.user_id', :'SUPPORT', false), set_config('app.clan_id', '', false);
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM gp_admin_list_pending_reviews(); ASSERT n = 1, 'T38 support sees one pending review';
END $$;
SELECT gp_admin_review_recovery(current_setting('test.recovery_id')::uuid, true, 'Đã đối chiếu giấy chứng tử');
SELECT set_config('app.user_id', :'EDITOR4A', false), set_config('app.clan_id', :'C4', false);
DO $$
DECLARE r text;
BEGIN
    SELECT role INTO r FROM clan_membership WHERE user_id = 'a0000000-0000-0000-0000-000000000015';
    ASSERT r = 'OWNER', 'T38 recovery completed';
    RAISE NOTICE 'PASS T38 đơn khôi phục: đủ xác nhận của EDITOR, thời gian chờ, SUPPORT duyệt';
END $$;

\echo 'All database tests passed.'
