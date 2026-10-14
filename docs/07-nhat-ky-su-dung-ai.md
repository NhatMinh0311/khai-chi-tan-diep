# Nhật ký sử dụng công cụ AI

| Thuộc tính | Giá trị |
|---|---|
| Mã tài liệu | GP-DOC-07 |
| Phiên bản | 1.0 |
| Ngày ban hành | 15/10/2026 |

## 1. Mục đích

Tài liệu ghi nhận phạm vi sử dụng công cụ AI trong dự án Khai Chi Tán Diệp, phân định phần việc do thành viên thực hiện
và phần việc do công cụ thực hiện, phục vụ minh bạch học thuật và báo cáo học phần. Nhật ký được bổ sung sau mỗi giai đoạn.

## 2. Công cụ và quy ước

| Mục | Nội dung |
|---|---|
| Công cụ | Claude Code (Anthropic), mô hình Claude Opus 5 và Claude Opus 5.5 |
| Hình thức | Trao đổi trực tiếp với công cụ; công cụ đọc, ghi tệp và chạy lệnh trên máy của thành viên khi được cho phép |
| Ghi nhận trong lịch sử mã nguồn | Commit do công cụ tạo có dòng `Co-Authored-By: Claude …`; commit do thành viên tạo không có dòng này |

Phân loại phần việc trong nhật ký:

| Ký hiệu | Ý nghĩa |
|---|---|
| **TV-QĐ** | Thành viên quyết định hoặc đặt yêu cầu |
| **TV-TH** | Thành viên trực tiếp thực hiện |
| **AI-ĐX** | Công cụ đề xuất, thành viên chọn hoặc chấp thuận |
| **AI-TH** | Công cụ trực tiếp thực hiện (soạn tài liệu, viết mã, chạy kiểm thử) |

### 2.1. Quy trình ghi nhật ký

Mỗi giai đoạn là một mục cấp 2 (`## n. Giai đoạn k — <tên>`), gồm các phần cố định theo thứ tự:
thông tin chung, phần việc của thành viên, phần việc của công cụ, sản phẩm, quá trình làm việc, các lần điều chỉnh hướng,
ước lượng tỷ lệ đóng góp.

| Thời điểm | Ghi vào | Nội dung |
|---|---|---|
| Thành viên đặt bài toán hoặc yêu cầu mới | Bảng "Quá trình làm việc" của giai đoạn hiện tại: thêm một vòng | Bài toán, việc công cụ thực hiện, kết quả đánh giá của thành viên |
| Đề xuất hoặc sản phẩm của công cụ không đạt và được điều chỉnh | Bảng "Các lần điều chỉnh hướng" | Đề xuất ban đầu, điều chỉnh của thành viên |
| Công cụ phát hiện lỗi qua kiểm thử | Bảng "Phần việc của công cụ", hạng mục phát hiện lỗi | Lỗi và cách khắc phục |
| Kết thúc giai đoạn | Các phần còn lại của giai đoạn; mục "Lịch sử thay đổi" | Tổng hợp phần việc, sản phẩm, ước lượng tỷ lệ; tăng phiên bản tài liệu |
| Bắt đầu giai đoạn mới | Mục giai đoạn mới | Thời gian, người sử dụng công cụ, phạm vi |

Quy định:
- Mỗi vòng ghi kết quả đánh giá thực tế, kể cả khi kết quả không đạt.
- Nhật ký được cập nhật trong cùng pull request với sản phẩm của vòng đó.
- Mỗi thành viên sử dụng công cụ AI ghi phần của mình; cột "Người sử dụng công cụ" xác định người ghi.

Mẫu một vòng trong bảng "Quá trình làm việc":

```markdown
| <số vòng> | <bài toán hoặc yêu cầu thành viên đặt ra> | <việc công cụ đề xuất hoặc thực hiện> | <Đạt / Không đạt ở lần đầu: lý do; điều chỉnh> |
```

