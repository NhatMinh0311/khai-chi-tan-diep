# Phân quyền và cách ly dữ liệu

| Thuộc tính | Giá trị |
|---|---|
| Mã tài liệu | GP-DOC-03 |
| Phiên bản | 1.2 |
| Ngày ban hành | 14/10/2026 |
| Tài liệu liên quan | GP-DOC-01 Phạm vi, GP-DOC-02 Mô hình dữ liệu, GP-DOC-05 Quản trị và chuyển giao, `db/migration/V2__rls.sql`, `db/tests/` |

## 1. Nguyên tắc

1. **Mặc định từ chối.** Truy vấn không có ngữ cảnh phiên không trả về dữ liệu (test T01).
2. **Cách ly dòng họ hai lớp.** Việc cách ly được thực hiện ở tầng service và ở tầng cơ sở dữ liệu
   (RLS và khóa ngoại kép). Sai sót ở một lớp không làm lộ dữ liệu (T02, T03, T11).
3. **Phản hồi 404 cho tài nguyên không được phép truy cập.** Tài nguyên thuộc dòng họ khác hoặc nằm ngoài phạm vi
   nhận phản hồi 404, giống tài nguyên không tồn tại. Phản hồi 403 chỉ dùng khi người dùng xem được tài nguyên
   nhưng không có quyền thực hiện hành động.
4. **Giao diện không phải cơ chế phân quyền.** Việc ẩn chức năng trên giao diện chỉ phục vụ trải nghiệm người dùng.
5. **Đặc quyền tối thiểu ở cơ sở dữ liệu.** Backend kết nối bằng tài khoản `gp_app` (không sở hữu bảng,
   không có `BYPASSRLS`, quyền ghi giới hạn theo cột). Tài khoản `gp_owner` chỉ dùng cho migration và tác vụ bảo trì.
6. **Quyền không nằm trong token.** JWT chỉ xác định danh tính. Vai trò hệ thống, vai trò trong dòng họ, phạm vi và
   nhóm trường được đọc từ cơ sở dữ liệu ở mỗi yêu cầu, do đó thay đổi quyền có hiệu lực tức thời.
7. **Quản trị nền tảng tách biệt dữ liệu gia phả.** Vai trò hệ thống không mở quyền đọc dữ liệu của bất kỳ dòng họ nào (T34).
8. **EDITOR chỉ ghi sử.** EDITOR thêm và sửa dữ liệu gia phả trong phạm vi; mọi hành động chia sẻ dữ liệu ra ngoài
   hoặc cấp quyền xem cho người khác (mời thành viên, gắn tài khoản với hồ sơ, link chia sẻ, chế độ xem, xuất tệp)
   thuộc về OWNER (T05, T29).

## 2. Chủ thể và vai trò

| Chủ thể | Xác thực | Vai trò |
|---|---|---|
| Người dùng | JWT `typ=user`, `sub=userId` | Vai trò hệ thống (`SYSTEM_ADMIN`, `SUPPORT`) từ `app_user.system_role`; vai trò trong dòng họ (`OWNER`, `EDITOR`, `MEMBER`) từ `clan_membership` |
| Khách | JWT `typ=guest`, `sub=shareLinkId`, `cid=clanId` | `GUEST`, với điều kiện link còn hạn, chưa thu hồi, chưa xóa |

Vai trò trong dòng họ mất hiệu lực tức thời khi: tài khoản bị khóa (T07), dòng họ bị tạm ngưng (T34).
Quyền của vai trò hệ thống được quy định tại GP-DOC-05.

## 3. Ma trận quyền trong dòng họ

