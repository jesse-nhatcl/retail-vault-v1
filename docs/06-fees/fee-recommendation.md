# Fee Model — Đề xuất (bản tóm tắt cho manager)

**Ngày:** 2026-06-05 · **Đọc trong:** ~5 phút · **Bản phân tích đầy đủ:** `fee-research.md`

---

## Vấn đề

PRD không định nghĩa fee — tức là chưa có câu trả lời cho **"sản phẩm này kiếm tiền bằng cách nào"**. Chúng tôi đã khảo sát 13 nền tảng tokenized fund (BlackRock BUIDL, Ondo, Securitize × Hamilton Lane, Maple, Centrifuge…) và chuẩn quỹ private credit truyền thống, để đề xuất fee structure cho sản phẩm này. Bản này nêu rõ đề xuất; bản đầy đủ có toàn bộ số liệu và nguồn.

## Thị trường đang thu thế nào

| Nhóm sản phẩm | Phí quản lý/năm | Phí khác |
|---|---|---|
| Quỹ trái phiếu chính phủ tokenized (BUIDL, Franklin, Ondo…) | 0.15–0.5% | Gần như không |
| **Private credit tokenized — cùng loại với chúng ta** (Hamilton Lane qua Securitize) | **1.75%** | 0 phí vào/ra |
| Quỹ private credit truyền thống | 1.0–1.5% | + 10–12.5% phí hiệu suất, + phạt 2% nếu rút sớm <12 tháng |

Kết luận từ benchmark: tài sản càng kém thanh khoản, fee càng cao — và việc đưa lên blockchain **không làm giảm** mặt bằng fee của private credit (1.5–1.75% vẫn là chuẩn). Chúng ta có dư địa thu fee ở mức TradFi mà vẫn cạnh tranh.

## Đề xuất

**Hai giai đoạn — POC thu gọn để chứng minh cơ chế, production thu đủ theo chuẩn ngành:**

| Loại fee | POC (bây giờ) | Production | Căn cứ |
|---|---|---|---|
| **Phí quản lý** | **1.5%/năm** | 1.5%/năm | Chuẩn TradFi 1.0–1.5%; Hamilton Lane qua Securitize thu 1.75% |
| **Phí rút** | **0.5%** mỗi lần rút | Giảm còn 0.1–0.2% | Cao hơn mặt bằng lúc đầu để bảo vệ vault khi còn nhỏ |
| **Phạt rút sớm** | Chưa làm | **2%** nếu rút trong 90 ngày | Chuẩn ngành 2%; bảo vệ nhà đầu tư ở lại |
| **Phí hiệu suất** | Chưa làm | 10% phần lợi nhuận vượt đỉnh | Hamilton Lane thu 10%; chỉ bật khi định giá NAV đã có kiểm chứng độc lập (xem Rủi ro #2) |
| Phí nạp | **Không thu** | Không thu | Chuẩn thị trường là 0; thu sẽ cản gọi vốn |

**Lợi nhuận cho nhà đầu tư sau fee vẫn hấp dẫn:** underlying ~8.8%/năm − 1.5% phí quản lý ≈ **7.3% net**, so với gửi USDC trên DeFi ~4–5%. Minh hoạ doanh thu: AUM $10M → ~$150K/năm phí quản lý, chưa kể phí rút.

## Hai rủi ro cần biết (và cách chúng tôi xử lý)

**1. Lỗ hổng "né phí qua matching" — riêng của thiết kế này.**
Hệ thống tự khớp lệnh mua và bán trong cùng kỳ để tiết kiệm chi phí. Nếu thu phí sai chỗ, người nạp và người rút có thể bắt tay nhau vào–ra cùng kỳ và **né toàn bộ phí rút**. Chưa nền tảng nào công bố cách xử lý. Đề xuất của chúng tôi đã chặn sẵn: phí tính trên **từng lệnh, trước khi khớp** — khớp lệnh chỉ tiết kiệm chi phí vận hành cho vault, không bao giờ thành đường né phí.

**2. Phí hiệu suất + định giá thủ công = xung đột lợi ích.**
Giai đoạn đầu, giá NAV do admin tự cập nhật. Nếu thu phí hiệu suất ngay, admin có động cơ đẩy giá lên để hưởng phí — rủi ro cả về tiền lẫn uy tín. Vì vậy chúng tôi **chủ động hoãn phí hiệu suất** sang production, chỉ bật khi NAV có kiểm chứng độc lập. Đây là lý do duy nhất khoản fee này chưa có mặt từ đầu, không phải vì không làm được.

## Phương án đã loại và lý do

- **Mô hình "0 phí" kiểu spread ẩn** (giữ chênh lệch lợi nhuận, như Ondo USDY): nhìn đẹp về marketing nhưng toàn bộ doanh thu nằm ở chỗ không kiểm chứng được — nếu bị soi, chi phí uy tín lớn hơn nhiều con số 1.5% công khai.
- **Thu phí nạp / phí ở launchpad**: cản đúng giai đoạn cần gọi vốn nhất.
- **Copy nguyên bộ phí TradFi vào POC ngay**: thêm ~2 ngày dev cho các cơ chế đã được ngành chứng minh, không tạo thêm insight — POC chỉ cần chứng minh phần chưa ai giải (rủi ro #1).

## Cần quyết định

| # | Quyết định | Đề xuất của chúng tôi |
|---|---|---|
| 1 | Hướng fee 2 giai đoạn như trên | ✅ Approve để đưa vào spec POC (+0.5–1 ngày dev) |
| 2 | Mức phí quản lý 1.5% & phí rút 0.5% | Chốt tạm cho POC; số cuối chờ #3 |
| 3 | Biểu phí thật của underlying Hamilton Lane | Cần lấy qua kênh chính thức (tài liệu công khai bị giới hạn truy cập) — quyết định mức fee cuối và con số APY net được phép quảng bá |
