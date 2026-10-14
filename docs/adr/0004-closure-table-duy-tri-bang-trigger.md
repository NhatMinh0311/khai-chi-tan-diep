# ADR-0004: Bảng closure được dựng lại theo dòng họ bằng trigger

| Thuộc tính | Giá trị |
|---|---|
| Trạng thái | Đã chấp nhận, kèm điều kiện xem xét lại |
| Ngày | 14/10/2026 |

## Bối cảnh
Phân quyền theo nhánh yêu cầu kiểm tra trong RLS điều kiện "người X nằm trong N đời dưới người gốc R".
Thực hiện truy vấn đệ quy tại mỗi lần kiểm tra có chi phí cao.

## Quyết định
Bảng `person_closure(ancestor, descendant, depth)` lưu số đời ngắn nhất của mọi cặp tổ tiên – hậu duệ.
Trigger trên `union_child` và `family_union` dựng lại closure của toàn bộ dòng họ bị ảnh hưởng bằng truy vấn
đệ quy có mệnh đề `CYCLE`; khi phát hiện quan hệ tổ tiên vòng, transaction bị hủy. Advisory lock theo dòng họ
bảo đảm các lần dựng lại được thực hiện tuần tự. Tầng ứng dụng chỉ có quyền đọc bảng này.

## Phương án đã cân nhắc
| Phương án | Lý do không chọn |
|---|---|
| Truy vấn đệ quy tại mỗi lần đọc | Chạy trong RLS cho mọi truy vấn, chi phí cao |
| Cập nhật closure từng phần | Hiệu năng ghi tốt hơn nhưng dễ sai với hôn nhân trong họ và thao tác xóa cạnh |
| `ltree` hoặc materialized path | Chỉ phù hợp cấu trúc cây; gia phả có nhiều đường đi |
| Tầng ứng dụng tự cập nhật closure | Sai sót ở tầng ứng dụng dẫn tới phân quyền sai |

## Hệ quả
- (+) Kiểm tra phạm vi là một phép tra chỉ mục; tính đời là một phép join.
- (+) Tính toàn vẹn (không có quan hệ tổ tiên vòng) được cơ sở dữ liệu bảo đảm.
- (−) Mỗi thao tác ghi quan hệ dựng lại closure của cả dòng họ.

## Điều kiện xem xét lại
Đánh giá hiệu năng với dữ liệu 5.000 người / 15 đời, gồm thời gian dựng lại closure khi ghi và độ trễ
`GET /tree` khi dùng closure so với truy vấn đệ quy. Nếu thời gian dựng lại vượt 200 ms, chuyển sang phương án
cập nhật từng phần.
