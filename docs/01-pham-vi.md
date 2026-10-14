# Đặc tả phạm vi và yêu cầu

| Thuộc tính | Giá trị |
|---|---|
| Mã tài liệu | GP-DOC-01 |
| Phiên bản | 1.2 |
| Ngày ban hành | 14/10/2026 |
| Tài liệu liên quan | GP-DOC-02 Mô hình dữ liệu, GP-DOC-03 Phân quyền, GP-DOC-04 Gói dịch vụ và thanh toán, GP-DOC-05 Quản trị nền tảng và chuyển giao trưởng tộc, `api/openapi.yaml` |

## 1. Mục đích

Tài liệu này xác định phạm vi chức năng, yêu cầu chức năng (dưới dạng user story kèm tiêu chí chấp nhận)
và yêu cầu phi chức năng của hệ thống quản lý gia phả. Mỗi tiêu chí chấp nhận có mã định danh dạng
`AC-xx.y`, dùng để truy vết từ test case. Mọi thay đổi phạm vi được thực hiện qua pull request sửa tài liệu này.

## 2. Mục tiêu hệ thống

Hệ thống là nền tảng web cho phép nhiều dòng họ lưu trữ và tra cứu gia phả, đáp ứng các yêu cầu cốt lõi:

1. **Cách ly dữ liệu giữa các dòng họ (multi-tenant).** Người dùng không đọc hoặc sửa được dữ liệu của dòng họ mà mình không thuộc về, kể cả khi tầng ứng dụng có lỗi lọc dữ liệu. Quản trị viên nền tảng cũng không đọc được dữ liệu gia phả.
2. **Phân quyền chi tiết đối với dữ liệu cá nhân nhạy cảm.** Quyền được xác định theo vai trò, theo phạm vi (nhánh, số đời) và theo nhóm trường thông tin; dữ liệu của người còn sống được bảo vệ ở mức cao nhất theo mặc định.
3. **Vận hành dạng dịch vụ có gói.** Mỗi dòng họ dùng một gói dịch vụ quy định hạn mức và tính năng; gói trả phí được thanh toán trực tuyến.
4. **Liên tục quản trị.** Quyền trưởng tộc được chuyển giao có kiểm soát, kể cả khi trưởng tộc không còn hoạt động.

## 3. Tác nhân

| Tác nhân | Phạm vi | Mô tả |
|---|---|---|
| Người dùng đã đăng nhập | Hệ thống | Có tài khoản; có thể chưa thuộc dòng họ nào |
| `SYSTEM_ADMIN` — Quản trị nền tảng | Hệ thống | Quản lý tài khoản, trạng thái dòng họ, gói dịch vụ, cấu hình hệ thống |
| `SUPPORT` — Hỗ trợ | Hệ thống | Tra cứu siêu dữ liệu, xét duyệt đơn khôi phục quyền trưởng tộc |
| `OWNER` — Trưởng tộc | Dòng họ | Toàn quyền trong dòng họ; mỗi dòng họ có đúng một OWNER |
| `EDITOR` — Người chép phả | Dòng họ | Thêm và sửa dữ liệu gia phả trong phạm vi được giao; không chia sẻ dữ liệu, không cấp quyền xem cho người khác |
| `MEMBER` — Thành viên | Dòng họ | Xem dữ liệu theo chế độ xem được áp dụng |
| `GUEST` — Khách | Dòng họ | Không cần tài khoản; truy cập qua link chia sẻ, xem theo chế độ xem của link |

Quyền chi tiết được quy định tại GP-DOC-03 và GP-DOC-05.

## 4. Chức năng thuộc MVP

