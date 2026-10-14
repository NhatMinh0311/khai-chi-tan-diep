# ADR-0008: Một trưởng tộc, người kế nhiệm chỉ định trước và quy trình chuyển giao có thời gian chờ

| Thuộc tính | Giá trị |
|---|---|
| Trạng thái | Đã chấp nhận |
| Ngày | 14/10/2026 |

## Bối cảnh
Dòng họ cần một người chịu trách nhiệm quản trị. Rủi ro chính: trưởng tộc không còn hoạt động (quên mật khẩu,
qua đời, bỏ dùng hệ thống) khiến dòng họ mất người quản trị; ngược lại, cơ chế khôi phục có thể bị lợi dụng để chiếm quyền.

## Quyết định
- Mỗi dòng họ có **đúng một** OWNER, bảo đảm bằng chỉ mục duy nhất và trigger.
- OWNER chỉ định trước một người kế nhiệm.
- Ba quy trình chuyển giao: chủ động; tiếp quản bởi người kế nhiệm khi OWNER không hoạt động, sau thời gian chờ;
  đơn khôi phục do EDITOR lập, cần xác nhận của ⌈2/3⌉ số EDITOR và SUPPORT duyệt.
- Mọi bước khởi tạo và chấp nhận yêu cầu step-up. OWNER hoạt động trở lại trong thời gian chờ thì yêu cầu tự hủy.
- Quy trình được hiện thực bằng hàm cơ sở dữ liệu; tầng ứng dụng không thay đổi được vai trò OWNER trực tiếp.

## Phương án đã cân nhắc
| Phương án | Lý do không chọn |
|---|---|
| Nhiều đồng quản trị ngang quyền | Khó xác định trách nhiệm; dễ phát sinh tranh chấp nội bộ |
| Trưởng tộc và phó trưởng tộc gần đủ quyền | Thêm một vai trò cần phân định quyền; người kế nhiệm đáp ứng mục tiêu liên tục quản trị với ít quyền hơn |
| Chỉ dựa vào quản trị viên nền tảng | Không mở rộng được; quản trị viên thiếu thông tin về dòng họ |

## Hệ quả
- (+) Dòng họ không bị mất người quản trị vĩnh viễn.
- (+) Chiếm quyền đòi hỏi vượt qua step-up, thời gian chờ có thông báo, và (với đơn khôi phục) xác nhận tập thể cùng xét duyệt.
- (−) Quy trình tiếp quản mất tối thiểu 30 ngày theo cấu hình mặc định.
- (−) Phụ thuộc chức năng gửi email để thông báo tới OWNER.
