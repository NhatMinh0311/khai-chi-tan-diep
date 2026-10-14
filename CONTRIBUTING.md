# Hướng dẫn đóng góp

Tài liệu hướng dẫn các thao tác của thành viên khi đưa thay đổi vào kho mã. Quy trình và cấu hình bảo vệ nhánh
được quy định tại GP-DOC-06 (`docs/06-quy-trinh-phat-trien.md`).

Các lệnh dùng shell bash. Trên Windows, chạy trong WSL2 (khuyến nghị) hoặc Git Bash.

## 1. Chuẩn bị (thực hiện một lần)

### 1.1. Công cụ

| Công cụ | Phiên bản | Dùng cho |
|---|---|---|
| Git | 2.40 trở lên | Quản lý mã nguồn |
| Docker, Docker Compose v2 | Docker 24 trở lên | PostgreSQL, Redis, Mailpit, Flyway |
| Node.js | 22 LTS | Lint đặc tả API, mock API, frontend |
| JDK | 21 | Backend |

### 1.2. Cấu hình Git

Email trong cấu hình Git phải trùng một email đã khai báo trong tài khoản GitHub (Settings → Emails),
để commit được ghi nhận cho đúng người.

```bash
git config --global user.name  "<Tên hiển thị>"
git config --global user.email "<email-tài-khoản-github>"
git config --global init.defaultBranch main
git config --global pull.ff only
```

### 1.3. Khóa SSH

```bash
ls ~/.ssh/id_ed25519.pub || ssh-keygen -t ed25519 -C "<email-tài-khoản-github>"
cat ~/.ssh/id_ed25519.pub        # dán vào GitHub → Settings → SSH and GPG keys → New SSH key
ssh -T git@github.com            # kết quả mong đợi: "Hi <username>! You've successfully authenticated"
```

### 1.4. Nhận quyền truy cập và tải kho mã

1. Chấp nhận lời mời collaborator (email hoặc thông báo trên GitHub).
2. Tải kho mã và dựng môi trường:

```bash
git clone git@github.com:NhatMinh0311/khai-chi-tan-diep.git
cd khai-chi-tan-diep
cp .env.example .env                       # đặt mật khẩu trong .env; không commit tệp này
docker compose up -d --wait db redis mailpit
docker compose run --rm migrate
./db/tests/run.sh                          # kết quả mong đợi: "All database tests passed."
```

## 2. Thực hiện một thay đổi

### 2.1. Tạo nhánh từ `main` mới nhất

```bash
git switch main
git pull
git switch -c <loại>/<mô-tả-ngắn>          # ví dụ: feat/view-policy-api
```

Loại nhánh: `feat/`, `fix/`, `docs/`, `test/`, `chore/` (GP-DOC-06 mục 2). Mỗi nhánh giải quyết một việc;
thay đổi lớn được chia thành nhiều pull request nhỏ.

### 2.2. Commit

```bash
git status                                 # kiểm tra tệp thay đổi; không có .env, tệp tạm, thư mục build
git add <tệp>
git commit
```

Quy ước nội dung commit:
- Dòng đầu: câu ngắn mô tả thay đổi, tối đa 72 ký tự, không có dấu chấm cuối. Ví dụ: `Thêm API tạo chế độ xem`.
- Để trống một dòng, sau đó giải thích lý do thay đổi và mã yêu cầu liên quan (ví dụ `US-06`, `AC-06.2`).

### 2.3. Cập nhật theo `main` trước khi push

Khi `main` đã có commit mới kể từ lúc tạo nhánh:

```bash
git fetch origin
git rebase origin/main
```

Xử lý xung đột khi rebase:

```bash
git status                                 # liệt kê tệp xung đột
# sửa tệp, xóa các dấu <<<<<<< ======= >>>>>>>
git add <tệp-đã-sửa>
git rebase --continue                      # lặp lại cho tới khi hoàn tất
git rebase --abort                         # hủy rebase, quay về trạng thái trước đó
```

### 2.4. Kiểm tra cục bộ trước khi push

```bash
npx --yes @redocly/cli@1.34.5 lint api/openapi.yaml     # khi sửa đặc tả API
./db/tests/run.sh                                       # khi sửa migration hoặc kiểm thử cơ sở dữ liệu
```

Các lệnh kiểm tra của backend và frontend được bổ sung vào mục này khi mã nguồn tương ứng có mặt.

