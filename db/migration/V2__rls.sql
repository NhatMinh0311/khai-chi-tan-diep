-- =====================================================================
-- V2 — Row-Level Security, hàm nghiệp vụ, phân quyền vai trò cơ sở dữ liệu
--
-- Backend kết nối bằng gp_app (không sở hữu bảng, không BYPASSRLS) và đặt
-- ngữ cảnh ở đầu mỗi transaction:
--     SELECT set_config('app.user_id',       '<uuid>', true),
--            set_config('app.clan_id',       '<uuid>', true),
--            set_config('app.share_link_id', '<uuid>', true);   -- chỉ với khách
-- Thiếu ngữ cảnh: không trả về dòng nào (fail-closed).
--
-- Hàm SECURITY DEFINER thuộc gp_owner (chủ bảng) nên không chịu RLS; đây là
-- cơ chế tránh đệ quy policy. Bảng không đặt FORCE RLS vì lý do đó; backend
-- không được kết nối bằng gp_owner.
--
-- Trong policy, lời gọi hàm được bọc trong (SELECT ...) để PostgreSQL tính
-- một lần cho mỗi câu lệnh (InitPlan) thay vì cho từng dòng.
--
-- Mã lỗi riêng (SQLSTATE lớp GP), ánh xạ HTTP tại GP-DOC-03 mục 10:
--   GP001 token không hợp lệ        GP006 hồ sơ đã gắn với tài khoản khác
--   GP002 email không khớp lời mời  GP007 email chưa xác minh
--   GP003 đã là thành viên          GP008 trạng thái không cho phép thao tác
--   GP004 chưa xác thực             GP009 không tìm thấy
--   GP005 không đủ quyền            GP010 vượt hạn mức gói
--   GP020 không tìm thấy giao dịch  GP021 số tiền không khớp
--   GP022 gói không mua được
-- =====================================================================

-- ---------------------------------------------------------------------
-- Ngữ cảnh phiên
-- ---------------------------------------------------------------------

CREATE FUNCTION app_current_clan() RETURNS uuid
LANGUAGE sql STABLE
AS $$ SELECT nullif(current_setting('app.clan_id', true), '')::uuid $$;

CREATE FUNCTION app_current_user() RETURNS uuid
LANGUAGE sql STABLE
AS $$ SELECT nullif(current_setting('app.user_id', true), '')::uuid $$;

CREATE FUNCTION app_current_share_link() RETURNS uuid
LANGUAGE sql STABLE
AS $$ SELECT nullif(current_setting('app.share_link_id', true), '')::uuid $$;

-- Vai trò hệ thống của người dùng hiện tại (SYSTEM_ADMIN, SUPPORT) hoặc NULL.
CREATE FUNCTION app_current_system_role() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT u.system_role FROM app_user u
    WHERE u.id = app_current_user() AND u.status = 'ACTIVE'
$$;

-- Vai trò trong dòng họ hiện tại: OWNER, EDITOR, MEMBER, GUEST hoặc NULL.
-- NULL khi: thiếu ngữ cảnh, không phải thành viên, tài khoản bị khóa,
-- dòng họ bị tạm ngưng, link hết hạn, bị thu hồi hoặc đã xóa.
CREATE FUNCTION app_principal_role() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT CASE
        WHEN app_current_clan() IS NULL THEN NULL
        WHEN NOT EXISTS (SELECT 1 FROM clan c WHERE c.id = app_current_clan() AND c.status = 'ACTIVE') THEN NULL
        WHEN app_current_user() IS NOT NULL THEN (
            SELECT m.role
            FROM clan_membership m
            JOIN app_user u ON u.id = m.user_id AND u.status = 'ACTIVE'
            WHERE m.clan_id = app_current_clan() AND m.user_id = app_current_user())
        WHEN app_current_share_link() IS NOT NULL THEN (
            SELECT 'GUEST'
            FROM share_link s
            WHERE s.id = app_current_share_link() AND s.clan_id = app_current_clan()
              AND s.revoked_at IS NULL AND s.deleted_at IS NULL
              AND (s.expires_at IS NULL OR s.expires_at > now()))
    END
$$;

-- Chế độ xem hiệu lực của chủ thể hiện tại (GP-DOC-03 mục 4, 5).
CREATE FUNCTION app_effective_policy()
RETURNS TABLE (scope_mode text, root_person_id uuid, depth_down integer, depth_up integer,
               include_spouses boolean, field_groups text[], viewer_person_id uuid)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_role   text := app_principal_role();
    v_clan   uuid := app_current_clan();
    v_member clan_membership%ROWTYPE;
    v_policy view_policy%ROWTYPE;
    v_pid    uuid;
BEGIN
    IF v_role IS NULL THEN
        RETURN;
    END IF;

    IF v_role = 'GUEST' THEN
        SELECT vp.* INTO v_policy
        FROM share_link s JOIN view_policy vp ON vp.id = s.view_policy_id
        WHERE s.id = app_current_share_link();
        RETURN QUERY SELECT v_policy.scope_mode, v_policy.root_person_id, v_policy.depth_down,
                            v_policy.depth_up, v_policy.include_spouses,
                            ARRAY(SELECT g FROM unnest(v_policy.field_groups) g
                                  WHERE g = ANY (gp_link_field_ceiling())),
                            NULL::uuid;
        RETURN;
    END IF;

    SELECT * INTO v_member FROM clan_membership m
    WHERE m.clan_id = v_clan AND m.user_id = app_current_user();

    IF v_role = 'OWNER' THEN
        RETURN QUERY SELECT 'CLAN'::text, NULL::uuid, NULL::integer, NULL::integer, true,
                            gp_all_field_groups(), v_member.person_id;
        RETURN;
    END IF;

    v_pid := CASE WHEN v_role = 'MEMBER'
                  THEN coalesce(v_member.view_policy_id,
                                (SELECT c.default_member_policy_id FROM clan c WHERE c.id = v_clan))
                  ELSE v_member.view_policy_id END;
    IF v_pid IS NOT NULL THEN
        SELECT * INTO v_policy FROM view_policy vp WHERE vp.id = v_pid;
    END IF;

    RETURN QUERY SELECT
        coalesce(v_policy.scope_mode, 'CLAN'),
        v_policy.root_person_id, v_policy.depth_down, v_policy.depth_up,
        coalesce(v_policy.include_spouses, true),
        CASE WHEN v_role = 'EDITOR' THEN array_remove(gp_all_field_groups(), 'IDENTITY_DOCS')
             ELSE coalesce(v_policy.field_groups, ARRAY['BASIC', 'LIFE_EVENTS', 'BIOGRAPHY']) END,
        v_member.person_id;
END;
$$;

-- Nhóm trường mà chủ thể hiện tại được xem; backend dùng để ẩn trường.
CREATE FUNCTION app_visible_field_groups() RETURNS text[]
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$ SELECT coalesce((SELECT field_groups FROM app_effective_policy()), '{}'::text[]) $$;

-- true nếu chủ thể xem được toàn bộ dòng họ. Policy kiểm tra điều này trước
-- tập id, vừa nhanh hơn vừa để INSERT ... RETURNING hoạt động.
CREATE FUNCTION app_has_full_scope() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$ SELECT coalesce((SELECT scope_mode = 'CLAN' FROM app_effective_policy()), false) $$;

-- Bổ sung vợ/chồng của một tập người.
CREATE FUNCTION gp_with_spouses(p_ids uuid[], p_include boolean) RETURNS SETOF uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT x FROM unnest(p_ids) AS x
    UNION
    SELECT u.partner_b_id FROM unnest(p_ids) AS c (x)
    JOIN family_union u ON u.partner_a_id = c.x
    WHERE p_include AND u.partner_b_id IS NOT NULL
    UNION
    SELECT u.partner_a_id FROM unnest(p_ids) AS c (x)
    JOIN family_union u ON u.partner_b_id = c.x
    WHERE p_include AND u.partner_a_id IS NOT NULL
$$;

-- Tập id người mà chủ thể hiện tại được xem.
CREATE FUNCTION app_visible_person_ids() RETURNS SETOF uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_clan uuid := app_current_clan();
    e      record;
    v_core uuid[];