| Mã | Chức năng |
|---|---|
| F01 | Đăng ký, đăng nhập, đăng xuất, làm mới phiên |
| F02 | Tạo dòng họ (người tạo trở thành `OWNER`, gói FREE); sửa thông tin dòng họ |
| F03 | Mời thành viên qua email, gán vai trò, chế độ xem và hồ sơ gắn sẵn; quản lý thành viên |
| F04 | Thêm, sửa, xóa người: họ tên, tên khác (tự, hiệu, húy), giới tính, ngày sinh và ngày mất theo âm lịch và dương lịch có độ chính xác, nơi sinh, nơi an táng, tiểu sử, thông tin liên hệ, ảnh |
| F05 | Quản lý quan hệ: hôn phối (nhiều vợ/chồng, thứ tự, ly hôn, góa), quan hệ con (con đẻ, con nuôi, thứ tự sinh), con chỉ xác định được một bên cha hoặc mẹ |
| F06 | Xem cây gia phả từ một người gốc, giới hạn số đời lên và xuống |
| F07 | Tìm kiếm người theo họ tên (không phân biệt dấu), theo đời, theo tình trạng còn sống |
| F08 | Chế độ xem: phạm vi (toàn dòng họ, theo nhánh, tương đối theo người xem) và nhóm trường; một chế độ mặc định áp dụng cho toàn bộ MEMBER, có thể ghi đè cho từng người |
| F09 | Link chia sẻ: nhiều link, mỗi link dùng một chế độ xem; tạo, sửa, xóa, thu hồi; có hoặc không thời hạn; bất kỳ ai có link đều xem được; bị giới hạn bởi trần an toàn |
| F10 | Ẩn trường theo nhóm trường; đánh dấu hồ sơ "hạn chế" |
| F11 | Xuất danh sách người trong phạm vi ra tệp Excel, áp dụng quy tắc ẩn trường |
| F12 | Nhật ký truy cập và thay đổi (audit log) dành cho `OWNER` |
| F13 | Quy đổi ngày âm lịch và dương lịch theo lịch Việt Nam (múi giờ UTC+7) |
| F14 | Gói dịch vụ và hạn mức theo dòng họ |
| F15 | Thanh toán trực tuyến qua VNPay (môi trường sandbox) |
| F16 | Quản trị nền tảng: tài khoản, trạng thái dòng họ, gói, cấu hình |
| F17 | Gắn tài khoản với hồ sơ gia phả; người dùng tự quản lý thông tin liên hệ và cờ hạn chế của hồ sơ mình |
| F18 | Người kế nhiệm; chuyển giao quyền trưởng tộc chủ động và tiếp quản khi trưởng tộc không hoạt động |
| F19 | Xác minh email, quên mật khẩu, xác thực bổ sung bằng OTP qua email |

## 5. Chức năng mở rộng (sau MVP)

| Mã | Chức năng | Yêu cầu bổ sung |
|---|---|---|
| S01 | Nhập dữ liệu từ tệp Excel theo template cố định | Có bước xem trước và báo lỗi theo từng dòng; dữ liệu chỉ được ghi khi toàn bộ tệp hợp lệ |
| S02 | Xác định quan hệ họ hàng giữa hai người | Sử dụng bảng closure |
| S03 | Lịch giỗ theo ngày mất âm lịch | |
| S04 | Đơn khôi phục quyền trưởng tộc khi không có người kế nhiệm | EDITOR xác nhận, SUPPORT xét duyệt (GP-DOC-05 mục 5.4) |

## 6. Ngoài phạm vi

- Gộp hai cây gia phả; tự động phát hiện người trùng lặp.
- Xóa dòng họ qua giao diện. Thao tác này chỉ thực hiện bằng thao tác quản trị trên cơ sở dữ liệu.
- Đăng nhập một lần (SSO), xác thực hai lớp bằng ứng dụng TOTP.
- Hóa đơn điện tử, hoàn tiền tự động, quy đổi thời gian còn lại khi đổi gói, nhiều cổng thanh toán.
- Nhập/xuất GEDCOM, xuất PDF, ứng dụng di động, đa ngôn ngữ.
- Năm chỉ ghi theo can chi mà không xác định được năm cụ thể. Thông tin này được ghi vào phần tiểu sử.
- Quan hệ khiến một người trở thành tổ tiên của chính mình. Cơ sở dữ liệu từ chối loại quan hệ này. Hôn nhân giữa những người có quan hệ họ hàng vẫn được hỗ trợ.

## 7. User story và tiêu chí chấp nhận

**US-01 (F01, F19)** — Là người dùng, tôi muốn đăng ký và đăng nhập để sử dụng hệ thống.
- AC-01.1: Đăng ký bằng email đã tồn tại bị từ chối (409).
- AC-01.2: Đăng nhập sai email và đăng nhập sai mật khẩu trả về cùng một thông báo lỗi.
- AC-01.3: Sau 5 lần đăng nhập sai trong 15 phút từ cùng một cặp (IP, email), các yêu cầu tiếp theo bị từ chối (429).
- AC-01.4: Access token hết hạn sau 15 phút. Refresh token được xoay vòng sau mỗi lần sử dụng; sử dụng lại refresh token cũ bị từ chối.
- AC-01.5: Tài khoản chưa xác minh email không tạo được dòng họ và không chấp nhận được lời mời (403 `EMAIL_NOT_VERIFIED`).
- AC-01.6: Yêu cầu quên mật khẩu luôn nhận cùng một phản hồi, bất kể email có tồn tại. Token đặt lại có hiệu lực 30 phút, dùng một lần; đặt lại thành công thu hồi mọi phiên đăng nhập.

