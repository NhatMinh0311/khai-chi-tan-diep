# ADR-0006: Chế độ xem dùng chung cho thành viên và link chia sẻ

| Thuộc tính | Giá trị |
|---|---|
| Trạng thái | Đã chấp nhận |
| Ngày | 14/10/2026 |

## Bối cảnh
Trưởng tộc cần quy định phạm vi (nhánh, số đời) và các trường thông tin được hiển thị, áp dụng cho toàn bộ thành viên
và cho từng link chia sẻ. Thiết kế ban đầu cố định các mức hiển thị theo vai trò và đặt phạm vi riêng trên từng thành viên,
không đáp ứng được việc điều chỉnh đồng loạt.

## Quyết định
Một thực thể `view_policy` gồm phạm vi (`CLAN`, `BRANCH`, `RELATIVE`) và danh sách nhóm trường, được tham chiếu bởi:
cấu hình mặc định của dòng họ cho MEMBER, chế độ riêng của từng thành viên, và mỗi link chia sẻ. Một bộ hàm duy nhất
(`app_effective_policy`, `app_visible_person_ids`, `app_visible_field_groups`) tính quyền cho mọi chủ thể.
Trần an toàn áp dụng cho link (không `RELATIVE`; chỉ `BASIC`, `LIFE_EVENTS`, `BIOGRAPHY`) được bảo đảm bằng trigger,
kể cả khi chế độ xem bị sửa sau khi đã gắn với link.

## Phương án đã cân nhắc
| Phương án | Lý do không chọn |
|---|---|
| Mức hiển thị cố định theo vai trò | Không cấu hình được theo nhu cầu từng dòng họ |
| Cấu hình nhúng trực tiếp trong từng link và từng thành viên | Lặp cấu hình; sửa đồng loạt phải cập nhật nhiều bản ghi |
| Dùng link chia sẻ làm cơ chế giới hạn thành viên | Link là quyền truy cập ẩn danh theo token; trộn với tư cách thành viên làm mất truy vết và khả năng thu hồi theo người |

## Hệ quả
- (+) Sửa chế độ xem mặc định áp dụng ngay cho toàn bộ thành viên (T23).
- (+) Một ma trận kiểm thử cho cả thành viên và khách.
- (+) Phạm vi tương đối cho phép mỗi thành viên xem "nhánh của mình" mà không cần cấu hình riêng.
- (−) Phạm vi tương đối yêu cầu tài khoản đã gắn hồ sơ; thành viên chưa gắn hồ sơ không có phạm vi.
- (−) Đánh giá chế độ xem là chi phí tham gia mọi truy vấn; được giảm bằng InitPlan và kiểm tra `CLAN` trước.