BEGIN
    SELECT * INTO e FROM app_effective_policy();
    IF NOT FOUND THEN
        RETURN;
    END IF;

    IF e.scope_mode = 'CLAN' THEN
        RETURN QUERY SELECT p.id FROM person p WHERE p.clan_id = v_clan;
        RETURN;
    ELSIF e.scope_mode = 'BRANCH' THEN
        v_core := ARRAY(
            SELECT c.descendant_id FROM person_closure c
            WHERE c.ancestor_id = e.root_person_id AND c.depth <= e.depth_down
            UNION
            SELECT c.ancestor_id FROM person_closure c
            WHERE c.descendant_id = e.root_person_id AND c.depth <= e.depth_up);
    ELSIF e.scope_mode = 'RELATIVE' THEN
        IF e.viewer_person_id IS NULL THEN
            RETURN;                    -- chưa gắn hồ sơ: không có phạm vi tương đối
        END IF;
        -- Tổ tiên trong depth_up đời của người xem, và hậu duệ của họ tới depth_down đời dưới thế hệ người xem.
        v_core := ARRAY(
            SELECT d.descendant_id
            FROM person_closure a
            JOIN person_closure d ON d.ancestor_id = a.ancestor_id
            WHERE a.descendant_id = e.viewer_person_id AND a.depth <= e.depth_up
              AND d.depth <= a.depth + e.depth_down);
    ELSE
        RETURN;
    END IF;

    RETURN QUERY SELECT gp_with_spouses(v_core, e.include_spouses);
END;
$$;

CREATE FUNCTION app_my_clan_ids() RETURNS SETOF uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT m.clan_id
    FROM clan_membership m
    JOIN app_user u ON u.id = m.user_id AND u.status = 'ACTIVE'
    WHERE m.user_id = app_current_user()
$$;

-- ---------------------------------------------------------------------
-- Policy
-- ---------------------------------------------------------------------

ALTER TABLE clan                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE person               ENABLE ROW LEVEL SECURITY;
ALTER TABLE family_union         ENABLE ROW LEVEL SECURITY;
ALTER TABLE union_child          ENABLE ROW LEVEL SECURITY;
ALTER TABLE person_closure       ENABLE ROW LEVEL SECURITY;
ALTER TABLE view_policy          ENABLE ROW LEVEL SECURITY;
ALTER TABLE clan_membership      ENABLE ROW LEVEL SECURITY;
ALTER TABLE invitation           ENABLE ROW LEVEL SECURITY;
ALTER TABLE share_link           ENABLE ROW LEVEL SECURITY;
ALTER TABLE person_claim         ENABLE ROW LEVEL SECURITY;
ALTER TABLE ownership_transfer   ENABLE ROW LEVEL SECURITY;
ALTER TABLE transfer_endorsement ENABLE ROW LEVEL SECURITY;
ALTER TABLE clan_subscription    ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_transaction  ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log            ENABLE ROW LEVEL SECURITY;

-- clan: thành viên thấy các dòng họ của mình (kể cả khi bị tạm ngưng); khách thấy dòng họ của link.
CREATE POLICY clan_select ON clan FOR SELECT
    USING (id IN (SELECT app_my_clan_ids())
           OR (id = (SELECT app_current_clan()) AND (SELECT app_principal_role()) = 'GUEST'));
CREATE POLICY clan_update ON clan FOR UPDATE
    USING (id = (SELECT app_current_clan()) AND (SELECT app_principal_role()) = 'OWNER')
    WITH CHECK (id = (SELECT app_current_clan()));

-- person
CREATE POLICY person_select ON person FOR SELECT
    USING (clan_id = (SELECT app_current_clan())
           AND ((SELECT app_has_full_scope()) OR id IN (SELECT app_visible_person_ids())));
CREATE POLICY person_insert ON person FOR INSERT
    WITH CHECK (clan_id = (SELECT app_current_clan())
                AND (SELECT app_principal_role()) IN ('OWNER', 'EDITOR'));
CREATE POLICY person_update ON person FOR UPDATE
    USING (clan_id = (SELECT app_current_clan())
           AND (SELECT app_principal_role()) IN ('OWNER', 'EDITOR')
           AND ((SELECT app_has_full_scope()) OR id IN (SELECT app_visible_person_ids())))
    WITH CHECK (clan_id = (SELECT app_current_clan()));
CREATE POLICY person_delete ON person FOR DELETE
    USING (clan_id = (SELECT app_current_clan()) AND (SELECT app_principal_role()) = 'OWNER');

-- family_union: thấy khi ít nhất một bên trong phạm vi.
CREATE POLICY family_union_select ON family_union FOR SELECT
    USING (clan_id = (SELECT app_current_clan())
           AND ((SELECT app_has_full_scope())
                OR partner_a_id IN (SELECT app_visible_person_ids())
                OR partner_b_id IN (SELECT app_visible_person_ids())));
CREATE POLICY family_union_insert ON family_union FOR INSERT
    WITH CHECK (clan_id = (SELECT app_current_clan())
                AND (SELECT app_principal_role()) IN ('OWNER', 'EDITOR'));
CREATE POLICY family_union_update ON family_union FOR UPDATE
    USING (clan_id = (SELECT app_current_clan()) AND (SELECT app_principal_role()) IN ('OWNER', 'EDITOR'))
    WITH CHECK (clan_id = (SELECT app_current_clan()));
CREATE POLICY family_union_delete ON family_union FOR DELETE
    USING (clan_id = (SELECT app_current_clan()) AND (SELECT app_principal_role()) IN ('OWNER', 'EDITOR'));

-- union_child: thấy khi người con trong phạm vi.
CREATE POLICY union_child_select ON union_child FOR SELECT
    USING (clan_id = (SELECT app_current_clan())
           AND ((SELECT app_has_full_scope()) OR child_id IN (SELECT app_visible_person_ids())));
CREATE POLICY union_child_insert ON union_child FOR INSERT
    WITH CHECK (clan_id = (SELECT app_current_clan())
                AND (SELECT app_principal_role()) IN ('OWNER', 'EDITOR'));
CREATE POLICY union_child_update ON union_child FOR UPDATE
    USING (clan_id = (SELECT app_current_clan()) AND (SELECT app_principal_role()) IN ('OWNER', 'EDITOR'))
    WITH CHECK (clan_id = (SELECT app_current_clan()));
CREATE POLICY union_child_delete ON union_child FOR DELETE
    USING (clan_id = (SELECT app_current_clan()) AND (SELECT app_principal_role()) IN ('OWNER', 'EDITOR'));

-- person_closure: chỉ đọc, các cặp có cả hai đầu trong phạm vi.
CREATE POLICY person_closure_select ON person_closure FOR SELECT
    USING (clan_id = (SELECT app_current_clan())
           AND ((SELECT app_has_full_scope())
                OR (ancestor_id IN (SELECT app_visible_person_ids())
                    AND descendant_id IN (SELECT app_visible_person_ids()))));

-- view_policy, share_link: chỉ OWNER. Link không xóa cứng (xóa mềm bằng deleted_at).
CREATE POLICY view_policy_owner ON view_policy FOR ALL
    USING (clan_id = (SELECT app_current_clan()) AND (SELECT app_principal_role()) = 'OWNER')
    WITH CHECK (clan_id = (SELECT app_current_clan()) AND (SELECT app_principal_role()) = 'OWNER');
CREATE POLICY share_link_owner ON share_link FOR ALL
    USING (clan_id = (SELECT app_current_clan()) AND (SELECT app_principal_role()) = 'OWNER')
    WITH CHECK (clan_id = (SELECT app_current_clan()) AND (SELECT app_principal_role()) = 'OWNER');

-- clan_membership: OWNER xem danh sách; mỗi người xem membership của chính mình.
-- Chỉ OWNER sửa, xóa. Thêm thành viên chỉ qua gp_accept_invitation().
CREATE POLICY clan_membership_select ON clan_membership FOR SELECT
    USING ((clan_id = (SELECT app_current_clan()) AND (SELECT app_principal_role()) = 'OWNER')
           OR user_id = (SELECT app_current_user()));
CREATE POLICY clan_membership_update ON clan_membership FOR UPDATE
    USING (clan_id = (SELECT app_current_clan()) AND (SELECT app_principal_role()) = 'OWNER')
    WITH CHECK (clan_id = (SELECT app_current_clan()));
CREATE POLICY clan_membership_delete ON clan_membership FOR DELETE
    USING (clan_id = (SELECT app_current_clan()) AND (SELECT app_principal_role()) = 'OWNER');

