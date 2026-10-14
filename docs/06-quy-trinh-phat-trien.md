# Quy trình phát triển và CI/CD

| Thuộc tính | Giá trị |
|---|---|
| Mã tài liệu | GP-DOC-06 |
| Phiên bản | 1.2 |
| Ngày ban hành | 15/10/2026 |
| Tài liệu liên quan | `.github/CODEOWNERS`, `.github/pull_request_template.md`, `.github/workflows/ci.yml`, `.github/rulesets/main-branch-protection.json` |

## 1. Phạm vi

Tài liệu quy định cách quản lý mã nguồn, quy trình pull request, cấu hình bảo vệ nhánh trên GitHub, pipeline tích hợp
liên tục (CI) và lộ trình triển khai liên tục (CD) của dự án Khai Chi Tán Diệp.

| Thành phần | Vai trò trong quy trình | Vị trí cấu hình |
|---|---|---|
| Ruleset bảo vệ nhánh | Chặn thay đổi vào `main` khi chưa qua review và CI | GitHub Settings (mục 4) |
| CODEOWNERS | Chỉ định người review bắt buộc | `.github/CODEOWNERS` |
| Mẫu pull request | Chuẩn hóa mô tả và danh mục kiểm tra | `.github/pull_request_template.md` |
| CI | Kiểm tra tự động mỗi pull request | `.github/workflows/ci.yml` |
| CD | Triển khai tự động lên staging | Chưa triển khai (mục 7) |

## 2. Kho mã

- Kho mã: `github.com/NhatMinh0311/khai-chi-tan-diep`.
- Nhánh `main` luôn ở trạng thái chạy được; mọi thay đổi vào `main` đi qua pull request.
- Nhánh làm việc được tạo từ `main`, đặt tên theo loại thay đổi:

| Tiền tố | Dùng cho | Ví dụ |
|---|---|---|
| `feat/` | Tính năng mới | `feat/view-policy-api` |
| `fix/` | Sửa lỗi | `fix/tree-spouse-order` |
| `docs/` | Tài liệu | `docs/cap-nhat-phan-quyen` |
| `test/` | Kiểm thử | `test/rls-share-link` |
| `chore/` | Hạ tầng, cấu hình, CI | `chore/thiet-lap-repo` |

- Pull request được merge bằng **squash**: mỗi pull request trở thành một commit trên `main`, lịch sử tuyến tính.

## 3. Quy trình pull request

1. Tạo nhánh từ `main`, thực hiện thay đổi, push nhánh lên GitHub.
2. Mở pull request vào `main`. Mô tả theo mẫu, ghi mã yêu cầu liên quan (ví dụ `US-04`, `AC-04.6`, `F08`).
3. CI chạy tự động. Pull request chỉ merge được khi mọi kiểm tra bắt buộc thành công.
4. Người review bắt buộc (CODEOWNERS) xem xét. Mọi trao đổi phải được giải quyết trước khi merge.
5. Commit mới đẩy lên sau khi đã được duyệt làm mất hiệu lực lượt duyệt cũ; pull request cần được duyệt lại.
6. Merge bằng squash; nhánh làm việc được xóa sau khi merge.

Lệnh và thao tác chi tiết cho thành viên, cùng quy tắc theo loại thay đổi (đặc tả API, migration, tài liệu),
được quy định tại `CONTRIBUTING.md`.

## 4. Cấu hình bảo vệ nhánh `main`

Ruleset **"main branch protection"** (GitHub → Settings → Rules → Rulesets):

| Mục | Giá trị | Mục đích |
|---|---|---|
| Enforcement status | Active | Ruleset có hiệu lực |
| Target branches | Nhánh mặc định (`main`) | |
| Bypass list | Repository admin — chỉ qua pull request | Trưởng nhóm merge được pull request của chính mình (GitHub không cho tự duyệt), nhưng không push thẳng được vào `main` |
| Restrict deletions | Bật | Không xóa được `main` |
| Require linear history | Bật | Lịch sử không có merge commit |
| Block force pushes | Bật | Không ghi đè lịch sử |
| Require a pull request before merging | Bật | Mọi thay đổi đi qua pull request |
| — Required approvals | 1 | |
| — Dismiss stale pull request approvals when new commits are pushed | Bật | Lượt duyệt chỉ áp dụng cho nội dung đã được xem |
| — Require review from Code Owners | Bật | Lượt duyệt bắt buộc phải từ người trong CODEOWNERS |
| — Require approval of the most recent reviewable push | Bật | Người đẩy commit cuối không tự đáp ứng điều kiện duyệt |
| — Require conversation resolution before merging | Bật | Mọi góp ý phải được xử lý |
| — Require an additional approval for unattributed Copilot pull requests | Bật | Pull request do tác tử Copilot tạo cần thêm lượt duyệt của người |
| — Allowed merge methods | Squash | |
| Require status checks to pass | Bật, kiểm tra `api-lint`, `db-tests` | CI phải thành công trước khi merge |
| — Require branches to be up to date before merging | Tắt | Nhánh không bắt buộc cập nhật theo `main` trước khi merge; squash merge và CI trên `main` phát hiện xung đột sau merge |
| Các quy tắc còn lại | Tắt | |