**US-02 (F02)** — Là người dùng, tôi muốn tạo một dòng họ để bắt đầu chép phả.
- AC-02.1: Người tạo trở thành `OWNER`; dòng họ bắt đầu ở gói FREE với một chế độ xem mặc định cho thành viên.
- AC-02.2: Mỗi dòng họ luôn có đúng một `OWNER`; không xóa được OWNER và không gán vai trò OWNER trực tiếp (409 `OWNER_TRANSFER_REQUIRED`).

**US-03 (F03)** — Là `OWNER`, tôi muốn mời người khác tham gia với vai trò và quyền xem xác định.
- AC-03.1: Lời mời được gửi qua email và chỉ được chấp nhận bởi tài khoản có đúng email được mời.
- AC-03.2: Lời mời có thời hạn tối đa 14 ngày, chỉ sử dụng được một lần và có thể thu hồi.
- AC-03.3: Chỉ `OWNER` mời được thành viên; `EDITOR` không mời được và không xem được danh sách thành viên, lời mời.
- AC-03.4: `OWNER` chỉ định và thay đổi được `EDITOR`; chỉ `OWNER` sửa vai trò, chế độ xem và hồ sơ gắn với thành viên.

**US-04 (F04, F05, F13)** — Là `EDITOR`, tôi muốn nhập thông tin người và quan hệ.
- AC-04.1: Ngày tháng nhận một trong các mức "Chưa rõ", chỉ năm, năm và tháng, hoặc đầy đủ ngày; có cờ "khoảng". Ngày âm lịch có cờ tháng nhuận.
- AC-04.1b: Khi ngày ở một loại lịch đã đầy đủ, nút "Tự tính" điền ngày ở loại lịch còn lại theo lịch Việt Nam. Nút bị vô hiệu khi ngày chưa đầy đủ.
- AC-04.1c: Ngày âm lịch và ngày dương lịch không khớp nhau theo quy tắc tại GP-DOC-02 mục 5.3 bị từ chối (422 `DATE_CALENDAR_MISMATCH`), kể cả khi gọi API trực tiếp.
- AC-04.2: Ngày không hợp lệ bị từ chối, bao gồm: ngày 30/02 dương lịch, ngày âm lịch 31, cờ tháng nhuận khi chỉ biết năm.
- AC-04.3: Người còn sống không có ngày mất.
- AC-04.4: Mỗi người có tối đa một gia đình đẻ và có thể có nhiều gia đình nuôi.
- AC-04.5: Quan hệ khiến một người trở thành tổ tiên của chính mình bị từ chối (409 `ANCESTRY_CYCLE`).
- AC-04.6: `EDITOR` có phạm vi giới hạn chỉ sửa được người trong phạm vi; người mới phải được gắn vào một người trong phạm vi ngay khi tạo.
- AC-04.7: Khi hai người dùng cùng sửa một hồ sơ, người lưu sau nhận lỗi 409 `VERSION_CONFLICT`; dữ liệu không bị ghi đè.

**US-05 (F06, F07)** — Là `MEMBER`, tôi muốn xem cây gia phả và tìm kiếm người.
- AC-05.1: Cây chỉ chứa người trong phạm vi; quan hệ chỉ hiển thị khi cả hai đầu đều nằm trong phạm vi.
- AC-05.2: Từ khóa "nguyen van duc" trả về kết quả "Nguyễn Văn Đức".
- AC-05.3: Yêu cầu truy cập người ngoài phạm vi hoặc thuộc dòng họ khác nhận phản hồi 404, giống hệt phản hồi cho người không tồn tại.

**US-06 (F08)** — Là `OWNER`, tôi muốn quy định phạm vi và thông tin mà thành viên được xem.
- AC-06.1: Chế độ xem gồm phạm vi (toàn dòng họ; theo nhánh với người gốc, số đời xuống, số đời lên; tương đối theo hồ sơ của người xem) và danh sách nhóm trường, có tùy chọn kèm vợ/chồng.
- AC-06.2: Sửa chế độ xem mặc định áp dụng ngay cho mọi MEMBER không có chế độ xem riêng.
- AC-06.3: Thành viên chưa gắn hồ sơ không có phạm vi khi chế độ xem là tương đối.
- AC-06.4: Không xóa được chế độ xem đang được thành viên, link hoặc cấu hình mặc định sử dụng (409 `POLICY_IN_USE`).