-- invitation: chỉ OWNER. EDITOR chỉ ghi dữ liệu gia phả, không cấp quyền truy cập cho người khác.
CREATE POLICY invitation_owner ON invitation FOR ALL
    USING (clan_id = (SELECT app_current_clan()) AND (SELECT app_principal_role()) = 'OWNER')
    WITH CHECK (clan_id = (SELECT app_current_clan()) AND (SELECT app_principal_role()) = 'OWNER');

-- person_claim: OWNER xem mọi yêu cầu; người dùng xem yêu cầu của mình.
CREATE POLICY person_claim_select ON person_claim FOR SELECT
    USING (clan_id = (SELECT app_current_clan())
           AND ((SELECT app_principal_role()) = 'OWNER' OR user_id = (SELECT app_current_user())));

-- ownership_transfer: OWNER, EDITOR và người liên quan.
CREATE POLICY ownership_transfer_select ON ownership_transfer FOR SELECT
    USING (clan_id = (SELECT app_current_clan())
           AND ((SELECT app_principal_role()) IN ('OWNER', 'EDITOR')
                OR (SELECT app_current_user()) IN (from_user_id, to_user_id, requested_by)));
CREATE POLICY transfer_endorsement_select ON transfer_endorsement FOR SELECT
    USING (clan_id = (SELECT app_current_clan()) AND (SELECT app_principal_role()) IN ('OWNER', 'EDITOR'));

-- Gói, thanh toán, audit: chỉ OWNER.
CREATE POLICY clan_subscription_select ON clan_subscription FOR SELECT
    USING (clan_id = (SELECT app_current_clan()) AND (SELECT app_principal_role()) = 'OWNER');
CREATE POLICY payment_transaction_select ON payment_transaction FOR SELECT
    USING (clan_id = (SELECT app_current_clan()) AND (SELECT app_principal_role()) = 'OWNER');
CREATE POLICY audit_log_select ON audit_log FOR SELECT
    USING (clan_id = (SELECT app_current_clan()) AND (SELECT app_principal_role()) = 'OWNER');

-- ---------------------------------------------------------------------
-- Hàm dùng chung
-- ---------------------------------------------------------------------

CREATE FUNCTION gp_require_role(p_roles text[]) RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_role text := app_principal_role();
BEGIN
    IF v_role IS NULL THEN
        RAISE EXCEPTION 'no principal in clan context' USING ERRCODE = 'GP004';
    END IF;
    IF NOT v_role = ANY (p_roles) THEN
        RAISE EXCEPTION 'role % is not permitted', v_role USING ERRCODE = 'GP005';
    END IF;
    RETURN v_role;
END;
$$;

CREATE FUNCTION gp_require_system_role(p_roles text[]) RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_role text := app_current_system_role();
BEGIN
    IF v_role IS NULL OR NOT v_role = ANY (p_roles) THEN
        RAISE EXCEPTION 'system role required' USING ERRCODE = 'GP005';
    END IF;
    RETURN app_current_user();
END;
$$;