### 2.5. Push và mở pull request

```bash
git push -u origin <tên-nhánh>
```

Trên GitHub, bấm **Compare & pull request**, kiểm tra **base: `main`**, điền mô tả theo mẫu, bấm **Create pull request**.
Pull request chưa sẵn sàng để review được mở ở trạng thái **Draft**.

### 2.6. Theo dõi CI và review

- CI (`api-lint`, `db-tests`) chạy tự động. Kiểm tra thất bại: bấm **Details**, đọc log, sửa, commit, push lại.
- Người review để lại góp ý. Mỗi góp ý được sửa bằng commit mới hoặc trả lời, sau đó bấm **Resolve conversation**.
- Commit mới sau khi đã được duyệt làm mất lượt duyệt; pull request cần được duyệt lại.
- Sau khi rebase, nhánh cần push lại bằng lệnh sau; lệnh từ chối ghi đè nếu trên GitHub có commit chưa tải về:

```bash
git push --force-with-lease
```

Nhánh `main` không nhận push trực tiếp và không nhận force push.

### 2.7. Merge

Trưởng nhóm duyệt và thực hiện **Squash and merge** khi đủ điều kiện: một lượt duyệt của người review bắt buộc,
CI thành công, mọi trao đổi đã được giải quyết. Nhánh trên GitHub được xóa khi merge.

### 2.8. Dọn dẹp sau khi merge

```bash
git switch main
git pull
git fetch --prune
git branch -D <tên-nhánh>
```

Squash merge tạo commit mới trên `main`, Git không nhận ra nhánh cục bộ đã được merge; vì vậy dùng `-D`.

## 3. Quy tắc theo loại thay đổi

### 3.1. Đặc tả API

- Thay đổi API được thực hiện trong pull request riêng sửa `api/openapi.yaml`, merge **trước** khi hiện thực ở backend
  và frontend, để hai phía làm việc trên cùng một hợp đồng.
- Pull request hiện thực phải khớp đặc tả đã merge.

### 3.2. Migration cơ sở dữ liệu

- Mỗi thay đổi lược đồ là một tệp migration mới `db/migration/V<số>__<mô_tả>.sql`, với `<số>` là số kế tiếp
  của migration lớn nhất trên `main` tại thời điểm tạo.
- Migration đã merge không được sửa. Sửa lỗi bằng migration mới.
- Hai nhánh cùng tạo một số phiên bản: nhánh merge sau đổi số migration của mình sau khi rebase. CI phát hiện trường hợp
  trùng số (`db-tests` thất bại).
- Thay đổi RLS, quyền hoặc hàm nghiệp vụ đi kèm kiểm thử trong `db/tests/`.

### 3.3. Tài liệu

- Thay đổi hành vi hệ thống được cập nhật vào tài liệu tương ứng trong `docs/` trong cùng pull request.
- Tài liệu dùng văn phong chính thức của dự án.
- Thành viên sử dụng công cụ AI ghi nhật ký tại GP-DOC-07 theo quy trình mục 2.1 của tài liệu đó.

## 4. Xử lý tình huống thường gặp

| Tình huống | Xử lý |
|---|---|
| `git push` bị từ chối với thông báo về quy tắc bảo vệ `main` | Đã commit trực tiếp trên `main`. Xem dòng tiếp theo |
| Lỡ commit trên `main` cục bộ | `git switch -c <tên-nhánh>` (mang commit sang nhánh mới), `git switch main`, `git reset --hard origin/main`, `git switch <tên-nhánh>`, push nhánh |
| Lỡ commit tệp `.env` hoặc mật khẩu | Không push. Chạy `git reset --soft HEAD~1`, bỏ tệp khỏi danh sách (`git restore --staged <tệp>`), commit lại. Nếu đã push: báo trưởng nhóm để đổi mật khẩu bị lộ |
| `db-tests` thất bại trên CI nhưng chạy được ở máy | Chạy lại từ cơ sở dữ liệu trống: `docker compose down -v`, sau đó thực hiện lại mục 1.4 |
| `./db/tests/run.sh: Permission denied` | `chmod +x db/tests/run.sh db/init/00-roles.sh` |
| Script báo lỗi `\r` hoặc `bad interpreter` | Tệp bị đổi xuống dòng sang CRLF. Chạy `git add --renormalize . && git status`, commit kết quả |