**US-07 (F09)** — Là `OWNER`, tôi muốn chia sẻ gia phả cho bất kỳ ai qua link.
- AC-07.1: Mỗi link dùng một chế độ xem phạm vi toàn dòng họ hoặc theo nhánh; link mở được bởi người đã hoặc chưa đăng nhập.
- AC-07.2: Link không bao giờ lộ thông tin liên hệ, giấy tờ, ngày sinh đầy đủ của người còn sống và quan hệ con nuôi, bất kể cấu hình (409 `LINK_POLICY_CEILING`).
- AC-07.3: Link có thể không thời hạn. Sửa, thu hồi và xóa có hiệu lực tức thời, kể cả với phiên khách đang mở.
- AC-07.4: Token của link không xuất hiện trong log máy chủ (token đặt sau ký tự `#` của URL).

**US-08 (F10, F17)** — Là thành viên còn sống, tôi muốn thông tin cá nhân của mình được bảo vệ và do tôi kiểm soát.
- AC-08.1: Không có nhóm trường `LIVING_BIRTH_DATE` thì chỉ xem được năm sinh của người còn sống; không có nhóm `CONTACT` thì không xem được số điện thoại, email, địa chỉ.
- AC-08.2: Hồ sơ được đánh dấu "hạn chế" chỉ hiển thị nhóm `BASIC` với MEMBER và khách.
- AC-08.3: Trường bị ẩn không có mặt trong JSON phản hồi; tên trường được liệt kê trong `redactedFields`.
- AC-08.4: Người dùng đã gắn hồ sơ tự sửa được thông tin liên hệ và cờ "hạn chế" của hồ sơ mình.

**US-09 (F11)** — Là `OWNER`, tôi muốn xuất danh sách người ra tệp Excel.
- AC-09.1: Chỉ `OWNER` xuất được dữ liệu; tệp áp dụng cùng quy tắc ẩn trường với API.
- AC-09.2: Ô có nội dung bắt đầu bằng `=`, `+`, `-`, `@` được vô hiệu hóa công thức.
- AC-09.3: Mỗi lần xuất tạo một bản ghi audit.
- AC-09.4: Gói không có tính năng xuất Excel nhận phản hồi 402 `FEATURE_NOT_IN_PLAN`.

**US-10 (F12)** — Là `OWNER`, tôi muốn biết ai đã xem hoặc sửa dữ liệu nhạy cảm.
- AC-10.1: Audit được ghi cho các hành động liệt kê tại GP-DOC-03 mục 11.
- AC-10.2: Tầng ứng dụng không sửa, không xóa được audit log và không giả mạo được người thực hiện.
- AC-10.3: Audit được lưu theo thời hạn của gói và được xóa tự động khi quá hạn.

**US-11 (F14, F15)** — Là `OWNER`, tôi muốn mua hoặc gia hạn gói dịch vụ.
- AC-11.1: Số tiền do máy chủ tính từ bảng giá; client không gửi số tiền.
- AC-11.2: Chỉ IPN có chữ ký hợp lệ và số tiền khớp mới kích hoạt gói; trang trả về không kích hoạt gói.
- AC-11.3: IPN lặp lại cho cùng giao dịch không cộng thời gian lần thứ hai.
- AC-11.4: Gói hết hạn không xóa dữ liệu; dòng họ trở về hạn mức FREE và chỉ bị chặn tạo mới tài nguyên vượt hạn mức.

**US-12 (F14)** — Là `OWNER`, tôi muốn biết hạn mức và mức sử dụng của dòng họ.
- AC-12.1: Vượt hạn mức nhận phản hồi 402 `QUOTA_EXCEEDED` kèm tên tài nguyên và giới hạn.
- AC-12.2: Hai yêu cầu đồng thời không làm vượt hạn mức.

**US-13 (F17)** — Là thành viên, tôi muốn tài khoản của tôi được gắn với hồ sơ của tôi trong gia phả.
- AC-13.1: Lời mời có hồ sơ gắn sẵn tự động gắn tài khoản khi được chấp nhận.
- AC-13.2: Thành viên gửi yêu cầu nhận một hồ sơ trong phạm vi xem; chỉ `OWNER` duyệt.
- AC-13.3: Một hồ sơ gắn với tối đa một tài khoản, một tài khoản gắn với tối đa một hồ sơ trong mỗi dòng họ.

