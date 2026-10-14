# ADR-0010: Gửi email qua hàng đợi outbox trong cơ sở dữ liệu

| Thuộc tính | Giá trị |
|---|---|
| Trạng thái | Đã chấp nhận |
| Ngày | 14/10/2026 |

## Bối cảnh
Nhiều nghiệp vụ phát sinh email: xác minh email, đặt lại mật khẩu, OTP, lời mời, thông báo chuyển giao trưởng tộc,
kết quả thanh toán. Email không được mất khi máy chủ SMTP gián đoạn, và không được gửi khi transaction nghiệp vụ bị hủy.

## Quyết định
- Email được ghi vào bảng `email_outbox` trong cùng transaction với thay đổi nghiệp vụ.
- Tiến trình nền của backend đọc các dòng `PENDING` đến hạn bằng `SELECT ... FOR UPDATE SKIP LOCKED`, gửi qua SMTP,
  thử lại với khoảng chờ tăng dần, tối đa 8 lần trước khi chuyển sang `FAILED`.
- Giá trị bí mật trong `payload` (OTP, token) được xóa khỏi dòng ngay sau khi gửi thành công. Dòng đã gửi được xóa sau 30 ngày.
- Môi trường phát triển dùng Mailpit; staging và production dùng nhà cung cấp SMTP cấu hình qua biến môi trường.

| Template | Người nhận |
|---|---|
| `EMAIL_VERIFY`, `PASSWORD_RESET`, `STEP_UP_OTP` | Chủ tài khoản |
| `INVITATION` | Người được mời |
| `OWNERSHIP_TRANSFER_REQUEST` | Người nhận chuyển giao |
| `OWNERSHIP_TAKEOVER_NOTICE`, `OWNERSHIP_RECOVERY_NOTICE`, `OWNERSHIP_WAITING_REMINDER` | OWNER hiện tại |
| `OWNERSHIP_TRANSFER_COMPLETED` | OWNER cũ và OWNER mới |
| `PAYMENT_SUCCEEDED` | OWNER |
| `CLAN_SUSPENDED` | OWNER |

## Phương án đã cân nhắc
| Phương án | Lý do không chọn |
|---|---|
| Gửi trực tiếp trong request | Mất email khi SMTP lỗi; email đã gửi dù transaction bị hủy |
| Hàng đợi riêng (RabbitMQ, Kafka) | Thêm thành phần hạ tầng; không đảm bảo nguyên tử với transaction cơ sở dữ liệu nếu không có outbox |

## Hệ quả
- (+) Email nhất quán với dữ liệu; không mất khi SMTP gián đoạn.
- (−) Độ trễ gửi phụ thuộc chu kỳ của tiến trình nền (10 giây).
