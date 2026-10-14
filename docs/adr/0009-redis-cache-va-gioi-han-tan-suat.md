# ADR-0009: Redis cho cache và giới hạn tần suất

| Thuộc tính | Giá trị |
|---|---|
| Trạng thái | Đã chấp nhận |
| Ngày | 14/10/2026 |

## Bối cảnh
API cây gia phả và link chia sẻ công khai là các điểm có tải đọc cao. Giới hạn tần suất (đăng nhập, phiên khách,
quên mật khẩu) cần bộ đếm dùng chung khi chạy nhiều bản backend. Đồng thời, hệ thống yêu cầu thu hồi quyền có hiệu lực tức thời.

## Quyết định
Sử dụng Redis 7, không lưu bền, chính sách `allkeys-lru`, yêu cầu mật khẩu, chỉ truy cập trong mạng nội bộ.

| Mục đích | Khóa | TTL |
|---|---|---|
| Dữ liệu cây đã ẩn trường | `tree:{clanId}:{dataVersion}:{policyFingerprint}:{root}:{down}:{up}:{spouses}` | 10 phút |
| Quy đổi âm lịch – dương lịch | `cal:{chiều}:{y}-{m}-{d}[:leap]` | 30 ngày |
| Danh mục gói | `plans:public` | 5 phút; xóa khi quản trị viên sửa gói |
| Giới hạn tần suất | `rl:{loại}:{khóa}` (ví dụ `rl:login:{ip}:{email}`) | Theo cửa sổ |
| Step-up token đã dùng | `stepup:used:{jti}` | Thời hạn của token |

Quy tắc bắt buộc (GP-DOC-03 mục 9): quyết định phân quyền luôn đọc từ cơ sở dữ liệu trước khi tra cache; khóa cache
chứa phiên bản dữ liệu và dấu vân tay của chế độ xem hiệu lực.

## Phương án đã cân nhắc
| Phương án | Lý do không chọn |
|---|---|
| Cache trong bộ nhớ của từng bản backend (Caffeine) | Không dùng chung giữa các bản; bộ đếm giới hạn tần suất sai khi mở rộng |
| Cache kết quả phân quyền | Thu hồi quyền không có hiệu lực tức thời |
| Xóa cache chủ động khi dữ liệu thay đổi | Dễ bỏ sót; khóa theo phiên bản dữ liệu loại bỏ nhu cầu xóa |

## Hệ quả
- (+) Giảm tải truy vấn đệ quy cho cây và link công khai.
- (+) Giới hạn tần suất đúng khi chạy nhiều bản backend.
- (−) Redis chứa dữ liệu cá nhân đã ẩn trường; được bảo vệ bằng mật khẩu, mạng nội bộ, TTL và không lưu bền.
- (−) Redis gián đoạn: backend bỏ qua cache và đọc trực tiếp cơ sở dữ liệu; giới hạn tần suất chuyển sang chế độ từ chối
  với các endpoint xác thực.