CREATE FUNCTION gp_audit(
    p_action text, p_entity_type text, p_entity_id uuid,
    p_detail jsonb DEFAULT '{}'::jsonb, p_ip inet DEFAULT NULL, p_user_agent text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_role text := app_principal_role();
BEGIN
    IF v_role IS NULL THEN
        RAISE EXCEPTION 'no principal in clan context' USING ERRCODE = 'GP004';
    END IF;
    -- Người thực hiện lấy từ ngữ cảnh phiên, không lấy từ tham số: không giả mạo được.
    INSERT INTO audit_log (clan_id, actor_user_id, actor_share_link_id, action,
                           entity_type, entity_id, detail, ip, user_agent)
    VALUES (app_current_clan(),
            CASE WHEN v_role = 'GUEST' THEN NULL ELSE app_current_user() END,
            CASE WHEN v_role = 'GUEST' THEN app_current_share_link() END,
            p_action, p_entity_type, p_entity_id, coalesce(p_detail, '{}'::jsonb),
            p_ip, left(p_user_agent, 500));
END;
$$;

-- Ghi nhận hoạt động của người dùng hiện tại (gọi khi đăng nhập và làm mới phiên).
CREATE FUNCTION gp_touch_activity() RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp
AS $$ UPDATE app_user SET last_active_at = now() WHERE id = app_current_user() $$;

-- ---------------------------------------------------------------------
-- Dòng họ, lời mời, link khách
-- ---------------------------------------------------------------------

CREATE FUNCTION gp_create_clan(p_name text, p_description text DEFAULT NULL, p_origin_place text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_user   uuid := app_current_user();
    v_user_r app_user%ROWTYPE;
    v_clan   uuid;
    v_policy uuid;
BEGIN
    SELECT * INTO v_user_r FROM app_user WHERE id = v_user AND status = 'ACTIVE';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'authentication required' USING ERRCODE = 'GP004';
    END IF;
    IF v_user_r.email_verified_at IS NULL THEN
        RAISE EXCEPTION 'email not verified' USING ERRCODE = 'GP007';
    END IF;

    INSERT INTO clan (name, description, origin_place, created_by)
    VALUES (p_name, p_description, p_origin_place, v_user)
    RETURNING id INTO v_clan;

    INSERT INTO view_policy (clan_id, name, scope_mode, field_groups, created_by)
    VALUES (v_clan, 'Mặc định cho thành viên', 'CLAN', ARRAY['BASIC', 'LIFE_EVENTS', 'BIOGRAPHY'], v_user)
    RETURNING id INTO v_policy;
    UPDATE clan SET default_member_policy_id = v_policy WHERE id = v_clan;

    INSERT INTO clan_membership (clan_id, user_id, role, created_by) VALUES (v_clan, v_user, 'OWNER', v_user);
    INSERT INTO clan_subscription (clan_id, plan_code) VALUES (v_clan, 'FREE');
    INSERT INTO audit_log (clan_id, actor_user_id, action, entity_type, entity_id)
    VALUES (v_clan, v_user, 'CLAN_CREATE', 'clan', v_clan);
    RETURN v_clan;
END;
$$;

-- p_token_hash = SHA-256 của token trong link mời.
CREATE FUNCTION gp_accept_invitation(p_token_hash bytea) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_user   uuid := app_current_user();
    v_user_r app_user%ROWTYPE;
    v_inv    invitation%ROWTYPE;
BEGIN
    SELECT * INTO v_user_r FROM app_user WHERE id = v_user AND status = 'ACTIVE';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'authentication required' USING ERRCODE = 'GP004';
    END IF;
    IF v_user_r.email_verified_at IS NULL THEN
        RAISE EXCEPTION 'email not verified' USING ERRCODE = 'GP007';
    END IF;

    SELECT * INTO v_inv FROM invitation WHERE token_hash = p_token_hash FOR UPDATE;
    IF NOT FOUND OR v_inv.accepted_at IS NOT NULL OR v_inv.revoked_at IS NOT NULL
       OR v_inv.expires_at <= now()
       OR NOT EXISTS (SELECT 1 FROM clan WHERE id = v_inv.clan_id AND status = 'ACTIVE') THEN
        -- Cùng một lỗi cho mọi trường hợp: không cho đoán trạng thái lời mời.
        RAISE EXCEPTION 'invalid invitation' USING ERRCODE = 'GP001';
    END IF;
    IF v_inv.email <> v_user_r.email THEN
        RAISE EXCEPTION 'invitation was issued to another email' USING ERRCODE = 'GP002';
    END IF;
    IF EXISTS (SELECT 1 FROM clan_membership WHERE clan_id = v_inv.clan_id AND user_id = v_user) THEN
        RAISE EXCEPTION 'already a member' USING ERRCODE = 'GP003';
    END IF;
    IF v_inv.person_id IS NOT NULL AND EXISTS (
           SELECT 1 FROM clan_membership WHERE clan_id = v_inv.clan_id AND person_id = v_inv.person_id) THEN
        RAISE EXCEPTION 'person is already linked to another account' USING ERRCODE = 'GP006';
    END IF;

    INSERT INTO clan_membership (clan_id, user_id, role, person_id, view_policy_id, created_by)
    VALUES (v_inv.clan_id, v_user, v_inv.role, v_inv.person_id, v_inv.view_policy_id, v_inv.created_by);
    UPDATE invitation SET accepted_at = now(), accepted_by = v_user WHERE id = v_inv.id;
    INSERT INTO audit_log (clan_id, actor_user_id, action, entity_type, entity_id, detail)
    VALUES (v_inv.clan_id, v_user, 'INVITATION_ACCEPT', 'invitation', v_inv.id,
            jsonb_build_object('role', v_inv.role, 'personId', v_inv.person_id));
    RETURN v_inv.clan_id;
END;
$$;

-- Đổi token link chia sẻ lấy thông tin để backend phát hành JWT khách.
CREATE FUNCTION gp_resolve_share_link(p_token_hash bytea)
RETURNS TABLE (link_id uuid, link_clan_id uuid, link_expires_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_link share_link%ROWTYPE;
BEGIN
    SELECT s.* INTO v_link FROM share_link s JOIN clan c ON c.id = s.clan_id AND c.status = 'ACTIVE'
    WHERE s.token_hash = p_token_hash AND s.revoked_at IS NULL AND s.deleted_at IS NULL
      AND (s.expires_at IS NULL OR s.expires_at > now());
    IF NOT FOUND THEN
        RAISE EXCEPTION 'invalid share link' USING ERRCODE = 'GP001';
    END IF;

    UPDATE share_link SET last_used_at = now() WHERE id = v_link.id;
    INSERT INTO audit_log (clan_id, actor_share_link_id, action, entity_type, entity_id)
    VALUES (v_link.clan_id, v_link.id, 'GUEST_SESSION_START', 'share_link', v_link.id);

    link_id := v_link.id;
    link_clan_id := v_link.clan_id;
    link_expires_at := v_link.expires_at;
    RETURN NEXT;
END;
$$;

-- Hạn mức và mức sử dụng của dòng họ hiện tại.
CREATE FUNCTION gp_clan_entitlements()
RETURNS TABLE (plan_code text, plan_name text, current_period_end timestamptz,
               max_persons integer, max_members integer, max_share_links integer,
               max_view_policies integer, max_storage_mb integer,
               feature_export_excel boolean, feature_import_excel boolean, feature_kinship boolean,
               audit_retention_days integer,
               used_persons bigint, used_members bigint, used_share_links bigint,
               used_view_policies bigint, used_storage_bytes bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_clan uuid := app_current_clan();
    v_plan plan;
BEGIN
    PERFORM gp_require_role(ARRAY['OWNER', 'EDITOR', 'MEMBER']);
    v_plan := gp_effective_plan(v_clan);
    RETURN QUERY SELECT
        v_plan.code, v_plan.name,
        (SELECT s.current_period_end FROM clan_subscription s
         WHERE s.clan_id = v_clan AND s.plan_code = v_plan.code),
        v_plan.max_persons, v_plan.max_members, v_plan.max_share_links,
        v_plan.max_view_policies, v_plan.max_storage_mb,
        v_plan.feature_export_excel, v_plan.feature_import_excel, v_plan.feature_kinship,
        v_plan.audit_retention_days,
        (SELECT count(*) FROM person p WHERE p.clan_id = v_clan),
        (SELECT count(*) FROM clan_membership m WHERE m.clan_id = v_clan),
        (SELECT count(*) FROM share_link s WHERE s.clan_id = v_clan AND s.deleted_at IS NULL
           AND s.revoked_at IS NULL AND (s.expires_at IS NULL OR s.expires_at > now())),
        (SELECT count(*) FROM view_policy v WHERE v.clan_id = v_clan),
        (SELECT coalesce(sum(p.photo_size_bytes), 0)::bigint FROM person p WHERE p.clan_id = v_clan);
END;
$$;

-- ---------------------------------------------------------------------
-- Gắn tài khoản với hồ sơ gia phả
-- ---------------------------------------------------------------------

-- Người dùng đã gắn hồ sơ tự sửa thông tin liên hệ và cờ hạn chế của hồ sơ mình.
CREATE FUNCTION gp_update_own_profile(
    p_phone text, p_email text, p_current_address text, p_is_restricted boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_person uuid;
BEGIN
    PERFORM gp_require_role(ARRAY['OWNER', 'EDITOR', 'MEMBER']);
    SELECT person_id INTO v_person FROM clan_membership
    WHERE clan_id = app_current_clan() AND user_id = app_current_user();
    IF v_person IS NULL THEN
        RAISE EXCEPTION 'account is not linked to a person' USING ERRCODE = 'GP008';
    END IF;

    UPDATE person
    SET phone = p_phone, email = p_email, current_address = p_current_address,
        is_restricted = coalesce(p_is_restricted, is_restricted), updated_by = app_current_user()
    WHERE id = v_person;
    PERFORM gp_audit('PERSON_SELF_UPDATE', 'person', v_person);
END;
$$;

CREATE FUNCTION gp_claim_person(p_person_id uuid, p_note text DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_clan  uuid := app_current_clan();
    v_user  uuid := app_current_user();
    v_claim uuid;
BEGIN
    PERFORM gp_require_role(ARRAY['OWNER', 'EDITOR', 'MEMBER']);
    IF EXISTS (SELECT 1 FROM clan_membership
               WHERE clan_id = v_clan AND user_id = v_user AND person_id IS NOT NULL) THEN
        RAISE EXCEPTION 'account is already linked to a person' USING ERRCODE = 'GP008';
    END IF;
    IF NOT (app_has_full_scope() OR p_person_id IN (SELECT app_visible_person_ids())) THEN
        RAISE EXCEPTION 'person not found' USING ERRCODE = 'GP009';
    END IF;
    IF EXISTS (SELECT 1 FROM clan_membership WHERE clan_id = v_clan AND person_id = p_person_id) THEN
        RAISE EXCEPTION 'person is already linked to another account' USING ERRCODE = 'GP006';
    END IF;

    INSERT INTO person_claim (clan_id, user_id, person_id, note)
    VALUES (v_clan, v_user, p_person_id, p_note)
    RETURNING id INTO v_claim;
    PERFORM gp_audit('PERSON_CLAIM_CREATE', 'person', p_person_id, jsonb_build_object('claimId', v_claim));
    RETURN v_claim;
END;
$$;

CREATE FUNCTION gp_decide_claim(p_claim_id uuid, p_approve boolean, p_note text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_clan  uuid := app_current_clan();
    v_claim person_claim%ROWTYPE;
BEGIN
    -- Gắn tài khoản với hồ sơ mở quyền xem tương đối và quyền tự sửa hồ sơ: chỉ OWNER quyết định.
    PERFORM gp_require_role(ARRAY['OWNER']);
    SELECT * INTO v_claim FROM person_claim WHERE id = p_claim_id AND clan_id = v_clan FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'claim not found' USING ERRCODE = 'GP009';
    END IF;
    IF v_claim.status <> 'PENDING' THEN
        RAISE EXCEPTION 'claim is not pending' USING ERRCODE = 'GP008';
    END IF;

    IF p_approve THEN
        IF EXISTS (SELECT 1 FROM clan_membership WHERE clan_id = v_clan AND person_id = v_claim.person_id) THEN
            RAISE EXCEPTION 'person is already linked to another account' USING ERRCODE = 'GP006';
        END IF;
        UPDATE clan_membership SET person_id = v_claim.person_id
        WHERE clan_id = v_clan AND user_id = v_claim.user_id AND person_id IS NULL;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'claimant is already linked' USING ERRCODE = 'GP008';
        END IF;
        UPDATE person_claim SET status = 'REJECTED', decided_by = app_current_user(), decided_at = now(),
                                decision_note = 'Hồ sơ đã được gắn với tài khoản khác'
        WHERE clan_id = v_clan AND person_id = v_claim.person_id AND status = 'PENDING' AND id <> v_claim.id;
    END IF;

    UPDATE person_claim
    SET status = CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END,
        decided_by = app_current_user(), decided_at = now(), decision_note = p_note
    WHERE id = v_claim.id;
    PERFORM gp_audit(CASE WHEN p_approve THEN 'PERSON_CLAIM_APPROVE' ELSE 'PERSON_CLAIM_REJECT' END,
                     'person', v_claim.person_id, jsonb_build_object('claimId', v_claim.id, 'userId', v_claim.user_id));
END;
$$;

-- ---------------------------------------------------------------------
-- Trưởng tộc: người kế nhiệm và chuyển giao (GP-DOC-05)
-- ---------------------------------------------------------------------

CREATE FUNCTION gp_owner_of(p_clan_id uuid) RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$ SELECT user_id FROM clan_membership WHERE clan_id = p_clan_id AND role = 'OWNER' $$;

-- Người dùng được coi là không hoạt động khi bị khóa hoặc không hoạt động quá OWNER_INACTIVE_DAYS ngày.
CREATE FUNCTION gp_user_is_inactive(p_user_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT coalesce((SELECT u.status <> 'ACTIVE'
                            OR u.last_active_at < now() - make_interval(days => coalesce(gp_setting('OWNER_INACTIVE_DAYS'), 180))
                     FROM app_user u WHERE u.id = p_user_id), true)
$$;

CREATE FUNCTION gp_swap_owner(p_clan_id uuid, p_from uuid, p_to uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE clan_membership SET role = 'EDITOR', view_policy_id = NULL
    WHERE clan_id = p_clan_id AND user_id = p_from AND role = 'OWNER';
    UPDATE clan_membership SET role = 'OWNER', view_policy_id = NULL
    WHERE clan_id = p_clan_id AND user_id = p_to;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'new owner is no longer a member' USING ERRCODE = 'GP008';
    END IF;
    UPDATE clan SET successor_user_id = NULL WHERE id = p_clan_id AND successor_user_id = p_to;
END;
$$;

CREATE FUNCTION gp_set_successor(p_user_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_clan uuid := app_current_clan();
BEGIN
    PERFORM gp_require_role(ARRAY['OWNER']);
    IF p_user_id IS NOT NULL AND NOT EXISTS (
           SELECT 1 FROM clan_membership WHERE clan_id = v_clan AND user_id = p_user_id AND role <> 'OWNER') THEN
        RAISE EXCEPTION 'successor must be a member other than the owner' USING ERRCODE = 'GP009';
    END IF;
    UPDATE clan SET successor_user_id = p_user_id WHERE id = v_clan;
    PERFORM gp_audit('SUCCESSOR_SET', 'user', p_user_id);
END;
$$;

-- Chuyển giao chủ động. Backend xác thực lại mật khẩu và OTP trước khi gọi.
CREATE FUNCTION gp_transfer_request(p_to_user uuid, p_reason text DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_clan uuid := app_current_clan();
    v_user uuid := app_current_user();
    v_id   uuid;
BEGIN
    PERFORM gp_require_role(ARRAY['OWNER']);
    IF p_to_user = v_user OR NOT EXISTS (
           SELECT 1 FROM clan_membership WHERE clan_id = v_clan AND user_id = p_to_user) THEN
        RAISE EXCEPTION 'recipient must be another member' USING ERRCODE = 'GP009';
    END IF;
    INSERT INTO ownership_transfer (clan_id, kind, from_user_id, to_user_id, requested_by, status, reason, expires_at)
    VALUES (v_clan, 'VOLUNTARY', v_user, p_to_user, v_user, 'PENDING_ACCEPTANCE', p_reason,
            now() + make_interval(days => coalesce(gp_setting('TRANSFER_ACCEPT_DAYS'), 7)))
    RETURNING id INTO v_id;
    PERFORM gp_audit('OWNERSHIP_TRANSFER_REQUEST', 'ownership_transfer', v_id, jsonb_build_object('toUserId', p_to_user));
    RETURN v_id;
END;
$$;

CREATE FUNCTION gp_transfer_accept(p_transfer_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_clan uuid := app_current_clan();
    v_user uuid := app_current_user();
    v_t    ownership_transfer%ROWTYPE;
BEGIN
    PERFORM gp_require_role(ARRAY['EDITOR', 'MEMBER']);
    SELECT * INTO v_t FROM ownership_transfer WHERE id = p_transfer_id AND clan_id = v_clan FOR UPDATE;
    IF NOT FOUND OR v_t.to_user_id <> v_user OR v_t.kind <> 'VOLUNTARY' THEN
        RAISE EXCEPTION 'transfer not found' USING ERRCODE = 'GP009';
    END IF;
    IF v_t.status <> 'PENDING_ACCEPTANCE' OR v_t.expires_at <= now()
       OR gp_owner_of(v_clan) IS DISTINCT FROM v_t.from_user_id THEN
        RAISE EXCEPTION 'transfer cannot be accepted' USING ERRCODE = 'GP008';
    END IF;
    PERFORM gp_swap_owner(v_clan, v_t.from_user_id, v_t.to_user_id);
    UPDATE ownership_transfer SET status = 'COMPLETED', decided_by = v_user, decided_at = now() WHERE id = v_t.id;
    PERFORM gp_audit('OWNERSHIP_TRANSFER_COMPLETE', 'ownership_transfer', v_t.id);
END;
$$;

-- Người tạo yêu cầu hủy yêu cầu của mình.
CREATE FUNCTION gp_transfer_cancel(p_transfer_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_t ownership_transfer%ROWTYPE;
BEGIN
    PERFORM gp_require_role(ARRAY['OWNER', 'EDITOR', 'MEMBER']);
    SELECT * INTO v_t FROM ownership_transfer
    WHERE id = p_transfer_id AND clan_id = app_current_clan() FOR UPDATE;
    IF NOT FOUND OR v_t.requested_by <> app_current_user() THEN
        RAISE EXCEPTION 'transfer not found' USING ERRCODE = 'GP009';
    END IF;
    IF v_t.status NOT IN ('PENDING_ACCEPTANCE', 'PENDING_ENDORSEMENT', 'WAITING_PERIOD', 'PENDING_REVIEW') THEN
        RAISE EXCEPTION 'transfer is not active' USING ERRCODE = 'GP008';
    END IF;
    UPDATE ownership_transfer SET status = 'CANCELED', decided_by = app_current_user(), decided_at = now()
    WHERE id = v_t.id;
    PERFORM gp_audit('OWNERSHIP_TRANSFER_CANCEL', 'ownership_transfer', v_t.id);
END;
$$;

-- Người nhận từ chối chuyển giao chủ động; OWNER từ chối yêu cầu tiếp quản hoặc khôi phục.
CREATE FUNCTION gp_transfer_reject(p_transfer_id uuid, p_note text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_user uuid := app_current_user();
    v_role text := gp_require_role(ARRAY['OWNER', 'EDITOR', 'MEMBER']);
    v_t    ownership_transfer%ROWTYPE;
BEGIN
    SELECT * INTO v_t FROM ownership_transfer
    WHERE id = p_transfer_id AND clan_id = app_current_clan() FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'transfer not found' USING ERRCODE = 'GP009';
    END IF;
    IF NOT ((v_t.kind = 'VOLUNTARY' AND v_t.status = 'PENDING_ACCEPTANCE' AND v_t.to_user_id = v_user)
            OR (v_t.kind IN ('SUCCESSOR', 'RECOVERY') AND v_role = 'OWNER'
                AND v_t.status IN ('PENDING_ENDORSEMENT', 'WAITING_PERIOD', 'PENDING_REVIEW'))) THEN
        RAISE EXCEPTION 'transfer cannot be rejected by this user' USING ERRCODE = 'GP005';
    END IF;
    UPDATE ownership_transfer SET status = 'REJECTED', decided_by = v_user, decided_at = now(), decision_note = p_note
    WHERE id = v_t.id;
    PERFORM gp_audit('OWNERSHIP_TRANSFER_REJECT', 'ownership_transfer', v_t.id);
END;
$$;

-- Người kế nhiệm yêu cầu tiếp quản khi OWNER không hoạt động.
CREATE FUNCTION gp_takeover_request(p_reason text DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_clan  uuid := app_current_clan();
    v_user  uuid := app_current_user();
    v_owner uuid := gp_owner_of(app_current_clan());
    v_id    uuid;
BEGIN
    PERFORM gp_require_role(ARRAY['EDITOR', 'MEMBER']);
    IF NOT EXISTS (SELECT 1 FROM clan WHERE id = v_clan AND successor_user_id = v_user) THEN
        RAISE EXCEPTION 'only the designated successor can request a takeover' USING ERRCODE = 'GP005';
    END IF;
    IF NOT gp_user_is_inactive(v_owner) THEN
        RAISE EXCEPTION 'owner is still active' USING ERRCODE = 'GP008';
    END IF;
    INSERT INTO ownership_transfer (clan_id, kind, from_user_id, to_user_id, requested_by, status, reason, effective_at)
    VALUES (v_clan, 'SUCCESSOR', v_owner, v_user, v_user, 'WAITING_PERIOD', p_reason,
            now() + make_interval(days => coalesce(gp_setting('TAKEOVER_WAIT_DAYS'), 30)))
    RETURNING id INTO v_id;
    PERFORM gp_audit('OWNERSHIP_TAKEOVER_REQUEST', 'ownership_transfer', v_id);
    RETURN v_id;
END;
$$;

-- Chuyển đơn khôi phục sang thời gian chờ khi đủ số xác nhận.
CREATE FUNCTION gp_recovery_check_threshold(p_transfer_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_t      ownership_transfer%ROWTYPE;
    v_needed integer;
    v_have   integer;
BEGIN
    SELECT * INTO v_t FROM ownership_transfer WHERE id = p_transfer_id;
    SELECT ceil(count(*) * 2.0 / 3)::integer INTO v_needed
    FROM clan_membership WHERE clan_id = v_t.clan_id AND role = 'EDITOR';
    SELECT count(*) INTO v_have FROM transfer_endorsement WHERE transfer_id = p_transfer_id;
    IF v_t.status = 'PENDING_ENDORSEMENT' AND v_have >= greatest(v_needed, 1) THEN
        UPDATE ownership_transfer
        SET status = 'WAITING_PERIOD',
            effective_at = now() + make_interval(days => coalesce(gp_setting('TAKEOVER_WAIT_DAYS'), 30))
        WHERE id = p_transfer_id;
    END IF;
END;
$$;

-- EDITOR lập đơn khôi phục khi OWNER không hoạt động và không có người kế nhiệm còn hoạt động.
CREATE FUNCTION gp_recovery_request(p_to_user uuid, p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_clan      uuid := app_current_clan();
    v_user      uuid := app_current_user();
    v_owner     uuid := gp_owner_of(app_current_clan());
    v_successor uuid;
    v_id        uuid;
BEGIN
    PERFORM gp_require_role(ARRAY['EDITOR']);
    SELECT successor_user_id INTO v_successor FROM clan WHERE id = v_clan;
    IF NOT gp_user_is_inactive(v_owner) THEN
        RAISE EXCEPTION 'owner is still active' USING ERRCODE = 'GP008';
    END IF;
    IF v_successor IS NOT NULL AND NOT gp_user_is_inactive(v_successor) THEN
        RAISE EXCEPTION 'an active successor exists' USING ERRCODE = 'GP008';
    END IF;
    IF p_to_user = v_owner OR NOT EXISTS (
           SELECT 1 FROM clan_membership WHERE clan_id = v_clan AND user_id = p_to_user) THEN
        RAISE EXCEPTION 'recipient must be another member' USING ERRCODE = 'GP009';
    END IF;

    INSERT INTO ownership_transfer (clan_id, kind, from_user_id, to_user_id, requested_by, status, reason, expires_at)
    VALUES (v_clan, 'RECOVERY', v_owner, p_to_user, v_user, 'PENDING_ENDORSEMENT', p_reason,
            now() + make_interval(days => coalesce(gp_setting('RECOVERY_ENDORSE_DAYS'), 14)))
    RETURNING id INTO v_id;
    INSERT INTO transfer_endorsement (clan_id, transfer_id, user_id) VALUES (v_clan, v_id, v_user);
    PERFORM gp_recovery_check_threshold(v_id);
    PERFORM gp_audit('OWNERSHIP_RECOVERY_REQUEST', 'ownership_transfer', v_id);
    RETURN v_id;
END;
$$;

CREATE FUNCTION gp_recovery_endorse(p_transfer_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_clan uuid := app_current_clan();
    v_t    ownership_transfer%ROWTYPE;
BEGIN
    PERFORM gp_require_role(ARRAY['EDITOR']);
    SELECT * INTO v_t FROM ownership_transfer WHERE id = p_transfer_id AND clan_id = v_clan FOR UPDATE;
    IF NOT FOUND OR v_t.kind <> 'RECOVERY' THEN
        RAISE EXCEPTION 'transfer not found' USING ERRCODE = 'GP009';
    END IF;
    IF v_t.status <> 'PENDING_ENDORSEMENT' OR v_t.expires_at <= now() THEN
        RAISE EXCEPTION 'recovery is not open for endorsement' USING ERRCODE = 'GP008';
    END IF;
    INSERT INTO transfer_endorsement (clan_id, transfer_id, user_id) VALUES (v_clan, v_t.id, app_current_user());
    PERFORM gp_recovery_check_threshold(v_t.id);
    PERFORM gp_audit('OWNERSHIP_RECOVERY_ENDORSE', 'ownership_transfer', v_t.id);
END;
$$;

-- Tác vụ định kỳ: hết hạn yêu cầu, hoàn tất hoặc chuyển xét duyệt khi hết thời gian chờ.
-- OWNER hoạt động trở lại trong thời gian chờ thì yêu cầu bị từ chối tự động.
CREATE FUNCTION gp_process_due_transfers() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_t     ownership_transfer%ROWTYPE;
    v_count integer := 0;
BEGIN
    FOR v_t IN
        SELECT * FROM ownership_transfer
        WHERE (status IN ('PENDING_ACCEPTANCE', 'PENDING_ENDORSEMENT') AND expires_at <= now())
           OR (status = 'WAITING_PERIOD' AND effective_at <= now())
        FOR UPDATE SKIP LOCKED
    LOOP
        IF v_t.status IN ('PENDING_ACCEPTANCE', 'PENDING_ENDORSEMENT') THEN
            UPDATE ownership_transfer SET status = 'EXPIRED' WHERE id = v_t.id;
        ELSIF EXISTS (SELECT 1 FROM app_user
                      WHERE id = v_t.from_user_id AND status = 'ACTIVE' AND last_active_at > v_t.created_at) THEN
            UPDATE ownership_transfer
            SET status = 'REJECTED', decided_at = now(), decision_note = 'OWNER_ACTIVE'
            WHERE id = v_t.id;
        ELSIF v_t.kind = 'SUCCESSOR' THEN
            PERFORM gp_swap_owner(v_t.clan_id, v_t.from_user_id, v_t.to_user_id);
            UPDATE ownership_transfer SET status = 'COMPLETED', decided_at = now() WHERE id = v_t.id;
            INSERT INTO audit_log (clan_id, actor_user_id, action, entity_type, entity_id, detail)
            VALUES (v_t.clan_id, v_t.requested_by, 'OWNERSHIP_TRANSFER_COMPLETE', 'ownership_transfer', v_t.id,
                    '{"system": true}'::jsonb);
        ELSE
            UPDATE ownership_transfer SET status = 'PENDING_REVIEW' WHERE id = v_t.id;
        END IF;
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END;
$$;

-- ---------------------------------------------------------------------
-- Thanh toán (VNPay). Backend xác minh chữ ký HMAC-SHA512 trước khi gọi.
-- ---------------------------------------------------------------------

CREATE FUNCTION gp_create_payment(p_plan_code text, p_months integer)
RETURNS TABLE (payment_id uuid, txn_ref text, amount_vnd bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_plan plan%ROWTYPE;
    v_id   uuid;
    v_ref  text := replace(gen_random_uuid()::text, '-', '');
BEGIN
    PERFORM gp_require_role(ARRAY['OWNER']);
    SELECT * INTO v_plan FROM plan WHERE code = p_plan_code AND is_purchasable AND price_vnd_per_month > 0;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'plan is not purchasable' USING ERRCODE = 'GP022';
    END IF;
    INSERT INTO payment_transaction (clan_id, plan_code, months, amount_vnd, txn_ref, created_by)
    VALUES (app_current_clan(), v_plan.code, p_months, v_plan.price_vnd_per_month * p_months, v_ref,
            app_current_user())
    RETURNING id INTO v_id;
    PERFORM gp_audit('PAYMENT_CREATE', 'payment', v_id,
                     jsonb_build_object('plan', v_plan.code, 'months', p_months));
    RETURN QUERY SELECT v_id, v_ref, v_plan.price_vnd_per_month * p_months;
END;
$$;

-- Xác nhận kết quả từ IPN. Idempotent: giao dịch đã kết thúc trả về trạng thái hiện tại.
CREATE FUNCTION gp_confirm_payment(
    p_txn_ref text, p_amount_vnd bigint, p_success boolean,
    p_provider_txn_no text DEFAULT NULL, p_payload jsonb DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_t   payment_transaction%ROWTYPE;
    v_sub clan_subscription%ROWTYPE;
BEGIN
    SELECT * INTO v_t FROM payment_transaction WHERE txn_ref = p_txn_ref FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'payment not found' USING ERRCODE = 'GP020';
    END IF;
    IF v_t.status IN ('SUCCEEDED', 'FAILED') THEN
        RETURN v_t.status;
    END IF;
    IF p_amount_vnd IS DISTINCT FROM v_t.amount_vnd THEN
        RAISE EXCEPTION 'amount mismatch' USING ERRCODE = 'GP021';
    END IF;

    IF NOT p_success THEN
        UPDATE payment_transaction
        SET status = 'FAILED', completed_at = now(), provider_txn_no = p_provider_txn_no, provider_payload = p_payload
        WHERE id = v_t.id;
        INSERT INTO audit_log (clan_id, actor_user_id, action, entity_type, entity_id)
        VALUES (v_t.clan_id, v_t.created_by, 'PAYMENT_FAILED', 'payment', v_t.id);
        RETURN 'FAILED';
    END IF;

    UPDATE payment_transaction
    SET status = 'SUCCEEDED', completed_at = now(), provider_txn_no = p_provider_txn_no, provider_payload = p_payload
    WHERE id = v_t.id;

    -- Cùng gói và còn hạn: cộng thêm thời gian. Khác gói hoặc đã hết hạn: bắt đầu kỳ mới.
    SELECT * INTO v_sub FROM clan_subscription WHERE clan_id = v_t.clan_id FOR UPDATE;
    IF FOUND AND v_sub.plan_code = v_t.plan_code AND v_sub.current_period_end > now() THEN
        UPDATE clan_subscription
        SET current_period_end = current_period_end + make_interval(months => v_t.months)
        WHERE clan_id = v_t.clan_id;
    ELSE
        INSERT INTO clan_subscription (clan_id, plan_code, current_period_end)
        VALUES (v_t.clan_id, v_t.plan_code, now() + make_interval(months => v_t.months))
        ON CONFLICT (clan_id) DO UPDATE
        SET plan_code = EXCLUDED.plan_code, current_period_end = EXCLUDED.current_period_end;
    END IF;

    INSERT INTO audit_log (clan_id, actor_user_id, action, entity_type, entity_id, detail)
    VALUES (v_t.clan_id, v_t.created_by, 'PAYMENT_SUCCEEDED', 'payment', v_t.id,
            jsonb_build_object('plan', v_t.plan_code, 'months', v_t.months));
    RETURN 'SUCCEEDED';
END;
$$;

CREATE FUNCTION gp_expire_pending_payments() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_count integer;
BEGIN
    UPDATE payment_transaction SET status = 'EXPIRED', completed_at = now()
    WHERE status = 'PENDING' AND created_at < now() - interval '60 minutes';
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

-- ---------------------------------------------------------------------
-- Quản trị nền tảng. Không hàm nào trả về dữ liệu gia phả.
-- ---------------------------------------------------------------------

CREATE FUNCTION gp_admin_log(p_action text, p_target_type text, p_target_id text, p_detail jsonb)
RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    INSERT INTO admin_audit_log (actor_user_id, action, target_type, target_id, detail)
    VALUES (app_current_user(), p_action, p_target_type, p_target_id, coalesce(p_detail, '{}'::jsonb))
$$;

CREATE FUNCTION gp_admin_list_clans(p_query text DEFAULT NULL, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE (clan_id uuid, name text, status text, owner_user_id uuid, owner_email text,
               owner_last_active_at timestamptz, plan_code text, current_period_end timestamptz,
               person_count bigint, member_count bigint, created_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
BEGIN
    PERFORM gp_require_system_role(ARRAY['SYSTEM_ADMIN', 'SUPPORT']);
    RETURN QUERY
    SELECT c.id, c.name, c.status, u.id, u.email, u.last_active_at,
           (gp_effective_plan(c.id)).code, s.current_period_end,
           (SELECT count(*) FROM person p WHERE p.clan_id = c.id),
           (SELECT count(*) FROM clan_membership m2 WHERE m2.clan_id = c.id),
           c.created_at
    FROM clan c
    LEFT JOIN clan_membership m ON m.clan_id = c.id AND m.role = 'OWNER'
    LEFT JOIN app_user u ON u.id = m.user_id
    LEFT JOIN clan_subscription s ON s.clan_id = c.id
    WHERE p_query IS NULL OR c.name ILIKE '%' || p_query || '%' OR u.email ILIKE '%' || p_query || '%'
    ORDER BY c.created_at DESC
    LIMIT least(greatest(p_limit, 1), 200) OFFSET greatest(p_offset, 0);
END;
$$;

CREATE FUNCTION gp_admin_set_clan_status(p_clan_id uuid, p_status text, p_reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_admin uuid := gp_require_system_role(ARRAY['SYSTEM_ADMIN']);
BEGIN
    UPDATE clan SET status = p_status WHERE id = p_clan_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'clan not found' USING ERRCODE = 'GP009';
    END IF;
    PERFORM gp_admin_log('CLAN_STATUS_SET', 'clan', p_clan_id::text,
                         jsonb_build_object('status', p_status, 'reason', p_reason));
    INSERT INTO audit_log (clan_id, actor_user_id, action, entity_type, entity_id, detail)
    VALUES (p_clan_id, v_admin, 'CLAN_STATUS_SET_BY_ADMIN', 'clan', p_clan_id,
            jsonb_build_object('status', p_status, 'reason', p_reason));
END;
$$;

CREATE FUNCTION gp_admin_set_user_status(p_user_id uuid, p_status text, p_reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_admin uuid := gp_require_system_role(ARRAY['SYSTEM_ADMIN']);
BEGIN
    IF p_user_id = v_admin THEN
        RAISE EXCEPTION 'administrators cannot change their own status' USING ERRCODE = 'GP008';
    END IF;
    UPDATE app_user SET status = p_status WHERE id = p_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'user not found' USING ERRCODE = 'GP009';
    END IF;
    IF p_status = 'LOCKED' THEN
        UPDATE refresh_token SET revoked_at = now() WHERE user_id = p_user_id AND revoked_at IS NULL;
    END IF;
    PERFORM gp_admin_log('USER_STATUS_SET', 'user', p_user_id::text,
                         jsonb_build_object('status', p_status, 'reason', p_reason));
END;
$$;

CREATE FUNCTION gp_admin_grant_subscription(
    p_clan_id uuid, p_plan_code text, p_period_end timestamptz, p_reason text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_admin uuid := gp_require_system_role(ARRAY['SYSTEM_ADMIN']);
BEGIN
    INSERT INTO clan_subscription (clan_id, plan_code, current_period_end)
    VALUES (p_clan_id, p_plan_code, p_period_end)
    ON CONFLICT (clan_id) DO UPDATE
    SET plan_code = EXCLUDED.plan_code, current_period_end = EXCLUDED.current_period_end;
    PERFORM gp_admin_log('SUBSCRIPTION_GRANT', 'clan', p_clan_id::text,
                         jsonb_build_object('plan', p_plan_code, 'periodEnd', p_period_end, 'reason', p_reason));
    INSERT INTO audit_log (clan_id, actor_user_id, action, entity_type, entity_id, detail)
    VALUES (p_clan_id, v_admin, 'SUBSCRIPTION_GRANT_BY_ADMIN', 'clan', p_clan_id,
            jsonb_build_object('plan', p_plan_code, 'periodEnd', p_period_end));
END;
$$;

-- p_plan: đối tượng JSON với các khóa trùng tên cột của bảng plan.
CREATE FUNCTION gp_admin_upsert_plan(p_plan jsonb) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_plan plan := jsonb_populate_record(NULL::plan, p_plan);
BEGIN
    PERFORM gp_require_system_role(ARRAY['SYSTEM_ADMIN']);
    INSERT INTO plan VALUES (v_plan.*)
    ON CONFLICT (code) DO UPDATE SET
        name = EXCLUDED.name, price_vnd_per_month = EXCLUDED.price_vnd_per_month,
        max_persons = EXCLUDED.max_persons, max_members = EXCLUDED.max_members,
        max_share_links = EXCLUDED.max_share_links, max_view_policies = EXCLUDED.max_view_policies,
        max_storage_mb = EXCLUDED.max_storage_mb, feature_export_excel = EXCLUDED.feature_export_excel,
        feature_import_excel = EXCLUDED.feature_import_excel, feature_kinship = EXCLUDED.feature_kinship,
        audit_retention_days = EXCLUDED.audit_retention_days, is_purchasable = EXCLUDED.is_purchasable,
        sort_order = EXCLUDED.sort_order;
    PERFORM gp_admin_log('PLAN_UPSERT', 'plan', v_plan.code, p_plan);
END;
$$;

CREATE FUNCTION gp_admin_set_setting(p_key text, p_value integer) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM gp_require_system_role(ARRAY['SYSTEM_ADMIN']);
    UPDATE system_setting SET value = p_value, updated_at = now() WHERE key = p_key;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'setting not found' USING ERRCODE = 'GP009';
    END IF;
    PERFORM gp_admin_log('SETTING_SET', 'setting', p_key, jsonb_build_object('value', p_value));
END;
$$;

CREATE FUNCTION gp_admin_review_recovery(p_transfer_id uuid, p_approve boolean, p_note text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_admin uuid := gp_require_system_role(ARRAY['SYSTEM_ADMIN', 'SUPPORT']);
    v_t     ownership_transfer%ROWTYPE;
BEGIN
    SELECT * INTO v_t FROM ownership_transfer WHERE id = p_transfer_id FOR UPDATE;
    IF NOT FOUND OR v_t.kind <> 'RECOVERY' THEN
        RAISE EXCEPTION 'transfer not found' USING ERRCODE = 'GP009';
    END IF;
    IF v_t.status <> 'PENDING_REVIEW' THEN
        RAISE EXCEPTION 'transfer is not pending review' USING ERRCODE = 'GP008';
    END IF;
    IF p_approve THEN
        PERFORM gp_swap_owner(v_t.clan_id, v_t.from_user_id, v_t.to_user_id);
    END IF;
    UPDATE ownership_transfer
    SET status = CASE WHEN p_approve THEN 'COMPLETED' ELSE 'REJECTED' END,
        decided_by = v_admin, decided_at = now(), decision_note = p_note
    WHERE id = v_t.id;
    PERFORM gp_admin_log('RECOVERY_REVIEW', 'ownership_transfer', v_t.id::text,
                         jsonb_build_object('approve', p_approve, 'note', p_note));
    INSERT INTO audit_log (clan_id, actor_user_id, action, entity_type, entity_id, detail)
    VALUES (v_t.clan_id, v_admin,
            CASE WHEN p_approve THEN 'OWNERSHIP_TRANSFER_COMPLETE' ELSE 'OWNERSHIP_TRANSFER_REJECT' END,
            'ownership_transfer', v_t.id, jsonb_build_object('reviewedBy', 'SUPPORT'));
END;
$$;

-- Đơn khôi phục chờ SUPPORT duyệt (chỉ siêu dữ liệu, không có dữ liệu gia phả).
CREATE FUNCTION gp_admin_list_pending_reviews()
RETURNS TABLE (transfer_id uuid, clan_id uuid, clan_name text, from_user_email text, to_user_email text,
               requested_by_email text, reason text, endorsement_count bigint, created_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
BEGIN
    PERFORM gp_require_system_role(ARRAY['SYSTEM_ADMIN', 'SUPPORT']);
    RETURN QUERY
    SELECT t.id, t.clan_id, c.name, uf.email, ut.email, ur.email, t.reason,
           (SELECT count(*) FROM transfer_endorsement e WHERE e.transfer_id = t.id), t.created_at
    FROM ownership_transfer t
    JOIN clan c ON c.id = t.clan_id
    JOIN app_user uf ON uf.id = t.from_user_id
    JOIN app_user ut ON ut.id = t.to_user_id
    JOIN app_user ur ON ur.id = t.requested_by
    WHERE t.status = 'PENDING_REVIEW'
    ORDER BY t.created_at;
END;
$$;

CREATE FUNCTION gp_admin_list_audit(p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
RETURNS SETOF admin_audit_log
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM gp_require_system_role(ARRAY['SYSTEM_ADMIN']);
    RETURN QUERY SELECT * FROM admin_audit_log ORDER BY id DESC
                 LIMIT least(greatest(p_limit, 1), 500) OFFSET greatest(p_offset, 0);
END;
$$;

-- ---------------------------------------------------------------------
-- Bảo trì (chỉ gp_owner chạy, qua tác vụ định kỳ của hạ tầng).
-- ---------------------------------------------------------------------

CREATE FUNCTION gp_purge_expired_data() RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_total bigint := 0;
    v_n     bigint;
BEGIN
    DELETE FROM audit_log a USING clan c
    WHERE a.clan_id = c.id
      AND a.created_at < now() - make_interval(days => (gp_effective_plan(c.id)).audit_retention_days);
    GET DIAGNOSTICS v_n = ROW_COUNT; v_total := v_total + v_n;

    DELETE FROM one_time_token WHERE expires_at < now() - interval '7 days';
    GET DIAGNOSTICS v_n = ROW_COUNT; v_total := v_total + v_n;

    DELETE FROM email_outbox WHERE status = 'SENT' AND sent_at < now() - interval '30 days';
    GET DIAGNOSTICS v_n = ROW_COUNT; v_total := v_total + v_n;

    DELETE FROM refresh_token WHERE expires_at < now() - interval '7 days';
    GET DIAGNOSTICS v_n = ROW_COUNT; v_total := v_total + v_n;
    RETURN v_total;
END;
$$;

-- ---------------------------------------------------------------------
-- Quyền của gp_app (đặc quyền tối thiểu)
-- ---------------------------------------------------------------------

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;

GRANT SELECT ON app_user TO gp_app;
GRANT INSERT (id, email, password_hash, display_name) ON app_user TO gp_app;
GRANT UPDATE (password_hash, display_name, email_verified_at) ON app_user TO gp_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON refresh_token, one_time_token TO gp_app;
GRANT SELECT, INSERT, UPDATE ON email_outbox TO gp_app;
GRANT SELECT ON plan, system_setting TO gp_app;

GRANT SELECT ON clan TO gp_app;
GRANT UPDATE (name, description, origin_place, root_person_id, default_member_policy_id, version) ON clan TO gp_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON person, family_union, union_child, view_policy TO gp_app;
GRANT SELECT ON person_closure TO gp_app;
GRANT SELECT, DELETE ON clan_membership TO gp_app;
GRANT UPDATE (role, person_id, view_policy_id, version) ON clan_membership TO gp_app;
GRANT SELECT, INSERT, UPDATE ON invitation, share_link TO gp_app;
GRANT SELECT ON person_claim, ownership_transfer, transfer_endorsement,
                clan_subscription, payment_transaction, audit_log TO gp_app;

-- Hàm SECURITY DEFINER: PUBLIC mặc định có quyền EXECUTE; thu hồi toàn bộ rồi cấp theo danh sách.
DO $$
DECLARE
    f regprocedure;
BEGIN
    FOR f IN SELECT p.oid::regprocedure FROM pg_proc p
             WHERE p.pronamespace = 'public'::regnamespace AND p.prosecdef LOOP
        EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', f);
    END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION
    app_current_system_role(),
    app_principal_role(),
    app_effective_policy(),
    app_visible_field_groups(),
    app_has_full_scope(),
    app_visible_person_ids(),
    app_my_clan_ids(),
    gp_with_spouses(uuid[], boolean),
    gp_audit(text, text, uuid, jsonb, inet, text),
    gp_touch_activity(),
    gp_create_clan(text, text, text),
    gp_accept_invitation(bytea),
    gp_resolve_share_link(bytea),
    gp_clan_entitlements(),
    gp_update_own_profile(text, text, text, boolean),
    gp_claim_person(uuid, text),
    gp_decide_claim(uuid, boolean, text),
    gp_set_successor(uuid),
    gp_transfer_request(uuid, text),
    gp_transfer_accept(uuid),
    gp_transfer_cancel(uuid),
    gp_transfer_reject(uuid, text),
    gp_takeover_request(text),
    gp_recovery_request(uuid, text),
    gp_recovery_endorse(uuid),
    gp_process_due_transfers(),
    gp_create_payment(text, integer),
    gp_confirm_payment(text, bigint, boolean, text, jsonb),
    gp_expire_pending_payments(),
    gp_admin_list_clans(text, integer, integer),
    gp_admin_set_clan_status(uuid, text, text),
    gp_admin_set_user_status(uuid, text, text),
    gp_admin_grant_subscription(uuid, text, timestamptz, text),
    gp_admin_upsert_plan(jsonb),
    gp_admin_set_setting(text, integer),
    gp_admin_review_recovery(uuid, boolean, text),
    gp_admin_list_pending_reviews(),
    gp_admin_list_audit(integer, integer)
TO gp_app;