| Hành động | OWNER | EDITOR | MEMBER | GUEST |
|---|:-:|:-:|:-:|:-:|
| Xem thông tin dòng họ | ✓ | ✓ | ✓ | ✓ |
| Xem cây và hồ sơ | Toàn bộ | Theo chế độ xem | Theo chế độ xem | Theo chế độ xem của link |
| Tìm kiếm | ✓ | ✓ | ✓ | ✗ |
| Thêm, sửa người, hôn phối, quan hệ con; tải ảnh | ✓ | Trong phạm vi | ✗ | ✗ |
| Xóa người | ✓ | ✗ | ✗ | ✗ |
| Tự sửa liên hệ và cờ hạn chế của hồ sơ mình | ✓ | ✓ | ✓ | ✗ |
| Yêu cầu nhận hồ sơ | ✓ | ✓ | ✓ | ✗ |
| Duyệt yêu cầu nhận hồ sơ | ✓ | ✗ | ✗ | ✗ |
| Xem danh sách thành viên, lời mời | ✓ | ✗ | ✗ | ✗ |
| Mời thành viên (vai trò EDITOR, MEMBER; chế độ xem; hồ sơ gắn sẵn) | ✓ | ✗ | ✗ | ✗ |
| Sửa vai trò, chế độ xem, hồ sơ gắn với thành viên; xóa thành viên | ✓ | ✗ | ✗ | ✗ |
| Quản lý chế độ xem, link chia sẻ | ✓ | ✗ | ✗ | ✗ |
| Xuất Excel | ✓ | ✗ | ✗ | ✗ |
| Xem audit log | ✓ | ✗ | ✗ | ✗ |
| Sửa thông tin dòng họ, thủy tổ, chế độ xem mặc định | ✓ | ✗ | ✗ | ✗ |
| Mua, gia hạn gói; xem lịch sử thanh toán | ✓ | ✗ | ✗ | ✗ |
| Xem gói và hạn mức | ✓ | ✓ | ✓ | ✗ |
| Chỉ định người kế nhiệm; chuyển giao chủ động | ✓ | ✗ | ✗ | ✗ |
| Chấp nhận chuyển giao; yêu cầu tiếp quản (người kế nhiệm) | — | ✓ | ✓ | ✗ |
| Lập và xác nhận đơn khôi phục (S04) | — | ✓ | ✗ | ✗ |

## 4. Nhóm trường thông tin

| Nhóm | Trường |
|---|---|
| `BASIC` | `id`, `fullName`, `gender`, `generation`, cấu trúc quan hệ (cha mẹ, vợ chồng, con, thứ tự) |
| `LIFE_EVENTS` | `isLiving`, `otherNames`, ngày sinh (với người còn sống chỉ gồm năm), ngày mất, `birthPlace`, `burialPlace`, `lifespan` |
| `BIOGRAPHY` | `occupation`, `biography`, ảnh (`hasPhoto`, tệp ảnh) |
| `LIVING_BIRTH_DATE` | Ngày và tháng sinh của người còn sống (áp dụng khi có `LIFE_EVENTS`) |
| `CONTACT` | `currentAddress`, `phone`, `email` |
| `ADOPTION` | Thuộc tính `relation` (`BIOLOGICAL`, `ADOPTED`) của quan hệ con |
| `IDENTITY_DOCS` | `nationalId`, `privateNote` |

Nhóm trường hiệu lực theo chủ thể (hàm `app_visible_field_groups()`):

| Chủ thể | Nhóm trường |
|---|---|
| OWNER | Tất cả |
| EDITOR | Tất cả trừ `IDENTITY_DOCS` (cố định, không cấu hình) |
| MEMBER | Theo chế độ xem riêng, nếu không có thì theo chế độ xem mặc định của dòng họ |
| GUEST | Theo chế độ xem của link, giao với trần của link |

Trần an toàn:
- Chế độ xem không chứa `IDENTITY_DOCS`; luôn chứa `BASIC`.
- **Trần của link chia sẻ:** `BASIC`, `LIFE_EVENTS`, `BIOGRAPHY`; phạm vi `CLAN` hoặc `BRANCH`. Link không bao giờ lộ
  liên hệ, giấy tờ, ngày sinh đầy đủ của người còn sống và quan hệ con nuôi (T25).

Quy tắc bổ sung:
- Hồ sơ có `isRestricted = true` chỉ hiển thị nhóm `BASIC` với MEMBER và khách.
- Chủ hồ sơ (tài khoản gắn với hồ sơ) xem được toàn bộ hồ sơ của mình trừ `privateNote`, và thấy cờ `isRestricted`.
- Cờ `isRestricted` hiển thị với EDITOR trở lên và chủ hồ sơ.

