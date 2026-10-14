# ADR-0002: Quan hệ gia đình gắn qua hôn phối

| Thuộc tính | Giá trị |
|---|---|
| Trạng thái | Đã chấp nhận |
| Ngày | 14/10/2026 |

## Bối cảnh
Gia phả Việt Nam có các trường hợp nhiều vợ hoặc chồng (đồng thời hoặc nối tiếp), con nuôi, con chỉ xác định
được một bên cha hoặc mẹ, và yêu cầu phân biệt con của từng hôn phối.

## Quyết định
Sử dụng hai bảng: `family_union` (một hoặc hai người) và `union_child` (người con, loại quan hệ đẻ hoặc nuôi,
thứ tự sinh). Mỗi người có tối đa một gia đình đẻ và không giới hạn số gia đình nuôi. Mô hình tương ứng với
cấu trúc FAM/CHIL của chuẩn GEDCOM.

## Phương án đã cân nhắc
| Phương án | Lý do không chọn |
|---|---|
| Cột `father_id`, `mother_id` trên bảng `person` | Không biểu diễn được con nuôi, nhiều gia đình nuôi và thứ tự hôn phối |
| Bảng cạnh `parent_child(parent_id, child_id)` | Không xác định được người con thuộc hôn phối nào; dễ mất nhất quán với bảng hôn phối |

## Hệ quả
- (+) Bố cục cây biểu diễn mỗi hôn phối thành một nút, người con nằm dưới hôn phối tương ứng.
- (+) API cây trả về `persons` và `unions` dạng phẳng, ánh xạ trực tiếp sang thư viện vẽ đồ thị.
- (−) Thao tác thêm con yêu cầu xác định hôn phối; trường hợp không rõ cha hoặc mẹ cần tạo hôn phối một bên.
