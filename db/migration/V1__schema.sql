-- =====================================================================
-- V1 — Lược đồ
-- Mọi bảng thuộc một dòng họ (tenant) có cột clan_id. Tham chiếu giữa các
-- bảng đó dùng khóa ngoại kép (clan_id, id), nhờ đó cơ sở dữ liệu từ chối
-- mọi tham chiếu giữa hai dòng họ khác nhau.
-- Kiểu liệt kê dùng text + CHECK (ánh xạ bằng @Enumerated(EnumType.STRING)).
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ---------------------------------------------------------------------
-- Hàm tiện ích
-- ---------------------------------------------------------------------

-- Khóa tìm kiếm: bỏ dấu tiếng Việt + chữ thường ("Nguyễn Văn Đức" -> "nguyen van duc").
CREATE FUNCTION gp_search_key(p_text text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT
AS $$ SELECT lower(public.unaccent('public.unaccent'::regdictionary, p_text)) $$;

-- Kiểm tra tính hợp lệ của một giá trị ngày theo độ chính xác (GP-DOC-02 mục 5.1).
-- Hàm luôn trả về true hoặc false, không trả về NULL (CHECK chấp nhận NULL).
CREATE FUNCTION gp_valid_partial_date(
    p_precision text, p_year integer, p_month integer, p_day integer,
    p_lunar boolean, p_leap boolean, p_approx boolean)
RETURNS boolean
LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
    IF p_precision IS NULL OR p_lunar IS NULL OR p_leap IS NULL OR p_approx IS NULL THEN
        RETURN false;
    END IF;
    IF p_leap AND NOT p_lunar THEN
        RETURN false;                       -- dương lịch không có tháng nhuận
    END IF;

    IF p_precision = 'UNKNOWN' THEN
        RETURN p_year IS NULL AND p_month IS NULL AND p_day IS NULL AND NOT p_leap AND NOT p_approx;
    END IF;

    IF p_year IS NULL OR p_year NOT BETWEEN 1 AND 9999 THEN
        RETURN false;
    END IF;

    IF p_precision = 'YEAR' THEN
        RETURN p_month IS NULL AND p_day IS NULL AND NOT p_leap;
    END IF;

    IF p_month IS NULL OR p_month NOT BETWEEN 1 AND 12 THEN
        RETURN false;
    END IF;

    IF p_precision = 'MONTH' THEN
        RETURN p_day IS NULL;
    END IF;

    IF p_precision = 'DAY' THEN
        IF p_day IS NULL THEN
            RETURN false;
        END IF;
        IF p_lunar THEN
            RETURN p_day BETWEEN 1 AND 30;  -- độ dài tháng âm (29/30 ngày) do tầng ứng dụng kiểm tra
        END IF;
        RETURN p_day BETWEEN 1 AND
            extract(day FROM make_date(p_year, p_month, 1) + interval '1 month - 1 day')::integer;
    END IF;

    RETURN false;
END;
$$;

CREATE FUNCTION gp_touch_updated_at() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE FUNCTION gp_forbid_clan_change() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.clan_id IS DISTINCT FROM OLD.clan_id THEN
        RAISE EXCEPTION 'clan_id is immutable on %', TG_TABLE_NAME
            USING ERRCODE = 'check_violation', CONSTRAINT = 'clan_id_immutable';
    END IF;
    RETURN NEW;
END;
$$;


-- Nhóm trường thông tin (GP-DOC-03 mục 4).
CREATE FUNCTION gp_all_field_groups() RETURNS text[]
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$ SELECT ARRAY['BASIC', 'LIFE_EVENTS', 'BIOGRAPHY', 'LIVING_BIRTH_DATE', 'CONTACT', 'ADOPTION', 'IDENTITY_DOCS'] $$;

-- Các nhóm được phép cấu hình trong chế độ xem (IDENTITY_DOCS chỉ dành cho OWNER).
CREATE FUNCTION gp_policy_field_groups() RETURNS text[]
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$ SELECT ARRAY['BASIC', 'LIFE_EVENTS', 'BIOGRAPHY', 'LIVING_BIRTH_DATE', 'CONTACT', 'ADOPTION'] $$;

-- Trần an toàn của link chia sẻ công khai.
CREATE FUNCTION gp_link_field_ceiling() RETURNS text[]
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$ SELECT ARRAY['BASIC', 'LIFE_EVENTS', 'BIOGRAPHY'] $$;

-- ---------------------------------------------------------------------
-- Cấu hình hệ thống
-- ---------------------------------------------------------------------

CREATE TABLE system_setting (
    key         text        PRIMARY KEY CHECK (key ~ '^[A-Z][A-Z0-9_]{1,63}$'),
    value       integer     NOT NULL CHECK (value >= 0),
    description text        NOT NULL,
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE FUNCTION gp_setting(p_key text) RETURNS integer
LANGUAGE sql STABLE
AS $$ SELECT value FROM system_setting WHERE key = p_key $$;

-- ---------------------------------------------------------------------
-- Người dùng, phiên, token dùng một lần, hàng đợi email (toàn cục)
-- ---------------------------------------------------------------------

CREATE TABLE app_user (
    id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    email             text        NOT NULL UNIQUE
                                  CHECK (email = lower(email) AND length(email) BETWEEN 3 AND 254),
    password_hash     text        NOT NULL,
    display_name      text        NOT NULL CHECK (length(display_name) BETWEEN 1 AND 100),
    status            text        NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'LOCKED')),
    system_role       text        CHECK (system_role IN ('SYSTEM_ADMIN', 'SUPPORT')),
    email_verified_at timestamptz,
    last_active_at    timestamptz NOT NULL DEFAULT now(),
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE refresh_token (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid        NOT NULL REFERENCES app_user (id) ON DELETE CASCADE,
    token_hash  bytea       NOT NULL UNIQUE CHECK (length(token_hash) = 32),   -- SHA-256
    expires_at  timestamptz NOT NULL,
    revoked_at  timestamptz,
    replaced_by uuid        REFERENCES refresh_token (id),
    user_agent  text        CHECK (length(user_agent) <= 500),
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX refresh_token_user_idx ON refresh_token (user_id);

-- Token xác minh email, đặt lại mật khẩu, OTP xác thực bổ sung.
CREATE TABLE one_time_token (
    id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    uuid        NOT NULL REFERENCES app_user (id) ON DELETE CASCADE,
    purpose    text        NOT NULL CHECK (purpose IN ('EMAIL_VERIFY', 'PASSWORD_RESET', 'STEP_UP_OTP')),
    token_hash bytea       NOT NULL UNIQUE CHECK (length(token_hash) = 32),
    context    jsonb       NOT NULL DEFAULT '{}'::jsonb,
    attempts   integer     NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    expires_at timestamptz NOT NULL,
    used_at    timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX one_time_token_user_idx ON one_time_token (user_id, purpose);

-- Hàng đợi email (outbox): ghi cùng transaction nghiệp vụ, tiến trình nền gửi đi.
CREATE TABLE email_outbox (
    id              bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    to_email        text        NOT NULL CHECK (length(to_email) BETWEEN 3 AND 254),
    template        text        NOT NULL CHECK (template ~ '^[A-Z_]{1,64}$'),
    payload         jsonb       NOT NULL DEFAULT '{}'::jsonb,
    status          text        NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'SENT', 'FAILED')),
    attempts        integer     NOT NULL DEFAULT 0,
    next_attempt_at timestamptz NOT NULL DEFAULT now(),
    last_error      text        CHECK (length(last_error) <= 2000),
    created_at      timestamptz NOT NULL DEFAULT now(),
    sent_at         timestamptz
);
CREATE INDEX email_outbox_pending_idx ON email_outbox (next_attempt_at) WHERE status = 'PENDING';

-- Nhật ký thao tác quản trị nền tảng (không thuộc dòng họ).
CREATE TABLE admin_audit_log (
    id            bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    actor_user_id uuid        REFERENCES app_user (id),
    action        text        NOT NULL CHECK (action ~ '^[A-Z_]{1,64}$'),
    target_type   text        CHECK (length(target_type) <= 64),
    target_id     text        CHECK (length(target_id) <= 100),
    detail        jsonb       NOT NULL DEFAULT '{}'::jsonb,
    created_at    timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Gói dịch vụ
-- ---------------------------------------------------------------------

CREATE TABLE plan (
    code                 text        PRIMARY KEY CHECK (code ~ '^[A-Z][A-Z0-9_]{1,31}$'),
    name                 text        NOT NULL CHECK (length(name) BETWEEN 1 AND 100),
    price_vnd_per_month  bigint      NOT NULL CHECK (price_vnd_per_month >= 0),
    max_persons          integer     NOT NULL CHECK (max_persons > 0),
    max_members          integer     NOT NULL CHECK (max_members > 0),
    max_share_links      integer     NOT NULL CHECK (max_share_links >= 0),
    max_view_policies    integer     NOT NULL CHECK (max_view_policies >= 1),
    max_storage_mb       integer     NOT NULL CHECK (max_storage_mb >= 0),
    feature_export_excel boolean     NOT NULL DEFAULT false,
    feature_import_excel boolean     NOT NULL DEFAULT false,
    feature_kinship      boolean     NOT NULL DEFAULT false,
    audit_retention_days integer     NOT NULL CHECK (audit_retention_days > 0),
    is_purchasable       boolean     NOT NULL DEFAULT true,
    sort_order           integer     NOT NULL DEFAULT 0,
    updated_at           timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Dòng họ (tenant)
-- ---------------------------------------------------------------------

CREATE TABLE clan (
    id                       uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    name                     text        NOT NULL CHECK (length(name) BETWEEN 1 AND 200),
    description              text        CHECK (length(description) <= 5000),
    origin_place             text        CHECK (length(origin_place) <= 500),
    root_person_id           uuid,       -- thủy tổ
    default_member_policy_id uuid,       -- chế độ xem mặc định của MEMBER
    successor_user_id        uuid,       -- người kế nhiệm do OWNER chỉ định
    status                   text        NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'SUSPENDED')),
    data_version             bigint      NOT NULL DEFAULT 0,   -- tăng khi dữ liệu gia phả thay đổi (khóa cache)
    created_by               uuid        NOT NULL REFERENCES app_user (id),
    created_at               timestamptz NOT NULL DEFAULT now(),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    version                  integer     NOT NULL DEFAULT 0
);

-- ---------------------------------------------------------------------
-- Người
-- ---------------------------------------------------------------------

CREATE TABLE person (
    id                    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    clan_id               uuid        NOT NULL REFERENCES clan (id),
    full_name             text        NOT NULL CHECK (length(full_name) BETWEEN 1 AND 200),
    other_names           text        CHECK (length(other_names) <= 500),   -- tên tự, hiệu, húy
    gender                text        NOT NULL DEFAULT 'UNKNOWN'
                                      CHECK (gender IN ('MALE', 'FEMALE', 'UNKNOWN')),
    is_living             boolean     NOT NULL DEFAULT true,   -- mặc định còn sống: áp dụng mức bảo vệ cao nhất
    is_restricted         boolean     NOT NULL DEFAULT false,

    birth_solar_precision text        NOT NULL DEFAULT 'UNKNOWN',
    birth_solar_year      integer,
    birth_solar_month     integer,
    birth_solar_day       integer,
    birth_solar_approx    boolean     NOT NULL DEFAULT false,
    birth_lunar_precision text        NOT NULL DEFAULT 'UNKNOWN',
    birth_lunar_year      integer,
    birth_lunar_month     integer,
    birth_lunar_day       integer,
    birth_lunar_leap      boolean     NOT NULL DEFAULT false,
    birth_lunar_approx    boolean     NOT NULL DEFAULT false,

    death_solar_precision text        NOT NULL DEFAULT 'UNKNOWN',
    death_solar_year      integer,
    death_solar_month     integer,
    death_solar_day       integer,
    death_solar_approx    boolean     NOT NULL DEFAULT false,
    death_lunar_precision text        NOT NULL DEFAULT 'UNKNOWN',
    death_lunar_year      integer,
    death_lunar_month     integer,
    death_lunar_day       integer,
    death_lunar_leap      boolean     NOT NULL DEFAULT false,
    death_lunar_approx    boolean     NOT NULL DEFAULT false,

    birth_place           text        CHECK (length(birth_place) <= 500),
    burial_place          text        CHECK (length(burial_place) <= 500),
    occupation            text        CHECK (length(occupation) <= 200),
    biography             text        CHECK (length(biography) <= 20000),
    current_address       text        CHECK (length(current_address) <= 500),
    phone                 text        CHECK (length(phone) <= 30),
    email                 text        CHECK (length(email) <= 254),
    national_id           text        CHECK (length(national_id) <= 20),
    private_note          text        CHECK (length(private_note) <= 5000),
    photo_object_key      text        CHECK (length(photo_object_key) <= 300),
    photo_size_bytes      bigint      NOT NULL DEFAULT 0 CHECK (photo_size_bytes >= 0),

    created_by            uuid        REFERENCES app_user (id),
    updated_by            uuid        REFERENCES app_user (id),
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    version               integer     NOT NULL DEFAULT 0,

    CONSTRAINT person_clan_id_uk UNIQUE (clan_id, id),
    CONSTRAINT person_birth_solar_ck CHECK (gp_valid_partial_date(
        birth_solar_precision, birth_solar_year, birth_solar_month, birth_solar_day,
        false, false, birth_solar_approx)),
    CONSTRAINT person_birth_lunar_ck CHECK (gp_valid_partial_date(
        birth_lunar_precision, birth_lunar_year, birth_lunar_month, birth_lunar_day,
        true, birth_lunar_leap, birth_lunar_approx)),
    CONSTRAINT person_death_solar_ck CHECK (gp_valid_partial_date(
        death_solar_precision, death_solar_year, death_solar_month, death_solar_day,
        false, false, death_solar_approx)),
    CONSTRAINT person_death_lunar_ck CHECK (gp_valid_partial_date(
        death_lunar_precision, death_lunar_year, death_lunar_month, death_lunar_day,
        true, death_lunar_leap, death_lunar_approx)),
    CONSTRAINT person_living_no_death_ck CHECK (
        NOT is_living OR (death_solar_precision = 'UNKNOWN' AND death_lunar_precision = 'UNKNOWN'))
);
CREATE INDEX person_clan_idx ON person (clan_id);
CREATE INDEX person_search_idx ON person USING gin (gp_search_key(full_name) gin_trgm_ops);

ALTER TABLE clan
    ADD CONSTRAINT clan_root_person_fk FOREIGN KEY (id, root_person_id) REFERENCES person (clan_id, id);

-- ---------------------------------------------------------------------
-- Quan hệ: hôn phối (family_union) và con của hôn phối (union_child)
-- Một hôn phối có 1 hoặc 2 người; con gắn vào hôn phối, không gắn vào từng người.
-- ---------------------------------------------------------------------

CREATE TABLE family_union (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    clan_id         uuid        NOT NULL REFERENCES clan (id),
    partner_a_id    uuid,
    partner_b_id    uuid,
    partner_a_order integer     CHECK (partner_a_order > 0),   -- đây là hôn phối thứ mấy của A
    partner_b_order integer     CHECK (partner_b_order > 0),
    status          text        NOT NULL DEFAULT 'MARRIED'
                                CHECK (status IN ('MARRIED', 'DIVORCED', 'WIDOWED', 'UNKNOWN')),
    note            text        CHECK (length(note) <= 1000),
    created_by      uuid        REFERENCES app_user (id),
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    version         integer     NOT NULL DEFAULT 0,

    CONSTRAINT family_union_clan_id_uk UNIQUE (clan_id, id),
    CONSTRAINT family_union_partner_a_fk FOREIGN KEY (clan_id, partner_a_id) REFERENCES person (clan_id, id),
    CONSTRAINT family_union_partner_b_fk FOREIGN KEY (clan_id, partner_b_id) REFERENCES person (clan_id, id),
    CONSTRAINT family_union_has_partner_ck CHECK (partner_a_id IS NOT NULL OR partner_b_id IS NOT NULL),
    CONSTRAINT family_union_distinct_partners_ck CHECK (partner_a_id <> partner_b_id)
);
CREATE UNIQUE INDEX family_union_pair_uk ON family_union
    (clan_id, least(partner_a_id, partner_b_id), greatest(partner_a_id, partner_b_id))
    WHERE partner_a_id IS NOT NULL AND partner_b_id IS NOT NULL;
CREATE INDEX family_union_partner_a_idx ON family_union (partner_a_id);
CREATE INDEX family_union_partner_b_idx ON family_union (partner_b_id);

CREATE TABLE union_child (
    clan_id     uuid        NOT NULL,
    union_id    uuid        NOT NULL,
    child_id    uuid        NOT NULL,
    relation    text        NOT NULL DEFAULT 'BIOLOGICAL' CHECK (relation IN ('BIOLOGICAL', 'ADOPTED')),
    birth_order integer     CHECK (birth_order > 0),           -- con thứ mấy
    created_by  uuid        REFERENCES app_user (id),
    created_at  timestamptz NOT NULL DEFAULT now(),

    PRIMARY KEY (union_id, child_id),
    CONSTRAINT union_child_union_fk FOREIGN KEY (clan_id, union_id) REFERENCES family_union (clan_id, id),
    CONSTRAINT union_child_child_fk FOREIGN KEY (clan_id, child_id) REFERENCES person (clan_id, id)
);
-- Tối đa một gia đình đẻ cho mỗi người; gia đình nuôi thì không giới hạn.
CREATE UNIQUE INDEX union_child_one_biological_uk ON union_child (child_id) WHERE relation = 'BIOLOGICAL';
CREATE INDEX union_child_child_idx ON union_child (child_id);

-- ---------------------------------------------------------------------
-- Closure table: mọi cặp (tổ tiên, hậu duệ) cùng số đời ngắn nhất.
-- Chỉ được ghi bởi trigger (SECURITY DEFINER); ứng dụng chỉ đọc.
-- ---------------------------------------------------------------------

CREATE TABLE person_closure (
    clan_id       uuid    NOT NULL,
    ancestor_id   uuid    NOT NULL,
    descendant_id uuid    NOT NULL,
    depth         integer NOT NULL CHECK (depth >= 0),

    PRIMARY KEY (ancestor_id, descendant_id),
    CONSTRAINT person_closure_ancestor_fk FOREIGN KEY (clan_id, ancestor_id)
        REFERENCES person (clan_id, id) ON DELETE CASCADE,
    CONSTRAINT person_closure_descendant_fk FOREIGN KEY (clan_id, descendant_id)
        REFERENCES person (clan_id, id) ON DELETE CASCADE
);
CREATE INDEX person_closure_descendant_idx ON person_closure (descendant_id, depth);
CREATE INDEX person_closure_clan_idx ON person_closure (clan_id);

CREATE FUNCTION gp_rebuild_person_closure(p_clan_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_cycle boolean;
BEGIN
    -- Tuần tự hóa các lần dựng lại của cùng một dòng họ.
    PERFORM pg_advisory_xact_lock(hashtextextended('person_closure:' || p_clan_id::text, 0));

    DELETE FROM person_closure WHERE clan_id = p_clan_id;

    WITH RECURSIVE edge AS (
        SELECT p.parent_id, uc.child_id
        FROM union_child uc
        JOIN family_union u ON u.id = uc.union_id
        CROSS JOIN LATERAL (VALUES (u.partner_a_id), (u.partner_b_id)) AS p (parent_id)
        WHERE uc.clan_id = p_clan_id AND p.parent_id IS NOT NULL
    ),
    walk (ancestor_id, descendant_id, depth) AS (
        SELECT id, id, 0 FROM person WHERE clan_id = p_clan_id
        UNION ALL
        SELECT w.ancestor_id, e.child_id, w.depth + 1
        FROM walk w
        JOIN edge e ON e.parent_id = w.descendant_id
    ) CYCLE descendant_id SET is_cycle USING path,
    inserted AS (
        INSERT INTO person_closure (clan_id, ancestor_id, descendant_id, depth)
        SELECT p_clan_id, ancestor_id, descendant_id, min(depth)
        FROM walk
        WHERE NOT is_cycle
        GROUP BY ancestor_id, descendant_id
        RETURNING 1
    )
    SELECT coalesce(bool_or(is_cycle), false) INTO v_cycle FROM walk;

    IF v_cycle THEN
        RAISE EXCEPTION 'relationship would make a person their own ancestor'
            USING ERRCODE = 'check_violation', CONSTRAINT = 'person_no_ancestry_cycle';
    END IF;
END;
$$;

CREATE FUNCTION gp_person_closure_self_trg() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    INSERT INTO person_closure (clan_id, ancestor_id, descendant_id, depth)
    VALUES (NEW.clan_id, NEW.id, NEW.id, 0);
    RETURN NULL;
END;
$$;

CREATE FUNCTION gp_union_child_closure_trg() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_clan uuid;
BEGIN
    FOR v_clan IN SELECT DISTINCT clan_id FROM changed_rows LOOP
        PERFORM gp_rebuild_person_closure(v_clan);
    END LOOP;
    RETURN NULL;
END;
$$;

CREATE FUNCTION gp_family_union_closure_trg() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM gp_rebuild_person_closure(NEW.clan_id);
    RETURN NULL;
END;
$$;

CREATE TRIGGER person_closure_self AFTER INSERT ON person
    FOR EACH ROW EXECUTE FUNCTION gp_person_closure_self_trg();

-- PostgreSQL không cho phép bảng chuyển tiếp trên trigger nhiều sự kiện; mỗi sự kiện dùng một trigger.
CREATE TRIGGER union_child_closure_ins AFTER INSERT ON union_child
    REFERENCING NEW TABLE AS changed_rows
    FOR EACH STATEMENT EXECUTE FUNCTION gp_union_child_closure_trg();
CREATE TRIGGER union_child_closure_upd AFTER UPDATE ON union_child
    REFERENCING NEW TABLE AS changed_rows
    FOR EACH STATEMENT EXECUTE FUNCTION gp_union_child_closure_trg();
CREATE TRIGGER union_child_closure_del AFTER DELETE ON union_child
    REFERENCING OLD TABLE AS changed_rows
    FOR EACH STATEMENT EXECUTE FUNCTION gp_union_child_closure_trg();

CREATE TRIGGER family_union_closure_upd AFTER UPDATE OF partner_a_id, partner_b_id ON family_union
    FOR EACH ROW
    WHEN (OLD.partner_a_id IS DISTINCT FROM NEW.partner_a_id
          OR OLD.partner_b_id IS DISTINCT FROM NEW.partner_b_id)
    EXECUTE FUNCTION gp_family_union_closure_trg();

-- ---------------------------------------------------------------------
-- Phiên bản dữ liệu gia phả (khóa cache): tăng khi person, family_union,
-- union_child thay đổi.
-- ---------------------------------------------------------------------

CREATE FUNCTION gp_bump_data_version_trg() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE clan SET data_version = data_version + 1
    WHERE id IN (SELECT DISTINCT clan_id FROM changed_rows);
    RETURN NULL;
END;
$$;

CREATE TRIGGER person_data_version_ins AFTER INSERT ON person
    REFERENCING NEW TABLE AS changed_rows FOR EACH STATEMENT EXECUTE FUNCTION gp_bump_data_version_trg();
CREATE TRIGGER person_data_version_upd AFTER UPDATE ON person
    REFERENCING NEW TABLE AS changed_rows FOR EACH STATEMENT EXECUTE FUNCTION gp_bump_data_version_trg();
CREATE TRIGGER person_data_version_del AFTER DELETE ON person
    REFERENCING OLD TABLE AS changed_rows FOR EACH STATEMENT EXECUTE FUNCTION gp_bump_data_version_trg();
CREATE TRIGGER family_union_data_version_ins AFTER INSERT ON family_union
    REFERENCING NEW TABLE AS changed_rows FOR EACH STATEMENT EXECUTE FUNCTION gp_bump_data_version_trg();
CREATE TRIGGER family_union_data_version_upd AFTER UPDATE ON family_union
    REFERENCING NEW TABLE AS changed_rows FOR EACH STATEMENT EXECUTE FUNCTION gp_bump_data_version_trg();
CREATE TRIGGER family_union_data_version_del AFTER DELETE ON family_union
    REFERENCING OLD TABLE AS changed_rows FOR EACH STATEMENT EXECUTE FUNCTION gp_bump_data_version_trg();
CREATE TRIGGER union_child_data_version_ins AFTER INSERT ON union_child
    REFERENCING NEW TABLE AS changed_rows FOR EACH STATEMENT EXECUTE FUNCTION gp_bump_data_version_trg();
CREATE TRIGGER union_child_data_version_upd AFTER UPDATE ON union_child
    REFERENCING NEW TABLE AS changed_rows FOR EACH STATEMENT EXECUTE FUNCTION gp_bump_data_version_trg();
CREATE TRIGGER union_child_data_version_del AFTER DELETE ON union_child
    REFERENCING OLD TABLE AS changed_rows FOR EACH STATEMENT EXECUTE FUNCTION gp_bump_data_version_trg();

-- ---------------------------------------------------------------------
-- Chế độ xem (view policy): phạm vi + nhóm trường.
--   CLAN:     toàn bộ dòng họ
--   BRANCH:   từ người gốc cố định, depth_down đời xuống, depth_up đời lên
--   RELATIVE: từ hồ sơ của chính người xem, depth_up đời lên, depth_down đời xuống
-- ---------------------------------------------------------------------

CREATE TABLE view_policy (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    clan_id         uuid        NOT NULL REFERENCES clan (id),
    name            text        NOT NULL CHECK (length(name) BETWEEN 1 AND 100),
    scope_mode      text        NOT NULL CHECK (scope_mode IN ('CLAN', 'BRANCH', 'RELATIVE')),
    root_person_id  uuid,
    depth_down      integer,
    depth_up        integer,
    include_spouses boolean     NOT NULL DEFAULT true,
    field_groups    text[]      NOT NULL DEFAULT ARRAY['BASIC', 'LIFE_EVENTS', 'BIOGRAPHY'],
    created_by      uuid        REFERENCES app_user (id),
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    version         integer     NOT NULL DEFAULT 0,

    CONSTRAINT view_policy_clan_id_uk UNIQUE (clan_id, id),
    CONSTRAINT view_policy_name_uk UNIQUE (clan_id, name),
    CONSTRAINT view_policy_root_fk FOREIGN KEY (clan_id, root_person_id) REFERENCES person (clan_id, id),
    CONSTRAINT view_policy_scope_ck CHECK (
        (scope_mode = 'CLAN' AND root_person_id IS NULL AND depth_down IS NULL AND depth_up IS NULL)
        OR (scope_mode = 'BRANCH' AND root_person_id IS NOT NULL
            AND coalesce(depth_down BETWEEN 0 AND 50, false) AND coalesce(depth_up BETWEEN 0 AND 50, false))
        OR (scope_mode = 'RELATIVE' AND root_person_id IS NULL
            AND coalesce(depth_down BETWEEN 0 AND 50, false) AND coalesce(depth_up BETWEEN 0 AND 50, false))),
    CONSTRAINT view_policy_fields_ck CHECK (
        'BASIC' = ANY (field_groups) AND field_groups <@ gp_policy_field_groups())
);

ALTER TABLE clan
    ADD CONSTRAINT clan_default_policy_fk FOREIGN KEY (id, default_member_policy_id)
        REFERENCES view_policy (clan_id, id);

-- ---------------------------------------------------------------------
-- Thành viên
-- ---------------------------------------------------------------------

CREATE TABLE clan_membership (
    clan_id        uuid        NOT NULL REFERENCES clan (id),
    user_id        uuid        NOT NULL REFERENCES app_user (id),
    role           text        NOT NULL CHECK (role IN ('OWNER', 'EDITOR', 'MEMBER')),
    person_id      uuid,       -- hồ sơ gia phả của chính người dùng
    view_policy_id uuid,       -- NULL: MEMBER dùng chế độ mặc định, EDITOR có phạm vi toàn dòng họ
    created_by     uuid        REFERENCES app_user (id),
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    version        integer     NOT NULL DEFAULT 0,

    PRIMARY KEY (clan_id, user_id),
    CONSTRAINT clan_membership_person_fk FOREIGN KEY (clan_id, person_id) REFERENCES person (clan_id, id),
    CONSTRAINT clan_membership_policy_fk FOREIGN KEY (clan_id, view_policy_id) REFERENCES view_policy (clan_id, id),
    CONSTRAINT clan_membership_owner_unscoped_ck CHECK (role <> 'OWNER' OR view_policy_id IS NULL)
);
CREATE INDEX clan_membership_user_idx ON clan_membership (user_id);
-- Mỗi dòng họ có đúng một OWNER (kết hợp trigger clan_membership_owner_guard).
CREATE UNIQUE INDEX clan_membership_one_owner_uk ON clan_membership (clan_id) WHERE role = 'OWNER';
-- Một hồ sơ gắn với tối đa một tài khoản trong dòng họ.
CREATE UNIQUE INDEX clan_membership_person_uk ON clan_membership (clan_id, person_id) WHERE person_id IS NOT NULL;

ALTER TABLE clan
    ADD CONSTRAINT clan_successor_fk FOREIGN KEY (id, successor_user_id)
        REFERENCES clan_membership (clan_id, user_id) ON DELETE SET NULL (successor_user_id);

CREATE FUNCTION gp_ensure_clan_has_owner() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM clan WHERE id = OLD.clan_id)
       AND NOT EXISTS (SELECT 1 FROM clan_membership WHERE clan_id = OLD.clan_id AND role = 'OWNER') THEN
        RAISE EXCEPTION 'clan % must keep exactly one OWNER', OLD.clan_id
            USING ERRCODE = 'check_violation', CONSTRAINT = 'clan_must_have_owner';
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER clan_membership_owner_guard
    AFTER UPDATE OR DELETE ON clan_membership
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION gp_ensure_clan_has_owner();

-- ---------------------------------------------------------------------
-- Lời mời
-- ---------------------------------------------------------------------

CREATE TABLE invitation (
    id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    clan_id        uuid        NOT NULL REFERENCES clan (id),
    email          text        NOT NULL CHECK (email = lower(email) AND length(email) BETWEEN 3 AND 254),
    role           text        NOT NULL CHECK (role IN ('EDITOR', 'MEMBER')),
    person_id      uuid,       -- hồ sơ được gắn khi người nhận chấp nhận
    view_policy_id uuid,
    token_hash     bytea       NOT NULL UNIQUE CHECK (length(token_hash) = 32),
    expires_at     timestamptz NOT NULL,
    accepted_at    timestamptz,
    accepted_by    uuid        REFERENCES app_user (id),
    revoked_at     timestamptz,
    created_by     uuid        NOT NULL REFERENCES app_user (id),
    created_at     timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT invitation_clan_id_uk UNIQUE (clan_id, id),
    CONSTRAINT invitation_person_fk FOREIGN KEY (clan_id, person_id) REFERENCES person (clan_id, id),
    CONSTRAINT invitation_policy_fk FOREIGN KEY (clan_id, view_policy_id) REFERENCES view_policy (clan_id, id),
    CONSTRAINT invitation_expiry_ck CHECK (expires_at > created_at AND expires_at <= created_at + interval '14 days')
);
CREATE INDEX invitation_clan_idx ON invitation (clan_id);

-- ---------------------------------------------------------------------
-- Link chia sẻ: luôn trỏ tới một chế độ xem; có thể không thời hạn.
-- ---------------------------------------------------------------------

CREATE TABLE share_link (
    id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    clan_id        uuid        NOT NULL REFERENCES clan (id),
    label          text        CHECK (length(label) <= 200),
    token_hash     bytea       NOT NULL UNIQUE CHECK (length(token_hash) = 32),
    view_policy_id uuid        NOT NULL,
    expires_at     timestamptz,                -- NULL: không thời hạn
    revoked_at     timestamptz,
    deleted_at     timestamptz,                -- xóa mềm; giữ lại để audit tham chiếu
    last_used_at   timestamptz,
    created_by     uuid        NOT NULL REFERENCES app_user (id),
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    version        integer     NOT NULL DEFAULT 0,

    CONSTRAINT share_link_clan_id_uk UNIQUE (clan_id, id),
    CONSTRAINT share_link_policy_fk FOREIGN KEY (clan_id, view_policy_id) REFERENCES view_policy (clan_id, id),
    CONSTRAINT share_link_expiry_ck CHECK (expires_at IS NULL OR expires_at > created_at)
);
CREATE INDEX share_link_clan_idx ON share_link (clan_id);

-- Trần an toàn: link chỉ được dùng chế độ xem không tương đối và chỉ gồm nhóm trường trong trần.
CREATE FUNCTION gp_assert_link_policy(p_policy_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM view_policy
               WHERE id = p_policy_id
                 AND (scope_mode = 'RELATIVE' OR NOT field_groups <@ gp_link_field_ceiling())) THEN
        RAISE EXCEPTION 'view policy exceeds the share link ceiling'
            USING ERRCODE = 'check_violation', CONSTRAINT = 'share_link_policy_ceiling';
    END IF;
END;
$$;

CREATE FUNCTION gp_share_link_policy_trg() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.deleted_at IS NULL THEN
        PERFORM gp_assert_link_policy(NEW.view_policy_id);
    END IF;
    RETURN NEW;
END;
$$;

CREATE FUNCTION gp_view_policy_link_trg() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM share_link WHERE view_policy_id = NEW.id AND deleted_at IS NULL) THEN
        PERFORM gp_assert_link_policy(NEW.id);
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER share_link_policy_check BEFORE INSERT OR UPDATE OF view_policy_id, deleted_at ON share_link
    FOR EACH ROW EXECUTE FUNCTION gp_share_link_policy_trg();
