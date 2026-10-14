# Khai Chi Tán Diệp

Khai Chi Tán Diệp là nền tảng web quản lý gia phả cho nhiều dòng họ (multi-tenant), với cơ chế phân quyền chi tiết cho dữ liệu cá nhân
nhạy cảm, gói dịch vụ có thanh toán trực tuyến và quy trình chuyển giao quyền trưởng tộc.
Công nghệ: React, Spring Boot, PostgreSQL, Redis.

## Cấu trúc kho mã

| Đường dẫn | Nội dung |
|---|---|
| `api/openapi.yaml` | Đặc tả API, là hợp đồng giữa frontend và backend |
| `db/init/` | Khởi tạo tài khoản cơ sở dữ liệu `gp_owner`, `gp_app` |
| `db/migration/` | Migration Flyway: V1 lược đồ, V2 RLS và hàm nghiệp vụ, V3 dữ liệu tham chiếu |
| `db/tests/` | Kiểm thử RLS, ràng buộc và hàm nghiệp vụ, chạy bằng quyền của backend |
| `db/scripts/` | Script quản trị chạy bằng `gp_owner` (cấp vai trò hệ thống) |
| `docs/01-pham-vi.md` | GP-DOC-01: Phạm vi, user story, tiêu chí chấp nhận |
| `docs/02-mo-hinh-du-lieu.md` | GP-DOC-02: Mô hình dữ liệu |
| `docs/03-phan-quyen.md` | GP-DOC-03: Phân quyền, cách ly dữ liệu, cache, ánh xạ lỗi |
| `docs/04-goi-dich-vu-va-thanh-toan.md` | GP-DOC-04: Gói dịch vụ, hạn mức, thanh toán VNPay |
| `docs/05-quan-tri-va-chuyen-giao.md` | GP-DOC-05: Quản trị nền tảng, xác thực bổ sung, chuyển giao trưởng tộc |
| `docs/06-quy-trinh-phat-trien.md` | GP-DOC-06: Quy trình phát triển, bảo vệ nhánh, CI/CD |
| `.github/` | CODEOWNERS, mẫu pull request, workflow CI |
| `docs/adr/` | Hồ sơ quyết định kiến trúc (ADR-0001 đến ADR-0010) |

## Môi trường phát triển

Yêu cầu: Docker, Node.js.

| Dịch vụ | Địa chỉ |
|---|---|
| PostgreSQL 17 | `localhost:${DB_PORT}` |
| Redis 7.4 | `localhost:${REDIS_PORT}` (yêu cầu `REDIS_PASSWORD`) |
| Mailpit (SMTP giả lập) | SMTP `localhost:${SMTP_PORT}`, giao diện `http://localhost:${MAILPIT_UI_PORT}` |

```bash
cp .env.example .env                       # đặt mật khẩu trong .env
docker compose up -d db redis mailpit      # khởi động dịch vụ
docker compose run --rm migrate            # áp dụng migration
./db/tests/run.sh                          # kiểm thử cơ sở dữ liệu trên CSDL tạm giapha_test

npx @stoplight/prism-cli@5.14.2 mock api/openapi.yaml -p 4010   # mock API
npx @redocly/cli@1.34.5 lint api/openapi.yaml                   # kiểm tra đặc tả API
```

Cấp vai trò quản trị nền tảng cho một tài khoản đã đăng ký:

```bash
docker compose exec -T db psql -U gp_owner -d giapha \
    -v email=admin@example.vn -v role=SYSTEM_ADMIN < db/scripts/grant_system_role.sql
```

## Hướng dẫn theo thành phần

### Frontend
- Trong giai đoạn backend chưa sẵn sàng, frontend sử dụng mock API tại `http://localhost:4010`. Mọi yêu cầu
  cần header `Authorization: Bearer <token>` (mock chấp nhận giá trị bất kỳ). Ví dụ cụ thể được chọn bằng header
  `Prefer: example=<tên ví dụ>`.
- Kiểu dữ liệu TypeScript được sinh từ đặc tả API:
  `npx openapi-typescript@7.4.4 api/openapi.yaml -o src/api/schema.d.ts`.
- API cây gia phả (`GET /clans/{clanId}/tree`) trả về `persons` và `unions` dạng phẳng; bố cục được dựng
  bằng React Flow kết hợp elkjs.
- Quyền hiển thị chức năng lấy từ `Clan.myAccess` (vai trò, phạm vi, nhóm trường) và `GET /clans/{clanId}/entitlements`
  (gói, tính năng, hạn mức).

### Backend
- Thiết kế entity và repository tuân theo GP-DOC-02 mục 12 và GP-DOC-03 mục 8–10.
- Ứng dụng kết nối bằng tài khoản `gp_app`. Cấu hình `spring.flyway.enabled=false` (migration chạy riêng bằng
  `gp_owner`) và `spring.jpa.hibernate.ddl-auto=validate`.
- Interface controller được sinh từ đặc tả API bằng openapi-generator (`interfaceOnly=true`), bảo đảm sai lệch
  so với đặc tả được phát hiện khi biên dịch.
- Biến môi trường: `JWT_SECRET`, `DB_URL`, `DB_USER=gp_app`, `DB_PASSWORD`, `REDIS_URL`, `REDIS_PASSWORD`,
  `SMTP_HOST`, `SMTP_PORT`, `VNPAY_TMN_CODE`, `VNPAY_HASH_SECRET`, `VNPAY_PAY_URL`, `VNPAY_RETURN_URL`, `FRONTEND_URL`.
- Tác vụ định kỳ của backend được liệt kê tại GP-DOC-05 mục 7.

## Quy trình đóng góp
Quy trình chi tiết tại GP-DOC-06.

- Mọi thay đổi vào nhánh `main` được thực hiện qua pull request và phải được review.
- Thay đổi API được thực hiện qua pull request sửa `api/openapi.yaml`.
- Thay đổi lược đồ được thực hiện bằng migration Flyway mới; migration đã merge không được sửa.