## 3. Giai đoạn 1 — Thiết kế và thiết lập ban đầu

| Mục | Nội dung |
|---|---|
| Thời gian | 13/10/2026 – 15/10/2026 |
| Người sử dụng công cụ | Trưởng nhóm (`NhatMinh0311`) |
| Phạm vi | Chọn đề tài, đặc tả yêu cầu, thiết kế dữ liệu và phân quyền, đặc tả API, lược đồ và kiểm thử cơ sở dữ liệu, môi trường phát triển, thiết lập kho mã và CI |

### 3.1. Phần việc của thành viên

| Hạng mục | Nội dung | Loại |
|---|---|---|
| Đề tài | Chọn đề tài gia phả dòng họ với hai bài toán multi-tenant và phân quyền dữ liệu nhạy cảm (cùng nhóm thảo luận); loại bỏ hướng tích hợp AI vào đề tài; giới hạn độ sâu phần bảo mật | TV-QĐ |
| Tổ chức nhóm | Phân vai: trưởng nhóm phụ trách QA, vận hành, triển khai, kiểm thử bảo mật; một thành viên backend, một thành viên frontend | TV-QĐ |
| Công nghệ | React, Spring Boot; Redis cho cache; JWT cho xác thực | TV-QĐ |
| Yêu cầu ngày tháng | Lưu cả âm lịch và dương lịch, có độ chính xác và giá trị "Chưa rõ"; nhập một loại lịch và tự tính loại còn lại; backend kiểm tra hai giá trị khớp nhau | TV-QĐ |
| Yêu cầu phân quyền | Khách chỉ xem họ tên; giới hạn phạm vi theo nhánh và số đời; điều chỉnh phạm vi và trường thông tin cho toàn bộ thành viên; EDITOR chỉ ghi dữ liệu gia phả, không chia sẻ, không cấp quyền xem | TV-QĐ |
| Yêu cầu bổ sung | Vai trò cấp hệ thống; gói dịch vụ và hạn mức cho dòng họ; gắn tài khoản với hồ sơ; link chia sẻ cấu hình trường và nhánh, tạo, sửa, xóa nhiều link; chỉ định EDITOR; chuyển giao trưởng tộc và xử lý khi trưởng tộc không hoạt động; phương thức xác thực | TV-QĐ |
| Lựa chọn giữa các phương án | Cổng thanh toán sandbox; đưa email vào phạm vi; một trưởng tộc cùng người kế nhiệm; trần an toàn cho link, cho phép link không thời hạn; đơn khôi phục để sau MVP; Excel: xuất trong MVP, nhập sau MVP | AI-ĐX |
| Duyệt và chỉnh sửa | Yêu cầu tài liệu dùng văn phong chính thức; yêu cầu ghi lại cấu hình ngoài kho mã phục vụ báo cáo; yêu cầu ghi nhật ký sử dụng AI | TV-QĐ |
| Kho mã | Đặt tên dự án; tạo kho mã GitHub; push; cấu hình ruleset bảo vệ nhánh; mời thành viên; tạo và merge pull request #1; xuất cấu hình ruleset | TV-TH |

### 3.2. Phần việc của công cụ

