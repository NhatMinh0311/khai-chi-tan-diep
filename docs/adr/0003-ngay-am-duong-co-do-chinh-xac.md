# ADR-0003: Lưu độc lập ngày âm lịch và dương lịch kèm độ chính xác

| Thuộc tính | Giá trị |
|---|---|
| Trạng thái | Đã chấp nhận |
| Ngày | 14/10/2026 |

## Bối cảnh
Gia phả cũ thường chỉ ghi năm, hoặc chỉ ghi ngày giỗ theo âm lịch; nhiều thông tin ở dạng "chưa rõ" hoặc "khoảng".
Kiểu `DATE` không biểu diễn được các trường hợp này. Chức năng lịch giỗ cần ngày mất âm lịch, bao gồm tháng nhuận.

## Quyết định
Mỗi sự kiện lưu hai giá trị: dương lịch (`precision`, `year`, `month`, `day`, `approximate`) và âm lịch
(bổ sung `leap`), với `precision` thuộc {UNKNOWN, YEAR, MONTH, DAY}. Tính hợp lệ của từng giá trị được kiểm tra
bằng ràng buộc `CHECK`. Sự nhất quán giữa hai giá trị được backend kiểm tra theo quy tắc giao khoảng (GP-DOC-02 mục 5.3).
Quy đổi chỉ áp dụng cho mức `DAY`, theo lịch Việt Nam tính tại UTC+7.

## Phương án đã cân nhắc
| Phương án | Lý do không chọn |
|---|---|
| Một cột `DATE` kèm cờ độ chính xác | Phải gán giá trị giả cho ngày, tháng chưa biết; không lưu được âm lịch |
| Chỉ lưu dương lịch, tính âm lịch khi hiển thị | Không quy đổi được khi chỉ biết năm; nguồn gia phả gốc ghi theo âm lịch |
| Kiểu JSONB | Cơ sở dữ liệu không kiểm tra được tính hợp lệ; khó truy vấn theo năm |
| Bảng sự kiện riêng | Tăng số phép join và độ phức tạp ánh xạ; chưa cần thiết ở phạm vi hiện tại |

## Hệ quả
- (+) Lưu đúng thông tin nguồn, không phát sinh dữ liệu giả.
- (+) Việc ẩn ngày sinh của người còn sống với MEMBER được thực hiện bằng cách hạ độ chính xác xuống `YEAR`.
- (−) Bảng `person` có 22 cột ngày; tầng ánh xạ sử dụng `@Embeddable` để tránh lặp mã.