**Quy ước phản hồi.** Trường bị ẩn không có mặt trong JSON; tên trường (dạng đường dẫn, ví dụ `birth.solar.day`)
được liệt kê trong `redactedFields`. Yêu cầu ghi chứa trường thuộc nhóm mà người gửi không được xem nhận lỗi
403 `FIELD_NOT_PERMITTED`.

**Vị trí thực thi.** RLS lọc theo dòng dữ liệu; việc ẩn trường do backend thực hiện dựa trên kết quả của
`app_visible_field_groups()`. Logic ẩn trường được tập trung tại một thành phần duy nhất (`PersonViewPolicy`),
dùng chung cho API hồ sơ, API cây, link chia sẻ và chức năng xuất Excel.

## 5. Phạm vi truy cập

Phạm vi được xác định bởi chế độ xem hiệu lực (GP-DOC-02 mục 7):

| Chủ thể | Phạm vi |
|---|---|
| OWNER | Toàn bộ dòng họ |
| EDITOR | Phạm vi của chế độ xem riêng; không có chế độ xem riêng thì toàn bộ dòng họ. Phạm vi này áp dụng cho cả đọc và ghi |
| MEMBER | Phạm vi của chế độ xem riêng hoặc chế độ xem mặc định |
| GUEST | Phạm vi của chế độ xem của link |

```
BRANCH {root: Bình, down: 1, up: 0, spouses: true}
  = hậu duệ của Bình trong 1 đời     -> Bình, Đức, Em
  + vợ/chồng của các người trên      -> Hoa

RELATIVE {up: 1, down: 1, spouses: false}, người xem là Đức
  = tổ tiên của Đức trong 1 đời      -> Đức, Bình, Hoa
  + hậu duệ của họ tới 1 đời dưới thế hệ Đức -> Em và con của Đức
```

- Nhánh được tính theo con cháu qua cả cha và mẹ.
- Phạm vi `RELATIVE` yêu cầu tài khoản đã gắn hồ sơ; chưa gắn thì phạm vi rỗng (T24).
- EDITOR có phạm vi giới hạn khi tạo người mới phải gắn người đó vào một người trong phạm vi trong cùng transaction
  (trường `link` của `POST /persons`) (T20).
- Thay đổi chế độ xem có hiệu lực từ truy vấn kế tiếp, do RLS đọc chế độ xem tại mỗi truy vấn (T23).

## 6. Link chia sẻ cho khách

1. Token gồm 32 byte ngẫu nhiên sinh bằng `SecureRandom`, mã hóa base64url. Cơ sở dữ liệu chỉ lưu `SHA-256(token)`.
2. URL có dạng `https://<host>/s#<token>`. Phần sau ký tự `#` không được trình duyệt gửi lên máy chủ, do đó
   không xuất hiện trong log máy chủ và header Referer.
3. Frontend đọc token từ fragment, gọi `POST /shared/sessions` để nhận JWT khách có hiệu lực 30 phút, sau đó xóa
   fragment khỏi thanh địa chỉ. Người đã đăng nhập mở link cũng được xem theo chế độ xem của link, độc lập với
   tư cách thành viên.
4. Link có thể không thời hạn. Thu hồi, xóa hoặc đổi chế độ xem có hiệu lực tức thời, kể cả với JWT khách chưa hết hạn,
   do RLS kiểm tra trạng thái link tại mỗi truy vấn (T09, T10, T26).
5. `POST /shared/sessions` giới hạn 10 yêu cầu/phút/IP. Token sai, hết hạn, đã thu hồi hoặc đã xóa nhận cùng phản hồi 404.
6. Số link đang hoạt động bị giới hạn theo gói (GP-DOC-04).

Lời mời sử dụng cùng cơ chế token với thời hạn tối đa 14 ngày, chỉ sử dụng được một lần và chỉ được chấp nhận
bởi tài khoản có đúng email được mời, đã xác minh (T18).

## 7. Các lớp thực thi