| Hạng mục | Nội dung | Loại |
|---|---|---|
| Đề xuất | Các hướng đề tài và vai trò; mức độ bảo mật phù hợp; phân chia công việc và tỷ trọng đóng góp dự kiến giữa các thành viên | AI-ĐX |
| Thiết kế kỹ thuật | Multi-tenant bằng lược đồ dùng chung và Row-Level Security; mô hình quan hệ theo hôn phối; bảng closure; mô hình ngày có độ chính xác và quy tắc kiểm tra khớp âm – dương lịch; chế độ xem và nhóm trường; luồng thanh toán và IPN; quy trình chuyển giao trưởng tộc; quy tắc cache; ánh xạ lỗi | AI-ĐX |
| Soạn thảo | Toàn bộ tài liệu GP-DOC-01 đến GP-DOC-07, ADR-0001 đến ADR-0010, `README.md` | AI-TH |
| Viết mã | Migration V1–V3, bộ kiểm thử cơ sở dữ liệu, đặc tả OpenAPI, Docker Compose, script khởi tạo, workflow CI, CODEOWNERS, mẫu pull request | AI-TH |
| Kiểm chứng | Áp dụng migration trên PostgreSQL 17; chạy bộ kiểm thử; lint đặc tả API; chạy mock server; sinh kiểu TypeScript từ đặc tả | AI-TH |
| Phát hiện lỗi thiết kế qua kiểm thử | `INSERT ... RETURNING` bị RLS từ chối với OWNER; tầng ứng dụng ghi được `last_active_at`, cho phép giả lập trưởng tộc không hoạt động; kỳ vọng sai trong một test | AI-TH |
| Hướng dẫn | Các bước tạo kho mã, cấu hình ruleset, mời thành viên, tạo và merge pull request | AI-ĐX |

### 3.3. Sản phẩm

| Sản phẩm | Quy mô | Soạn bởi | Yêu cầu và duyệt bởi |
|---|---|---|---|
| Tài liệu đặc tả và ADR (`docs/`) | Khoảng 1.600 dòng | Công cụ | Thành viên |
| Migration (`db/migration/`) | Khoảng 2.260 dòng SQL | Công cụ | Thành viên |
| Kiểm thử cơ sở dữ liệu (`db/tests/`) | Khoảng 1.080 dòng, 43 kiểm tra | Công cụ | Thành viên |
| Đặc tả API (`api/openapi.yaml`) | Khoảng 3.000 dòng, 87 operation | Công cụ | Thành viên |
| Hạ tầng và CI | Docker Compose, script, workflow, CODEOWNERS | Công cụ | Thành viên |
| Cấu hình GitHub (ruleset, collaborator) | 1 ruleset | Thành viên thực hiện theo hướng dẫn | Thành viên |

### 3.4. Quá trình làm việc

Giai đoạn diễn ra theo các vòng lặp: thành viên đặt bài toán và yêu cầu, công cụ đề xuất hoặc triển khai,
thành viên đánh giá kết quả, phát hiện điểm chưa đạt và đặt yêu cầu tiếp theo.

| Vòng | Thành viên đặt ra | Công cụ thực hiện | Kết quả đánh giá của thành viên |
|---|---|---|---|
| 1 | Vai trò vận hành, triển khai, kiểm thử bảo mật; cần đề tài phù hợp | Đề xuất các đề tài thiên về bảo mật | Bổ sung ràng buộc: giảng viên hướng dẫn chuyên ngành học máy |
| 2 | Ràng buộc về giảng viên hướng dẫn | Đề xuất đề tài RAG kết hợp red-teaming | Không đạt: ràng buộc nhằm giới hạn độ sâu bảo mật, không nhằm đưa AI vào đề tài |
| 3 | Đề tài web, bảo mật ở mức vừa phải | Đề xuất các đề tài đặt chỗ, thương mại điện tử | Nhóm chốt đề tài gia phả với hai bài toán multi-tenant và phân quyền dữ liệu nhạy cảm |
| 4 | Phương án phân công của nhóm | Đánh giá phân công, mô tả vai trò, ước lượng tỷ trọng công việc | Chấp thuận |
| 5 | Thiết kế hệ thống để backend và frontend làm song song; yêu cầu về khách, phạm vi, ngày âm dương | Tài liệu đặc tả, migration, đặc tả API, kiểm thử cơ sở dữ liệu | Bổ sung: nhập một loại lịch và tự tính loại còn lại; backend kiểm tra hai giá trị khớp nhau |
| 6 | Đánh giá văn phong tài liệu | Viết lại toàn bộ tài liệu | Không đạt ở lần đầu: tài liệu mang giọng trò chuyện thay vì văn bản chính thức của dự án |
| 7 | Thiếu vai trò hệ thống, gói dịch vụ, gắn tài khoản với hồ sơ, phạm vi cho toàn bộ thành viên, link cấu hình được, chuyển giao trưởng tộc, phương thức xác thực; dùng Redis, JWT | Mở rộng thiết kế, nêu các lựa chọn cần quyết định | Chọn phương án cho 4 câu hỏi |
| 8 | Duyệt quyền của EDITOR | Thu hẹp quyền EDITOR | Không đạt ở lần đầu: thiết kế cho phép EDITOR mời thành viên, tạo link và xuất dữ liệu, trái với vai trò chỉ ghi dữ liệu gia phả |
| 9 | Đơn khôi phục là gì; đưa vào MVP hay không | Giải thích, đánh dấu sau MVP | Để sau MVP |
| 10 | Thiết lập GitHub | Hướng dẫn, tệp cấu hình, workflow CI | Không đạt ở lần đầu: cấu hình ngoài kho mã chưa được ghi lại phục vụ báo cáo; bổ sung GP-DOC-06 và nhật ký này |
| 11 | Quy trình ghi nhật ký khi có bài toán mới | Bổ sung quy trình và mẫu ghi nhật ký (mục 2.1) | Đạt |
| 12 | Quy trình tích hợp chưa được phổ biến tới thành viên: lệnh và thao tác cụ thể | `CONTRIBUTING.md`; `.gitattributes` chuẩn hóa xuống dòng LF | Bổ sung: thiếu sót được thành viên phát hiện sau vòng 10 |

