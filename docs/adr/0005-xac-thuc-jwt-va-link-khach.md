# ADR-0005: Xác thực bằng JWT, refresh token xoay vòng, xác thực bổ sung và phiên khách qua link

| Thuộc tính | Giá trị |
|---|---|
| Trạng thái | Đã chấp nhận (sửa đổi 14/10/2026: bổ sung xác minh email, đặt lại mật khẩu, step-up) |
| Ngày | 14/10/2026 |

## Quyết định
- **Access token**: JWT ký HS256 bằng khóa tối thiểu 256 bit lấy từ biến môi trường; thời hạn 15 phút.
  Token chỉ chứa danh tính (`sub`, `typ`), không chứa vai trò. Frontend lưu token trong bộ nhớ, không lưu vào localStorage.
- **Refresh token**: chuỗi ngẫu nhiên trong cookie `gp_refresh` (HttpOnly, Secure, SameSite=Strict,
  Path=/api/v1/auth); cơ sở dữ liệu lưu SHA-256. Token được xoay vòng sau mỗi lần sử dụng; việc sử dụng lại
  token cũ dẫn tới thu hồi toàn bộ chuỗi token. Các endpoint dùng cookie yêu cầu header `X-Requested-With` để chống CSRF.
- **Mật khẩu**: bcrypt với cost 12; độ dài 10–128 ký tự. Đăng nhập sai 5 lần trong 15 phút theo cặp (IP, email)
  dẫn tới phản hồi 429; bộ đếm lưu trong Redis.
- **Xác minh email và đặt lại mật khẩu**: token dùng một lần lưu SHA-256 trong `one_time_token`; email gửi qua
  `email_outbox` (ADR-0010). Đặt lại mật khẩu thu hồi mọi refresh token của tài khoản.
- **Xác thực bổ sung (step-up)**: mật khẩu và OTP 6 chữ số qua email, phát hành JWT `typ=step_up` hiệu lực 5 phút,
  dùng một lần (đánh dấu `jti` trong Redis). Áp dụng cho chuyển giao quyền trưởng tộc (GP-DOC-05 mục 3).
- **Khách**: token link (32 byte) đặt sau ký tự `#` của URL; `POST /shared/sessions` đổi token lấy JWT khách
  (`typ=guest`) có hiệu lực 30 phút. Quyền truy cập dữ liệu được RLS kiểm tra tại mỗi truy vấn, do đó việc
  thu hồi link có hiệu lực tức thời.

## Phương án đã cân nhắc
| Phương án | Lý do không chọn |
|---|---|
| Session phía máy chủ lưu trong Redis | Redis có trong hệ thống nhưng được dùng làm cache không lưu bền (ADR-0009); session phụ thuộc Redis làm mất phiên khi Redis khởi động lại. JWT kết hợp kiểm tra quyền tại cơ sở dữ liệu đã đáp ứng yêu cầu thu hồi tức thời |
| Đưa vai trò vào claim của JWT | Thay đổi vai trò không có hiệu lực cho tới khi token hết hạn |
| Lưu access token trong localStorage | Có thể bị đánh cắp qua XSS |
| Đặt token khách trong query string | Token xuất hiện trong log máy chủ và header Referer |
| TOTP (ứng dụng xác thực) cho step-up | Tăng độ phức tạp đăng ký thiết bị; OTP qua email đủ cho tần suất sử dụng thấp của thao tác chuyển giao |

## Hệ quả
- (+) API không trạng thái, kiểm thử được bằng công cụ dòng lệnh.
- (+) Thay đổi quyền, khóa tài khoản, tạm ngưng dòng họ có hiệu lực từ yêu cầu kế tiếp.
- (−) Access token không thu hồi được trước khi hết hạn 15 phút. Rủi ro được chấp nhận do quyền và trạng thái tài khoản
  được kiểm tra lại tại mỗi truy vấn.
- (−) Bảo mật của step-up phụ thuộc bảo mật hộp thư email của người dùng.