| Lớp | Trách nhiệm | Thành phần |
|---|---|---|
| Giao diện | Ẩn chức năng, hiển thị trạng thái trường bị ẩn | Frontend |
| Spring Security | Xác thực JWT, kiểm tra step-up token cho thao tác nhạy cảm | Backend |
| Service | Kiểm tra trường được phép ghi, ẩn trường, kiểm tra tính năng của gói, ghi audit | Backend |
| RLS | Cách ly dòng họ, tư cách thành viên, trạng thái dòng họ, phạm vi đọc, vai trò ghi | Cơ sở dữ liệu |
| Hàm nghiệp vụ | Tạo dòng họ, lời mời, link khách, nhận hồ sơ, chuyển giao, thanh toán, quản trị | Cơ sở dữ liệu |
| Ràng buộc | Khóa ngoại kép, quan hệ tổ tiên vòng, ngày hợp lệ, đúng một OWNER, hạn mức, trần của link, audit chỉ ghi thêm, quyền theo cột | Cơ sở dữ liệu |

## 8. Truyền ngữ cảnh phiên xuống cơ sở dữ liệu

Backend đặt ngữ cảnh ở đầu mỗi transaction, trước mọi truy vấn khác. Tham số thứ ba bằng `true` giới hạn
hiệu lực trong transaction hiện tại, bảo đảm kết nối trả về pool không mang ngữ cảnh sang yêu cầu khác.

```sql
SELECT set_config('app.user_id',       :userId,      true),
       set_config('app.clan_id',       :clanId,      true),   -- chuỗi rỗng với thao tác không thuộc dòng họ
       set_config('app.share_link_id', :shareLinkId, true);  -- chuỗi rỗng nếu không phải khách
```

Mẫu hiện thực:

```java
@Component
@RequiredArgsConstructor
public class DbSessionContext {
    private final EntityManager em;

    /** Đặt ngữ cảnh phiên cho transaction hiện tại. */
    public void apply(Principal p, UUID clanId) {
        em.createNativeQuery("""
                select set_config('app.user_id', :u, true),
                       set_config('app.clan_id', :c, true),
                       set_config('app.share_link_id', :s, true)""")
          .setParameter("u", p.isGuest() ? "" : p.userId().toString())
          .setParameter("c", clanId == null ? "" : clanId.toString())
          .setParameter("s", p.isGuest() ? p.shareLinkId().toString() : "")
          .getSingleResult();
    }
}
```

Việc gọi `apply` được thực hiện tự động bằng aspect bao quanh các service có `@Transactional`.
Transaction thiếu ngữ cảnh nhận kết quả rỗng; bộ test integration phát hiện trường hợp này.

Các thao tác diễn ra ngoài phạm vi một dòng họ, hoặc cần vượt RLS có kiểm soát, được thực hiện qua hàm cơ sở dữ liệu
(danh sách đầy đủ tại `V2__rls.sql`, mục "Quyền của gp_app"):

| Thao tác | Hàm | Ngữ cảnh yêu cầu |
|---|---|---|
| Tạo dòng họ | `gp_create_clan` | `app.user_id` |
| Chấp nhận lời mời | `gp_accept_invitation(sha256(token))` | `app.user_id` |
| Mở phiên khách | `gp_resolve_share_link(sha256(token))` | Không |
| Ghi nhận hoạt động khi đăng nhập, làm mới phiên | `gp_touch_activity` | `app.user_id` |
| Nhóm trường của người xem | `app_visible_field_groups` | Đầy đủ |
| Hạn mức và mức sử dụng | `gp_clan_entitlements` | Đầy đủ |
| Tự sửa hồ sơ; nhận hồ sơ; duyệt | `gp_update_own_profile`, `gp_claim_person`, `gp_decide_claim` | Đầy đủ |
| Chuyển giao, kế nhiệm | `gp_set_successor`, `gp_transfer_*`, `gp_takeover_request`, `gp_recovery_*` | Đầy đủ |
| Thanh toán | `gp_create_payment`; `gp_confirm_payment` (IPN) | Đầy đủ; IPN không cần |
| Ghi audit | `gp_audit` | Đầy đủ; người thực hiện lấy từ ngữ cảnh |
| Quản trị nền tảng | `gp_admin_*` | `app.user_id` có vai trò hệ thống |

## 9. Cache và phân quyền

Redis được dùng cho cache và bộ đếm giới hạn tần suất (ADR-0009). Quy tắc bắt buộc:

1. **Không cache quyết định phân quyền.** Vai trò, phạm vi và nhóm trường được đọc từ cơ sở dữ liệu ở mỗi yêu cầu,
   trước khi tra cache. Yêu cầu bị từ chối không bao giờ chạm tới cache.
2. **Khóa cache chứa mọi yếu tố quyết định nội dung.** Dữ liệu cây được cache với khóa
   `tree:{clanId}:{dataVersion}:{policyFingerprint}:{rootPersonId}:{depthDown}:{depthUp}:{includeSpouses}`,
   trong đó `policyFingerprint` là SHA-256 của kết quả `app_effective_policy()` (phạm vi, nhóm trường, hồ sơ người xem).
   Hai người xem có quyền khác nhau không bao giờ dùng chung một mục cache.
3. **Dữ liệu thay đổi thì khóa thay đổi.** `dataVersion` tăng khi dữ liệu gia phả thay đổi (T31); mục cache cũ không
   còn được đọc và hết hạn theo TTL (10 phút).
4. Dữ liệu trong Redis đã được ẩn trường theo quyền; Redis yêu cầu mật khẩu, không mở ra ngoài mạng nội bộ,
   không lưu bền xuống đĩa.

## 10. Ánh xạ lỗi cơ sở dữ liệu sang HTTP

Backend bắt `DataAccessException`, lấy `PSQLException` gốc, đọc `getSQLState()` và
`getServerErrorMessage().getConstraint()`, sau đó ánh xạ theo bảng sau.

| SQLSTATE | Constraint | HTTP | `code` | Ghi chú |
|---|---|---|---|---|
| `23514` | `person_no_ancestry_cycle` | 409 | `ANCESTRY_CYCLE` | |
| `23514` | `clan_must_have_owner` | 409 | `LAST_OWNER` | Phát sinh tại thời điểm commit |
| `23514` | `share_link_policy_ceiling` | 409 | `LINK_POLICY_CEILING` | |
| `23514` | `person_*_ck`, `view_policy_*_ck` | 422 | `VALIDATION_FAILED` | Dữ liệu sai lọt qua tầng kiểm tra của backend |
| `23505` | `clan_membership_one_owner_uk` | 409 | `OWNER_TRANSFER_REQUIRED` | |
| `23505` | `clan_membership_person_uk` | 409 | `PERSON_ALREADY_LINKED` | |
| `23505` | `ownership_transfer_one_active_uk` | 409 | `TRANSFER_IN_PROGRESS` | |
| `23505` | `person_claim_one_pending_uk` | 409 | `INVALID_STATE` | |
| `23505` | `union_child_one_biological_uk` | 409 | `DUPLICATE_BIOLOGICAL_FAMILY` | |
| `23505` | `family_union_pair_uk` | 409 | `DUPLICATE_UNION` | |
| `23505` | `view_policy_name_uk` | 422 | `VALIDATION_FAILED` | Trường `name` |
| `23503` | Khi xóa `view_policy` | 409 | `POLICY_IN_USE` | |
| `23503` | Khi xóa người, hôn phối | 409 | `HAS_RELATIONS` | |
| `23503` | Khi thêm, sửa | 404 | `NOT_FOUND` | Tham chiếu tới dữ liệu của dòng họ khác |
| `42501` | Vi phạm RLS hoặc quyền theo cột | 404 | `NOT_FOUND` | Ghi log cảnh báo bảo mật: tầng service đã bỏ sót kiểm tra |
| `GP001` | | 404 | `INVALID_TOKEN` | |
| `GP002` | | 403 | `INVITATION_EMAIL_MISMATCH` | |
| `GP003` | | 409 | `ALREADY_MEMBER` | |
| `GP004` | | 401 | `UNAUTHENTICATED` | |
| `GP005` | | 403 | `FORBIDDEN` | |
| `GP006` | | 409 | `PERSON_ALREADY_LINKED` | |
| `GP007` | | 403 | `EMAIL_NOT_VERIFIED` | |
| `GP008` | | 409 | `INVALID_STATE` | |
| `GP009` | | 404 | `NOT_FOUND` | |
| `GP010` | | 402 | `QUOTA_EXCEEDED` | `DETAIL` là tài nguyên, `HINT` là giới hạn |
| `GP020` | | IPN `RspCode=01` | | Chỉ phát sinh từ IPN |
| `GP021` | | IPN `RspCode=04` | | Chỉ phát sinh từ IPN |
| `GP022` | | 422 | `PLAN_NOT_PURCHASABLE` | |

