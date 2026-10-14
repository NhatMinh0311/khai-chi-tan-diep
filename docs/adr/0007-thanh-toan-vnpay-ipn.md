# ADR-0007: Thanh toán qua VNPay, kích hoạt gói chỉ bằng IPN

| Thuộc tính | Giá trị |
|---|---|
| Trạng thái | Đã chấp nhận |
| Ngày | 14/10/2026 |

## Bối cảnh
Gói trả phí cần được thanh toán trực tuyến. Hệ thống phục vụ người dùng tại Việt Nam, thanh toán bằng VND.

## Quyết định
- Tích hợp VNPay ở môi trường sandbox; chuyển sang môi trường thật chỉ thay đổi cấu hình.
- Số tiền do cơ sở dữ liệu tính từ bảng `plan` (`gp_create_payment`).
- **Chỉ IPN** (máy chủ VNPay gọi máy chủ hệ thống) kích hoạt gói, sau khi xác minh chữ ký HMAC-SHA512 và số tiền.
  Trang trả về của trình duyệt chỉ hiển thị kết quả.
- `gp_confirm_payment` khóa dòng giao dịch và xử lý idempotent.
- Bảng `payment_transaction` có cột `provider`, cho phép bổ sung nhà cung cấp khác mà không đổi lược đồ.
- `SYSTEM_ADMIN` cấp gói thủ công cho các trường hợp ngoại lệ.

## Phương án đã cân nhắc
| Phương án | Lý do không chọn |
|---|---|
| Kích hoạt thủ công bởi quản trị viên | Không tự động; không đáp ứng mục tiêu vận hành dạng dịch vụ |
| Stripe (chế độ test) | Không phù hợp thanh toán nội địa bằng VND |
| Kích hoạt gói tại trang trả về | Tham số trên URL trình duyệt có thể bị giả mạo hoặc không bao giờ tới (người dùng đóng trình duyệt) |

## Hệ quả
- (+) Kích hoạt gói không phụ thuộc trình duyệt của người dùng.
- (+) IPN lặp lại không gây cộng thời gian hai lần (T33).
- (−) Môi trường phát triển cục bộ không nhận được IPN từ VNPay; cần địa chỉ công khai (staging) hoặc công cụ tạo
  đường hầm khi kiểm thử tích hợp.
