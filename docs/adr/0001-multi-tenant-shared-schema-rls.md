# ADR-0001: Multi-tenant bằng lược đồ dùng chung và Row-Level Security

| Thuộc tính | Giá trị |
|---|---|
| Trạng thái | Đã chấp nhận |
| Ngày | 14/10/2026 |

## Bối cảnh
Nhiều dòng họ sử dụng chung một hệ thống. Dữ liệu của mỗi dòng họ, bao gồm thông tin người còn sống và quan hệ
nhạy cảm, không được lộ sang dòng họ khác. Nguyên nhân rò rỉ phổ biến nhất ở hệ thống multi-tenant là truy vấn
thiếu điều kiện lọc theo tenant.

## Quyết định
Các dòng họ dùng chung một lược đồ; mỗi bảng thuộc dòng họ có cột `clan_id`. Việc cách ly được bảo đảm ở hai lớp:
1. Tầng service lọc dữ liệu theo dòng họ và phạm vi.
2. PostgreSQL Row-Level Security lọc lại theo ngữ cảnh phiên (`app.clan_id`, `app.user_id`, `app.share_link_id`)
   và kiểm tra tư cách thành viên. Khóa ngoại kép `(clan_id, id)` ngăn tham chiếu giữa các dòng họ.

Backend kết nối bằng tài khoản `gp_app`, không sở hữu bảng và không có quyền `BYPASSRLS`.

## Phương án đã cân nhắc
| Phương án | Lý do không chọn |
|---|---|
| Mỗi dòng họ một lược đồ | Migration phải chạy lặp theo số dòng họ; quản lý kết nối phức tạp; không tương xứng quy mô hệ thống |
| Mỗi dòng họ một cơ sở dữ liệu | Các nhược điểm trên ở mức cao hơn |
| Chỉ lọc tại tầng ứng dụng | Một truy vấn thiếu điều kiện lọc dẫn tới rò rỉ dữ liệu; không có lớp phòng thủ thứ hai |

## Hệ quả
- (+) Truy vấn thiếu điều kiện lọc không làm lộ dữ liệu; được chứng minh bằng test T02, T03.
- (+) Một bộ migration và một pool kết nối.
- (−) Backend phải đặt ngữ cảnh ở đầu mỗi transaction; thiếu ngữ cảnh dẫn tới kết quả rỗng.
- (−) Hàm kiểm tra phạm vi tham gia mọi truy vấn, phát sinh chi phí hiệu năng cần được đo lường.
- (−) `INSERT ... RETURNING` bị từ chối đối với EDITOR có phạm vi giới hạn; khóa chính phải được sinh tại tầng ứng dụng.