## 11. Audit

Audit được ghi khi: trả về trường thuộc nhóm `CONTACT`, `LIVING_BIRTH_DATE`, `ADOPTION` hoặc `IDENTITY_DOCS`
(`PERSON_VIEW_SENSITIVE`); tạo, sửa, xóa người, hôn phối và quan hệ con; thay đổi chế độ xem, thành viên, lời mời,
link; khách mở phiên; xuất tệp; nhận hồ sơ; chuyển giao quyền trưởng tộc; thanh toán; thao tác của quản trị nền tảng
lên dòng họ. Danh mục đầy đủ là enum `AuditAction` trong `api/openapi.yaml`.
Tài khoản `gp_app` không có quyền INSERT, UPDATE, DELETE trên `audit_log`; việc ghi chỉ thực hiện qua hàm `gp_audit()`
và các hàm nghiệp vụ (T16). Audit quá thời hạn lưu của gói được xóa bởi tác vụ bảo trì chạy bằng `gp_owner`.

## 12. Bất biến và kiểm thử

Các bất biến dưới đây được kiểm thử ở tầng cơ sở dữ liệu bằng `db/tests/run.sh` và được kiểm thử lại
qua HTTP bằng bộ test API.

| Mã | Bất biến | Test cơ sở dữ liệu |
|---|---|---|
| I1 | Truy vấn thiếu ngữ cảnh không trả về dữ liệu | T01 |
| I2 | Không đọc, không ghi được dữ liệu dòng họ khác, kể cả khi truy vấn thiếu điều kiện lọc hoặc đặt sai `clan_id` | T02, T03, T11 |
| I3 | Phạm vi được áp dụng cho cả đọc và ghi; chế độ xem mặc định và tương đối hoạt động đúng | T04, T08, T20, T23, T24 |
| I4 | Vai trò thấp không ghi được dữ liệu; không tự nâng được quyền | T05, T06, T21, T27 |
| I5 | Khóa tài khoản, thu hồi, xóa link, link hết hạn, tạm ngưng dòng họ có hiệu lực tức thời | T07, T09, T10, T26, T34 |
| I6 | Toàn vẹn gia phả: không có quan hệ tổ tiên vòng, một gia đình đẻ, ngày hợp lệ | T12–T15 |
| I7 | Audit không sửa, không xóa, không giả mạo được | T16, T21 |
| I8 | Đúng một OWNER; chuyển giao chỉ qua quy trình | T17, T27, T36–T38 |
| I9 | Lời mời đúng người, email đã xác minh, chỉ dùng một lần; gắn hồ sơ 1–1 | T18, T28, T29 |
| I10 | Nhóm trường đúng theo vai trò và chế độ xem; trần của link không bị vượt | T22, T25 |
| I11 | Tầng ứng dụng không truy cập được cơ chế nội bộ và cột được bảo vệ | T19, T35 |
| I12 | Hạn mức gói được áp dụng; thanh toán idempotent, kiểm tra số tiền | T32, T33 |
| I13 | Quản trị nền tảng không đọc được dữ liệu gia phả | T34 |
| I14 | Trường bị ẩn không có mặt trong phản hồi, tệp xuất và cache | Kiểm thử ở tầng API |

## Lịch sử thay đổi

| Phiên bản | Ngày | Nội dung |
|---|---|---|
| 1.0 | 14/10/2026 | Ban hành lần đầu |
| 1.2 | 14/10/2026 | Giới hạn EDITOR ở việc ghi dữ liệu gia phả (nguyên tắc 8) |
| 1.1 | 14/10/2026 | Thay mức T0–T3 bằng nhóm trường và chế độ xem; link chia sẻ cấu hình được, có trần an toàn; bổ sung vai trò hệ thống, gắn tài khoản với hồ sơ, quy tắc cache, mã lỗi mới |