CREATE TRIGGER view_policy_link_check AFTER UPDATE ON view_policy
    FOR EACH ROW EXECUTE FUNCTION gp_view_policy_link_trg();

-- ---------------------------------------------------------------------
-- Yêu cầu nhận hồ sơ (gắn tài khoản với hồ sơ gia phả)
-- ---------------------------------------------------------------------

CREATE TABLE person_claim (
    id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    clan_id       uuid        NOT NULL,
    user_id       uuid        NOT NULL,
    person_id     uuid        NOT NULL,
    status        text        NOT NULL DEFAULT 'PENDING'
                              CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'CANCELED')),
    note          text        CHECK (length(note) <= 500),
    decided_by    uuid        REFERENCES app_user (id),
    decided_at    timestamptz,
    decision_note text        CHECK (length(decision_note) <= 500),
    created_at    timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT person_claim_member_fk FOREIGN KEY (clan_id, user_id)
        REFERENCES clan_membership (clan_id, user_id) ON DELETE CASCADE,
    CONSTRAINT person_claim_person_fk FOREIGN KEY (clan_id, person_id) REFERENCES person (clan_id, id)
);
CREATE UNIQUE INDEX person_claim_one_pending_uk ON person_claim (clan_id, user_id) WHERE status = 'PENDING';