**US-14 (F18)** — Là `OWNER`, tôi muốn chuyển giao quyền trưởng tộc và bảo đảm dòng họ không mất người quản trị.
- AC-14.1: Chuyển giao chủ động yêu cầu xác thực bổ sung (mật khẩu và OTP qua email) ở cả bên chuyển và bên nhận; người nhận chấp nhận trong 7 ngày.
- AC-14.2: Người kế nhiệm yêu cầu tiếp quản được khi OWNER không hoạt động từ 180 ngày hoặc bị khóa; quyền được chuyển sau 30 ngày chờ có thông báo tới OWNER.
- AC-14.3: OWNER hoạt động trở lại hoặc từ chối trong thời gian chờ thì yêu cầu tiếp quản bị hủy.
- AC-14.4: Mỗi dòng họ có tối đa một yêu cầu chuyển giao đang xử lý; mọi bước được ghi audit.

**US-15 (F16)** — Là quản trị viên nền tảng, tôi muốn quản lý nền tảng mà không truy cập dữ liệu gia phả.
- AC-15.1: `SYSTEM_ADMIN` và `SUPPORT` không đọc được dữ liệu gia phả của bất kỳ dòng họ nào.
- AC-15.2: Dòng họ bị tạm ngưng không truy cập được dữ liệu, kể cả `OWNER` và link chia sẻ; `OWNER` vẫn thấy trạng thái.
- AC-15.3: `SUPPORT` không đổi được trạng thái dòng họ, gói hay cấu hình.
- AC-15.4: Vai trò hệ thống không cấp được qua API; mọi thao tác quản trị được ghi nhật ký quản trị.

## 8. Yêu cầu phi chức năng

| Nhóm | Yêu cầu | Phương pháp kiểm chứng |
|---|---|---|
| Bảo mật | Đáp ứng OWASP Top 10 (2021), có bằng chứng kiểm thử cho từng mục | Báo cáo kiểm thử bảo mật |
| Bảo mật | Cách ly dòng họ được bảo đảm đồng thời ở tầng ứng dụng và tầng cơ sở dữ liệu (RLS) | Ma trận test chéo dòng họ chạy trong CI |
| Bảo mật | Cache không làm chậm hiệu lực của thu hồi quyền; quyết định phân quyền luôn đọc từ cơ sở dữ liệu | Test thu hồi link và khóa tài khoản khi cache đang có dữ liệu |
| Thanh toán | IPN idempotent; chữ ký và số tiền được kiểm tra trước khi kích hoạt gói | Test tích hợp với VNPay sandbox |
| Hiệu năng | Với dòng họ 15 đời / 5.000 người: `GET /tree` p95 < 500 ms; tìm kiếm p95 < 200 ms trên máy chủ staging 2 vCPU | Kiểm thử tải bằng k6 |
| Dữ liệu | Sao lưu hằng ngày; diễn tập khôi phục đạt RPO ≤ 24 giờ, RTO ≤ 1 giờ | Biên bản diễn tập |
| Email | Email nghiệp vụ được gửi qua hàng đợi, thử lại khi lỗi; không mất email khi máy chủ email gián đoạn | Test với Mailpit dừng và khởi động lại |
| Triển khai | Dựng toàn bộ môi trường bằng một lệnh; tự động triển khai staging khi merge vào `main` | Pipeline CI/CD |
| Giao diện | Tiếng Việt; hỗ trợ Chrome và Firefox phiên bản hiện hành; sử dụng được ở độ rộng màn hình 360 px | Kiểm thử E2E bằng Playwright |

## Lịch sử thay đổi

| Phiên bản | Ngày | Nội dung |
|---|---|---|
| 1.0 | 14/10/2026 | Ban hành lần đầu |
| 1.2 | 14/10/2026 | Giới hạn EDITOR ở việc ghi dữ liệu gia phả: bỏ quyền mời thành viên, duyệt nhận hồ sơ, xuất Excel |
| 1.1 | 14/10/2026 | Bổ sung vai trò hệ thống, gói dịch vụ và thanh toán, chế độ xem, link chia sẻ có cấu hình, gắn tài khoản với hồ sơ, chuyển giao trưởng tộc, xác minh email và quên mật khẩu |