**Lý do cần CODEOWNERS.** Nếu chỉ yêu cầu một lượt duyệt, hai thành viên bất kỳ có quyền ghi có thể duyệt pull request
của nhau và merge mà không qua trưởng nhóm. Tùy chọn "Require review from Code Owners" kết hợp `.github/CODEOWNERS`
(`* @NhatMinh0311`) buộc mọi pull request phải được trưởng nhóm duyệt.

**Phân quyền kho mã.**

| Thành viên | Quyền |
|---|---|
| Trưởng nhóm (QA, DevOps, kiểm thử bảo mật) | Admin |
| Backend, Frontend | Write (không sửa được ruleset, không bỏ qua được quy tắc) |

Ruleset được xuất ra JSON (Rulesets → Export) và lưu tại `.github/rulesets/main-branch-protection.json` mỗi khi cấu hình thay đổi,
để cấu hình được quản lý phiên bản cùng mã nguồn.

## 5. Pipeline CI

Workflow `.github/workflows/ci.yml` chạy khi có pull request vào `main` và khi có commit trên `main`.
Mỗi lần chạy mới của cùng một nhánh hủy lần chạy cũ đang dở.

| Job | Nội dung | Kiểm chứng |
|---|---|---|
| `api-lint` | `redocly lint api/openapi.yaml` | Đặc tả API hợp lệ theo OpenAPI 3.1 và bộ quy tắc `recommended`; các ngoại lệ có chủ ý được ghi tại `.redocly.lint-ignore.yaml` |
| `db-tests` | Dựng PostgreSQL bằng Docker Compose, áp dụng migration bằng Flyway, chạy `db/tests/run.sh` | Migration áp dụng được trên cơ sở dữ liệu trống; toàn bộ kiểm thử RLS, ràng buộc và hàm nghiệp vụ thành công |

- Mật khẩu cơ sở dữ liệu trong CI được sinh ngẫu nhiên ở mỗi lần chạy; workflow không dùng secret của kho mã.
- Workflow chỉ có quyền đọc nội dung kho mã (`permissions: contents: read`).
- Khi `db-tests` thất bại, log PostgreSQL được in ra để chẩn đoán.

Các job được bổ sung khi mã nguồn backend và frontend có mặt:

| Job | Nội dung |
|---|---|
| `backend-build` | Biên dịch, unit test, integration test với Testcontainers |
| `frontend-build` | Kiểm tra kiểu, lint, component test, build |
| `contract-check` | So khớp interface sinh từ đặc tả API với mã backend; sinh kiểu TypeScript cho frontend |
| `security-scan` | Quét phụ thuộc và image (Trivy), quét bí mật (gitleaks) |
| `e2e` | Playwright trên môi trường dựng bằng Docker Compose |

## 6. Truy vết

| Đối tượng | Truy vết qua |
|---|---|
| Thay đổi mã nguồn | Commit trên `main`, mỗi commit tương ứng một pull request |
| Lý do thay đổi | Mô tả pull request, mã yêu cầu liên kết |
| Người duyệt | Lịch sử review của pull request |
| Kết quả kiểm thử | Lịch sử chạy GitHub Actions gắn với từng pull request |
| Cấu hình bảo vệ nhánh | `.github/rulesets/main-branch-protection.json` |

## 7. Triển khai liên tục (CD)

Thành phần CD chưa được triển khai. Thiết kế dự kiến:

| Giai đoạn | Kích hoạt | Nội dung |
|---|---|---|
| Build image | Commit trên `main` sau khi CI thành công | Build image backend, frontend; gắn tag theo commit; đẩy lên GitHub Container Registry |
| Triển khai staging | Sau build image | Cập nhật Docker Compose trên máy chủ staging; chạy migration bằng `gp_owner` trước khi khởi động backend |
| Kiểm tra sau triển khai | Sau triển khai | Kiểm tra `/actuator/health`; quét OWASP ZAP baseline trên staging |

## Lịch sử thay đổi

| Phiên bản | Ngày | Nội dung |
|---|---|---|
| 1.2 | 15/10/2026 | Tham chiếu hướng dẫn thao tác `CONTRIBUTING.md` |
| 1.1 | 15/10/2026 | Cập nhật tên ruleset, đường dẫn tệp xuất và tùy chọn cập nhật nhánh theo cấu hình thực tế |
| 1.0 | 15/10/2026 | Ban hành lần đầu |