-- ---------------------------------------------------------------------
-- Chuyển giao quyền trưởng tộc
--   VOLUNTARY: OWNER chủ động chuyển, người nhận chấp nhận
--   SUCCESSOR: người kế nhiệm tiếp quản khi OWNER không hoạt động
--   RECOVERY:  EDITOR lập đơn khôi phục, EDITOR xác nhận, SUPPORT duyệt
-- ---------------------------------------------------------------------

CREATE TABLE ownership_transfer (
    id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    clan_id       uuid        NOT NULL REFERENCES clan (id),
    kind          text        NOT NULL CHECK (kind IN ('VOLUNTARY', 'SUCCESSOR', 'RECOVERY')),
    from_user_id  uuid        NOT NULL REFERENCES app_user (id),
    to_user_id    uuid        NOT NULL REFERENCES app_user (id),
    requested_by  uuid        NOT NULL REFERENCES app_user (id),
    status        text        NOT NULL CHECK (status IN (
                                  'PENDING_ACCEPTANCE', 'PENDING_ENDORSEMENT', 'WAITING_PERIOD',
                                  'PENDING_REVIEW', 'COMPLETED', 'CANCELED', 'REJECTED', 'EXPIRED')),
    reason        text        CHECK (length(reason) <= 2000),
    expires_at    timestamptz,
    effective_at  timestamptz,
    decided_by    uuid        REFERENCES app_user (id),
    decided_at    timestamptz,
    decision_note text        CHECK (length(decision_note) <= 2000),
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT ownership_transfer_clan_id_uk UNIQUE (clan_id, id),
    CONSTRAINT ownership_transfer_distinct_ck CHECK (from_user_id <> to_user_id)
);
-- Mỗi dòng họ có tối đa một yêu cầu chuyển giao đang xử lý.
CREATE UNIQUE INDEX ownership_transfer_one_active_uk ON ownership_transfer (clan_id)
    WHERE status IN ('PENDING_ACCEPTANCE', 'PENDING_ENDORSEMENT', 'WAITING_PERIOD', 'PENDING_REVIEW');