### 3.5. Các lần điều chỉnh hướng

| Đề xuất ban đầu của công cụ | Điều chỉnh của thành viên |
|---|---|
| Đưa thành phần AI (RAG) vào đề tài để phù hợp chuyên ngành giảng viên | Không đưa AI vào đề tài; chuyên ngành giảng viên chỉ là căn cứ để giới hạn độ sâu bảo mật |
| Tài liệu viết như lời trao đổi với thành viên, có ghi chú và câu hỏi lẫn trong nội dung | Tài liệu là văn bản chính thức của nhóm; câu hỏi và điểm chưa chắc được trao đổi trực tiếp |
| EDITOR được mời thành viên, tạo link trong phạm vi, xuất Excel, duyệt yêu cầu nhận hồ sơ | EDITOR chỉ ghi dữ liệu gia phả; mọi hành động chia sẻ và cấp quyền xem thuộc OWNER |
| Cấu hình GitHub chỉ được hướng dẫn trong trao đổi | Mọi cấu hình ngoài kho mã được ghi thành tài liệu trong kho mã |

### 3.6. Ước lượng tỷ lệ đóng góp

Ước lượng dựa trên nguồn gốc của từng quyết định và từng sản phẩm trong lịch sử trao đổi; mang tính định tính.
Thiếu sót về nghiệp vụ và các lần điều chỉnh hướng do thành viên phát hiện; lỗi kỹ thuật phát hiện qua kiểm thử do công cụ phát hiện.

| Hạng mục | Thành viên | Công cụ |
|---|---|---|
| Định hướng đề tài và yêu cầu nghiệp vụ | 60% | 40% |
| Quyết định kiến trúc và công nghệ | 20% | 80% |
| Soạn tài liệu, đặc tả API, mã SQL, kiểm thử | 5% | 95% |
| Kiểm chứng kỹ thuật | 10% | 90% |
| Phát hiện thiếu sót, điều chỉnh hướng (mục 3.4, 3.5) | 65% | 35% |
| Thiết lập GitHub | 70% | 30% |
| **Tổng thể giai đoạn** | **khoảng 20–25%** | **khoảng 75–80%** |

## Lịch sử thay đổi

| Phiên bản | Ngày | Nội dung |
|---|---|---|
| 1.0 | 15/10/2026 | Ghi nhận giai đoạn 1 |