CREATE TABLE transfer_endorsement (
    clan_id     uuid        NOT NULL,
    transfer_id uuid        NOT NULL,
    user_id     uuid        NOT NULL REFERENCES app_user (id),
    created_at  timestamptz NOT NULL DEFAULT now(),

    PRIMARY KEY (transfer_id, user_id),
    CONSTRAINT transfer_endorsement_transfer_fk FOREIGN KEY (clan_id, transfer_id)
        REFERENCES ownership_transfer (clan_id, id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
-- Đăng ký gói và thanh toán
-- ---------------------------------------------------------------------

CREATE TABLE clan_subscription (
    clan_id            uuid        PRIMARY KEY REFERENCES clan (id),
    plan_code          text        NOT NULL REFERENCES plan (code),
    current_period_end timestamptz,            -- NULL: không thời hạn (gói FREE hoặc cấp bởi quản trị)
    updated_at         timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE payment_transaction (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    clan_id         uuid        NOT NULL REFERENCES clan (id),
    plan_code       text        NOT NULL REFERENCES plan (code),
    months          integer     NOT NULL CHECK (months BETWEEN 1 AND 24),
    amount_vnd      bigint      NOT NULL CHECK (amount_vnd > 0),
    provider        text        NOT NULL DEFAULT 'VNPAY' CHECK (provider IN ('VNPAY')),
    txn_ref         text        NOT NULL UNIQUE CHECK (txn_ref ~ '^[A-Za-z0-9]{8,64}$'),
    status          text        NOT NULL DEFAULT 'PENDING'
                                CHECK (status IN ('PENDING', 'SUCCEEDED', 'FAILED', 'EXPIRED')),
    provider_txn_no text        CHECK (length(provider_txn_no) <= 100),
    provider_payload jsonb,
    created_by      uuid        NOT NULL REFERENCES app_user (id),
    created_at      timestamptz NOT NULL DEFAULT now(),
    completed_at    timestamptz
);
CREATE INDEX payment_transaction_clan_idx ON payment_transaction (clan_id, created_at DESC);

-- Gói hiệu lực của dòng họ: gói đã đăng ký nếu còn hạn, ngược lại là FREE.
CREATE FUNCTION gp_effective_plan(p_clan_id uuid) RETURNS plan
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT p.* FROM plan p
    WHERE p.code = coalesce(
        (SELECT s.plan_code FROM clan_subscription s
         WHERE s.clan_id = p_clan_id
           AND (s.current_period_end IS NULL OR s.current_period_end > now())),
        'FREE')
$$;

-- ---------------------------------------------------------------------
-- Hạn mức: kiểm tra trước khi thêm; khóa tư vấn theo (tài nguyên, dòng họ)
-- để hai yêu cầu đồng thời không vượt hạn mức.
-- ---------------------------------------------------------------------

CREATE FUNCTION gp_enforce_quota_trg() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_resource text := TG_ARGV[0];
    v_plan     plan := gp_effective_plan(NEW.clan_id);
    v_count    bigint;
    v_limit    bigint;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended('quota:' || v_resource || ':' || NEW.clan_id::text, 0));

    IF v_resource = 'PERSONS' THEN
        SELECT count(*) INTO v_count FROM person WHERE clan_id = NEW.clan_id;
        v_limit := v_plan.max_persons;
    ELSIF v_resource = 'MEMBERS' THEN
        SELECT count(*) INTO v_count FROM clan_membership WHERE clan_id = NEW.clan_id;
        v_limit := v_plan.max_members;
    ELSIF v_resource = 'SHARE_LINKS' THEN
        SELECT count(*) INTO v_count FROM share_link
        WHERE clan_id = NEW.clan_id AND deleted_at IS NULL AND revoked_at IS NULL
          AND (expires_at IS NULL OR expires_at > now());
        v_limit := v_plan.max_share_links;
    ELSIF v_resource = 'VIEW_POLICIES' THEN
        SELECT count(*) INTO v_count FROM view_policy WHERE clan_id = NEW.clan_id;
        v_limit := v_plan.max_view_policies;
    ELSE
        RAISE EXCEPTION 'unknown quota resource %', v_resource;
    END IF;

    IF v_count >= v_limit THEN
        RAISE EXCEPTION 'quota exceeded for %', v_resource
            USING ERRCODE = 'GP010', DETAIL = v_resource, HINT = v_limit::text;
    END IF;
    RETURN NEW;
END;
$$;

CREATE FUNCTION gp_enforce_storage_quota_trg() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
    v_used  bigint;
    v_limit bigint := (gp_effective_plan(NEW.clan_id)).max_storage_mb::bigint * 1024 * 1024;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended('quota:STORAGE:' || NEW.clan_id::text, 0));
    SELECT coalesce(sum(photo_size_bytes), 0) INTO v_used
    FROM person WHERE clan_id = NEW.clan_id AND id <> NEW.id;
    IF v_used + NEW.photo_size_bytes > v_limit THEN
        RAISE EXCEPTION 'quota exceeded for STORAGE'
            USING ERRCODE = 'GP010', DETAIL = 'STORAGE', HINT = v_limit::text;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER person_quota BEFORE INSERT ON person
    FOR EACH ROW EXECUTE FUNCTION gp_enforce_quota_trg('PERSONS');
CREATE TRIGGER clan_membership_quota BEFORE INSERT ON clan_membership
    FOR EACH ROW EXECUTE FUNCTION gp_enforce_quota_trg('MEMBERS');
CREATE TRIGGER share_link_quota BEFORE INSERT ON share_link
    FOR EACH ROW EXECUTE FUNCTION gp_enforce_quota_trg('SHARE_LINKS');
CREATE TRIGGER view_policy_quota BEFORE INSERT ON view_policy
    FOR EACH ROW EXECUTE FUNCTION gp_enforce_quota_trg('VIEW_POLICIES');
CREATE TRIGGER person_storage_quota BEFORE UPDATE OF photo_size_bytes ON person
    FOR EACH ROW WHEN (NEW.photo_size_bytes > OLD.photo_size_bytes)
    EXECUTE FUNCTION gp_enforce_storage_quota_trg();

-- ---------------------------------------------------------------------
-- Nhật ký dòng họ (chỉ ghi thêm). Tầng ứng dụng ghi qua gp_audit() (V2).
-- ---------------------------------------------------------------------

CREATE TABLE audit_log (
    id                  bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    clan_id             uuid        NOT NULL REFERENCES clan (id),
    actor_user_id       uuid        REFERENCES app_user (id),
    actor_share_link_id uuid        REFERENCES share_link (id),
    action              text        NOT NULL CHECK (action ~ '^[A-Z_]{1,64}$'),
    entity_type         text        CHECK (length(entity_type) <= 64),
    entity_id           uuid,
    detail              jsonb       NOT NULL DEFAULT '{}'::jsonb,
    ip                  inet,
    user_agent          text        CHECK (length(user_agent) <= 500),
    created_at          timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT audit_log_actor_ck CHECK (actor_user_id IS NOT NULL OR actor_share_link_id IS NOT NULL)
);
CREATE INDEX audit_log_clan_time_idx ON audit_log (clan_id, created_at DESC);

-- ---------------------------------------------------------------------
-- Trigger chung
-- ---------------------------------------------------------------------

CREATE TRIGGER app_user_touch BEFORE UPDATE ON app_user
    FOR EACH ROW EXECUTE FUNCTION gp_touch_updated_at();
CREATE TRIGGER clan_touch BEFORE UPDATE ON clan
    FOR EACH ROW EXECUTE FUNCTION gp_touch_updated_at();
CREATE TRIGGER person_touch BEFORE UPDATE ON person
    FOR EACH ROW EXECUTE FUNCTION gp_touch_updated_at();
CREATE TRIGGER family_union_touch BEFORE UPDATE ON family_union
    FOR EACH ROW EXECUTE FUNCTION gp_touch_updated_at();
CREATE TRIGGER view_policy_touch BEFORE UPDATE ON view_policy
    FOR EACH ROW EXECUTE FUNCTION gp_touch_updated_at();
CREATE TRIGGER clan_membership_touch BEFORE UPDATE ON clan_membership
    FOR EACH ROW EXECUTE FUNCTION gp_touch_updated_at();
CREATE TRIGGER share_link_touch BEFORE UPDATE ON share_link
    FOR EACH ROW EXECUTE FUNCTION gp_touch_updated_at();
CREATE TRIGGER ownership_transfer_touch BEFORE UPDATE ON ownership_transfer
    FOR EACH ROW EXECUTE FUNCTION gp_touch_updated_at();
CREATE TRIGGER clan_subscription_touch BEFORE UPDATE ON clan_subscription
    FOR EACH ROW EXECUTE FUNCTION gp_touch_updated_at();
CREATE TRIGGER plan_touch BEFORE UPDATE ON plan
    FOR EACH ROW EXECUTE FUNCTION gp_touch_updated_at();

CREATE TRIGGER person_clan_immutable BEFORE UPDATE OF clan_id ON person
    FOR EACH ROW EXECUTE FUNCTION gp_forbid_clan_change();
CREATE TRIGGER family_union_clan_immutable BEFORE UPDATE OF clan_id ON family_union
    FOR EACH ROW EXECUTE FUNCTION gp_forbid_clan_change();
CREATE TRIGGER union_child_clan_immutable BEFORE UPDATE OF clan_id ON union_child
    FOR EACH ROW EXECUTE FUNCTION gp_forbid_clan_change();
CREATE TRIGGER view_policy_clan_immutable BEFORE UPDATE OF clan_id ON view_policy
    FOR EACH ROW EXECUTE FUNCTION gp_forbid_clan_change();
CREATE TRIGGER clan_membership_clan_immutable BEFORE UPDATE OF clan_id ON clan_membership
    FOR EACH ROW EXECUTE FUNCTION gp_forbid_clan_change();
CREATE TRIGGER invitation_clan_immutable BEFORE UPDATE OF clan_id ON invitation
    FOR EACH ROW EXECUTE FUNCTION gp_forbid_clan_change();
CREATE TRIGGER share_link_clan_immutable BEFORE UPDATE OF clan_id ON share_link
    FOR EACH ROW EXECUTE FUNCTION gp_forbid_clan_change();
CREATE TRIGGER person_claim_clan_immutable BEFORE UPDATE OF clan_id ON person_claim
    FOR EACH ROW EXECUTE FUNCTION gp_forbid_clan_change();
CREATE TRIGGER ownership_transfer_clan_immutable BEFORE UPDATE OF clan_id ON ownership_transfer
    FOR EACH ROW EXECUTE FUNCTION gp_forbid_clan_change();
