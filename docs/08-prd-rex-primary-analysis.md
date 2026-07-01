# Phân tích PRD "REX Primary" và đối chiếu với Retail Access Vault (POC)

> Nguồn: `PRD REX Primary.pdf` (8 trang) + repo example [`d3labs-io/pruv-docs`](https://github.com/d3labs-io/pruv-docs)
> (interface Pruv thật). Đối chiếu với bản POC hiện tại trong repo này (`src/`, `docs/05-spec.md`,
> `docs/SUMMARY.md`). Mục tiêu: xem PRD muốn làm gì, phần implementation của ta đã phủ tới đâu, và
> **các example Pruv khớp/lấp vào PRD ra sao** (§6).

---

## 1. PRD muốn làm gì (tóm tắt)

REX Primary là sản phẩm đưa **token RWA (quỹ Evergreen Private Credit của Pruv Finance)** ra
**thị trường bán lẻ (retail)**. Ý tưởng cốt lõi: gom vốn lẻ của nhiều nhà đầu tư nhỏ lại thành
một "vé" đủ lớn để mua được tài sản quỹ tư nhân (vốn có minimum ticket cao), rồi phân phối lại
cho họ — và cho phép họ thoát vốn (redeem) về stablecoin.

Ba mục tiêu (Objectives) PRD nêu rõ:

1. **Tự phát hành, không phụ thuộc web3 foundation** — chủ động marketing token của chính mình.
2. **Giải bài toán "early redemption" mà không phải bỏ thanh khoản của chính công ty** — cho
   retail thoát vốn mà không rút cạn vốn nhà.
3. **Đạt được minimum ticket size** để đủ điều kiện mua tài sản quỹ tư nhân.

**Product Vision:** phân phối được quỹ private credit với **vốn tự có tối thiểu**.

### Cấu trúc chính (3 khối chức năng)

| Khối | Vai trò |
|---|---|
| **Group Subscription** | Gom stablecoin của retail → tới epoch thì subscribe tài sản ở Pruv → phân phối wRWA lại cho họ |
| **Group Redemption** | Gom wRWA của người muốn thoát → tới epoch thì redeem ở Pruv → trả stablecoin lại |
| **Matching System** | Nett (bù trừ) sub ↔ redeem trong cùng epoch; chỉ phần **chênh lệch (delta)** mới thực sự chạm tới Pruv |

### 5 trạng thái (state machine)

```
Initialized → Launchpad-start → ┬→ Epoch-based → Wind-down → (END)
                                └→ Launchpad-fail
```

- **Initialized** — vault đã deploy nhưng launchpad chưa mở; mọi giao dịch bị khoá.
- **Launchpad-start** — retail khoá USDC để đạt minimum ticket; nhận **receipt token** (chưa
  phải vault token), dùng receipt để claim wRWA sau.
- **Launchpad-fail** — không đạt minimum trong thời hạn → mọi người redeem lại stablecoin đã khoá.
- **Epoch-based** — pha vận hành bình thường: sub/redeem theo epoch, có matching.
- **Wind-down** — đóng pool: khoá sub mới, refund sub đang chờ, đổi tài sản lỏng → stablecoin trả
  redeem queue, rồi redeem nốt tài sản kém lỏng theo window, cuối cùng user đổi vault token lấy
  stablecoin trong thời hạn.

### Thông tin admin phải cung cấp để launch
Asset address (Pruv) · stablecoin · thời điểm mở launchpad · độ dài launchpad · minimum amount ·
độ dài epoch.

### Chi tiết Matching (ví dụ trong PRD)
- **Sub > Redeem:** 10.000 USDC sub, token redeem trị giá 4.000 USDC → match 4.000 P2P, **6.000
  còn lại** đem mua tài sản Pruv.
- **Redeem > Sub:** 4.000 sub, 10.000 redeem → match 4.000, **6.000 còn lại** trả bằng cách swap
  tài sản lỏng trong custody ra USDC; nếu hết lỏng thì **bán tài sản kém lỏng (Pruv)**.

### Fees (PRD yêu cầu 2 loại)
1. Phí **huỷ subscription** (subscribe cancellation).
2. Phí **redemption**.

---

## 2. Đối chiếu PRD ↔ POC của chúng ta

Bản POC (`Vault.sol` + `Custody.sol` + mocks) chính là hiện thực **Alternative 1** của PRD này.
Mức độ phủ:

| Hạng mục PRD | Trong POC | Trạng thái |
|---|---|---|
| 5 states (Initialized → Launchpad → Epoch → Wind-down) | State machine y hệt, thêm state cuối `Closed` | ✅ Khớp |
| Group Subscription (ERC-7540, có queue, không mint ngay) | `requestDeposit`/`requestRedeem` → queue → fulfill tại epoch | ✅ Khớp |
| Huỷ request trước window (ERC-7887) | `cancelRequest(id)` trước khi epoch xử lý | ✅ Khớp |
| Matching nett sub ↔ redeem, chỉ xử lý delta | `processEpoch()`: **matching chạy trước**, rồi mới xử lý net | ✅ Khớp |
| Sub > Redeem: phần dư mua Pruv | Nhánh `netSub > 0` → `computeRebalanceBuy` → `subscribeToPruv` | ✅ Khớp (đúng ví dụ 10k/4k = **kịch bản S4**) |
| Redeem > Sub: phần dư lấy từ tài sản lỏng, hết lỏng thì bán Pruv | **Redemption 3 lớp**: matching → liquid buffer → Pruv | ✅ Khớp (đúng ví dụ = **kịch bản S5/S6**) |
| NAV cập nhật theo epoch | NAV thủ công qua `MockPruv.setPrice()` trước mỗi `processEpoch` (seam `INavSource`) | ✅ Khớp về cơ chế |
| Launchpad: gom USDC, đạt/không đạt minimum | Launchpad + `LaunchpadFail` refund 100% | ✅ Khớp (S1/S2) |
| Wind-down: refund sub chờ, thanh lý tài sản trả redeem | `triggerWindDown` → settle sạch nghĩa vụ đang treo | ✅ Khớp (S8) |
| Pruv Finance (tài sản nền) | `MockPruv` on-chain (admin `setPrice`) | 🟡 Mock (đúng chủ đích POC) |

**Điểm đáng chú ý:** hai ví dụ số học trong mục Matching của PRD (10k/4k) **chính là** hai kịch
bản chấp nhận (acceptance) **S4 và S5** của POC — được assert đúng từng con số. Nói cách khác,
"hợp đồng số học" của PRD đã được chứng minh chạy đúng bằng test tự động.

---

## 3. Chỗ POC làm rõ / diễn giải khác PRD (clarifications)

PRD có vài chỗ mơ hồ; POC đã chốt một cách diễn giải nhất quán:

1. **User cầm "vault share", không phải cầm wRWA trực tiếp.**
   PRD lúc thì nói "phân phối wRWA cho retail", lúc lại nói matching "burn vault token" — không
   nhất quán. POC chốt rõ: **retail cầm cổ phần vault (rACCESS, ERC-20 18-dec)** — một *claim*
   trên NAV của pool; còn **wRWA + tài sản lỏng nằm trong `Custody`**. Đây là cách duy nhất để
   pooling + NAV + buffer 20% hoạt động mạch lạc. Redeem = nộp rACCESS-IN, nhận USDC-OUT.

2. **"Receipt token" = mapping, không phải token chuyển nhượng được.**
   PRD gọi là "receipt token". POC dùng `mapping(address => uint256)` (không transferable) cho
   biên nhận launchpad/claim — quyết định có chủ đích (SUMMARY §5.3) để tránh phát sinh một token
   thứ cấp không cần thiết trong phạm vi POC.

3. **Buffer thanh khoản 80/20 được hình thức hoá.**
   PRD chỉ nói mơ hồ "swap tài sản lỏng trong custody". POC định lượng thành **sleeve lỏng ~20%**
   + cơ chế **rebalance-toward-target** (net sub mua bù sleeve đang thiếu để kéo về 80/20).

---

## 4. Chỗ PRD có mà POC **cố ý chưa làm** (out-of-scope, đã ghi rõ)

| Hạng mục PRD | Vì sao POC chưa làm |
|---|---|
| **Fees** (phí huỷ sub + phí redeem) | POC để **0% phí** toàn bộ (scope guardrail). Đã có nghiên cứu riêng ở `docs/06-fees/` để bật khi graduate |
| **Bridge / cross-chain** ("bridge sang Pruv Network", "bridge wRWA về chain gốc") | POC chạy **1 chain Anvil duy nhất**, Pruv là mock on-chain — không có cầu nối. Interface thật = Hyperlane warp route (xem §6.5) |
| **Pruv API thật** (subscription/redemption window thật) | POC giả định Pruv luôn fulfill đầy đủ; rollover partial-fill là edge case đã defer (ghi chú S6). Interface thật = ERC-4626 `deposit`/`redeem` + whitelist KYC (xem §6.1, §6.4) |
| **UI / product page** | POC chỉ chứng minh cơ chế on-chain, không có frontend |
| **NAV oracle / feed tự động** | NAV nhập tay qua `setPrice` (decision 5); seam `INavSource` để sau này cắm oracle không đổi Vault |

Tất cả đều nằm trong danh sách "Out (deferred)" của `CLAUDE.md` — không phải thiếu sót, mà là
ranh giới phạm vi đã thống nhất.

---

## 5. Chỗ POC **vượt trên PRD** (extensions)

1. **OTC early-exit (variant 1a)** — `src/otc/` (`OTCMarket` + `OTCFactory` + `BidVault`).
   Đây là câu trả lời **trực tiếp cho Objective #2 của PRD**: "giải early redemption mà không
   tiêu thanh khoản của công ty". Trong vault gốc, muốn thoát thì phải chờ tới epoch kế. OTC cho
   phép **thoát ngay lập tức** giữa hai epoch bằng cách bán cổ phần cho một **retail buyer khác**
   ở mức chiết khấu nhỏ (ladder 1% / 2.5% / 5% / 10%) — **thanh khoản đến từ buyer P2P, không phải
   từ vault/công ty**. Phần không bán được rơi về queue redeem ở full NAV. Vault lõi **không đổi
   một dòng nào** (OTC chỉ chuyển quyền sở hữu cổ phần sẵn có, không mint/burn).

2. **8 kịch bản acceptance** (S1–S8) + **6 kịch bản OTC** + invariant fuzz — biến các câu chữ
   PRD thành số liệu assert được, chạy `forge test` < 30s.

3. **Tách Custody khỏi Vault** (ADR 001): "Vault giữ state, Custody giữ token" — ranh giới an
   toàn PRD không nói tới.

---

## 6. Pruv Finance **thật** — khớp các example vào PRD (lấp chỗ PRD để trống)

PRD chỉ nói trừu tượng "subscribe/redeem the asset **in Pruv Finance**" mà không đưa interface.
Repo example [`d3labs-io/pruv-docs`](https://github.com/d3labs-io/pruv-docs) cung cấp đúng phần
kỹ thuật còn thiếu đó. Đọc các example (`node-js-deposit-redeem`, `node-js-set-value`, `bridge`),
Pruv lộ ra như sau:

### 6.1. Pruv RWAToken **là một vault ERC-4626 chuẩn (đồng bộ)**

Subscribe/redeem ở Pruv **không phải async** ở tầng contract — nó là ERC-4626 UUPS-upgradeable
+ AccessControl. Các hàm cốt lõi:

| Hành động PRD | Hàm Pruv thật (RWAToken) | Ghi chú |
|---|---|---|
| "subscribe to asset in Pruv" | `deposit(assets, receiver) → shares` | nộp stablecoin, nhận RWA share **ngay** |
| "redeem in Pruv" | `redeem(shares, receiver, owner) → assets` | đốt share, nhận stablecoin **ngay** |
| xem trước | `previewDeposit` / `previewRedeem` / `convertToAssets` / `convertToShares` | |
| hạn mức | `maxDeposit` / `maxRedeem` / `maxSupply` / `cappedSupply` | có trần cung |
| liên kết | `asset()` (stablecoin), `rwaConversion()`, `rwaFee()`, `rwaConfig()` | |

**Hệ quả cho PRD/POC:** "subscription window" mà PRD nói là **ràng buộc vận hành/nghiệp vụ**
(quỹ mở cửa mua theo đợt), **không phải** cơ chế trong contract Pruv. Contract Pruv trả kết quả
đồng bộ. → cách POC gọi `Custody.subscribeToPruv` vào một mock **đồng bộ** là trung thành với
interface thật; phần "chờ window" nằm ở tầng epoch của REX, không phải ở Pruv.

### 6.2. NAV = `RWAConversion` — **trùng khít với `MockPruv` của ta**

Pruv tách riêng một contract giá:

| Pruv thật | POC của ta | Khớp? |
|---|---|---|
| `RWAConversion.value() → uint256` (18-dec) | `INavSource.pricePerWRWA()` / `MockPruv.pricePerWRWA()` | ✅ cùng ý nghĩa |
| `RWAConversion.setValue(newValue)` (18-dec, vd `1.5e18`) | `MockPruv.setPrice(p)` (1e18 = parity) | ✅ cùng scale, cùng cách admin submit |

Đây là **xác nhận quan trọng**: quy ước NAV 18-dec, parity `1e18`, admin nhập tay của POC
(CLAUDE.md) **đúng như Pruv thật làm**. Seam `INavSource` chính là chỗ sau này trỏ thẳng vào
`RWAConversion.value()` — thay `MockPruv`, **không đổi `Vault`**.

### 6.3. Fees = `RWAFee` — chính là 2 loại phí PRD muốn

PRD yêu cầu phí (mục Fees). Pruv đã có sẵn contract phí:

- `feeOnRaw(amount, timing=0)` → **phí entry** (cộng thêm *trên* số tiền deposit).
- `feeOnTotal(amount, timing=1)` → **phí exit** (trừ *khỏi* số nhận khi redeem).
- `setFee(kind, bps, timing)` / `setRecipient(addr, kind)` — admin cấu hình.

→ Khi POC bật fee model (đang 0%), đây là interface tham chiếu; nghiên cứu ở `docs/06-fees/` nên
map thẳng vào `feeOnRaw` (entry) và `feeOnTotal` (exit) của Pruv.

### 6.4. **Whitelist (KYC) — mảnh PRD không nói, nhưng giải thích *tại sao* cần aggregator**

Mọi `deposit`/`redeem` ở Pruv đều qua **Whitelist ERC-1155**: `whitelist.balanceOf(user, 1)` phải
> 0 (token ID 1 = quyền KYC). Nghĩa là **Pruv là permissioned**.

Đây là insight kiến trúc mạnh nhất: retail **không thể** ai cũng đi KYC ở Pruv. Nên mô hình đúng
là — **REX Vault/`Custody` là địa chỉ whitelisted DUY NHẤT** nắm vị thế ở Pruv; retail nhận
exposure **permissionless** thông qua **vault share** của REX. Điều này giải thích chính xác vì
sao PRD cần pooling/aggregator: không chỉ để **gom đủ minimum ticket** (Objective #3), mà còn để
**bao bọc KYC** — biến một sản phẩm permissioned (Pruv) thành permissionless cho retail (Objective
#1). POC hiện chưa mô phỏng whitelist; khi tích hợp thật, `Custody` phải là ví được cấp token ID 1.

### 6.5. Bridge = **Hyperlane warp routes** (PRUV ↔ Kaia)

PRD nói "bridge to Pruv Network" / "bridge wRWA back" nhưng không nói bằng gì. Example dùng
**Hyperlane warp route** giữa PRUV Testnet (domain `7336`) và Kaia Kairos (domain `1001`):
`HypERC20CollateralWithFee` phía PRUV ↔ `HypERC20` synthetic phía Kaia, có phí bridge + relay
tracking. Đáng chú ý: RWA token bridged ("KAI") và USDC ở đây đều **6-dec** — phần nào xác nhận
lựa chọn để mock wRWA/liquid 6-dec của POC là hợp lý.

### 6.6. Bảng ánh xạ 3 lớp: PRD → Pruv thật → POC

| Bước PRD (trừu tượng) | Pruv thật (pruv-docs) | POC hiện tại |
|---|---|---|
| Subscribe asset in Pruv | `RWAToken.deposit(assets, receiver)` | `Custody.subscribeToPruv` → `MockPruv` |
| Redeem in Pruv | `RWAToken.redeem(shares, receiver, owner)` | `Custody` redeem lớp 3 → `MockPruv` |
| "updated value on epoch" (NAV) | `RWAConversion.value()` / `setValue()` | `INavSource.pricePerWRWA()` / `setPrice()` |
| Fees (cancel/redeem) | `RWAFee.feeOnRaw` (entry) / `feeOnTotal` (exit) | 0% (defer, `docs/06-fees/`) |
| (ẩn) KYC để mua được | `Whitelist.balanceOf(user, 1)` ERC-1155 | chưa mô phỏng — `Custody` sẽ là ví whitelisted |
| Bridge USDC↔RWA giữa chain | Hyperlane warp route (domain 7336 ↔ 1001) | 1 chain Anvil, không bridge |

---

## 7. Đối chiếu theo từng Objective của PRD

| Objective PRD | POC phục vụ thế nào |
|---|---|
| **#1** Tự phát hành, không phụ thuộc foundation | Vault + shares ERC-20 tự quản, admin `Ownable` đơn, không dựa hạ tầng bên thứ ba |
| **#2** Giải early redemption **không tiêu thanh khoản nhà** | **Hai tầng**: (a) redemption 3 lớp trong vault (matching → buffer → Pruv) cho redeem theo epoch; (b) **OTC layer** cho thoát *tức thì* bằng thanh khoản P2P của buyer |
| **#3** Đạt minimum ticket size | Launchpad gom USDC tới ngưỡng `minimum`; không đạt → `LaunchpadFail` refund 100% |

---

## 8. Kết luận & khuyến nghị

- Bản POC **đã chứng minh trọn vẹn phần "cơ chế lõi"** của REX Primary PRD: state machine 5
  trạng thái, queue bất đồng bộ (7540/7887), matching nett-delta, redemption 3 lớp, wind-down —
  và hai ví dụ số học Matching của PRD đúng nguyên văn (S4/S5).
- POC còn **đi xa hơn PRD một bước** ở đúng điểm đau nhất (Objective #2): OTC early-exit — thứ
  PRD nêu là mục tiêu nhưng không mô tả cơ chế.
- **Đối chiếu với Pruv thật (§6) cho thấy hướng thiết kế POC là đúng:** interface Pruv là
  ERC-4626 đồng bộ, NAV qua `RWAConversion` 18-dec — **trùng khít** cách `MockPruv`/`INavSource`
  của ta mô hình hoá. Việc thay mock bằng Pruv thật là **drop-in qua seam, không đổi `Vault`**.
- **Lộ trình graduate lên sản phẩm** (thứ tự ưu tiên, đã có interface cụ thể từ §6):
  1. **Whitelist/KYC** — cấp token ID 1 cho `Custody` để nó là địa chỉ được phép giao dịch Pruv
     (điều kiện *bắt buộc* mới; PRD không nêu, phát hiện từ pruv-docs §6.4).
  2. **Thay `MockPruv`** bằng adapter gọi `RWAToken.deposit/redeem` + `RWAConversion.value()`
     cắm vào `INavSource` (§6.1–6.2).
  3. **Bridge Hyperlane** nối USDC/RWA giữa chain dApp và PRUV (§6.5).
  4. **Bật fee model** map vào `RWAFee.feeOnRaw`/`feeOnTotal` (§6.3, nghiên cứu `docs/06-fees/`).
  5. **UI/product page**; staleness guard cho giá + audit hardening.

> Tóm một câu: PRD REX Primary mô tả *cái gì cần xây*; repo này đã chứng minh *cơ chế đó chạy
> đúng* trên một chain mô phỏng, cộng thêm lời giải P2P cho bài toán early-exit — phần còn lại để
> lên production đều là các mảnh hạ tầng đã được khoanh vùng rõ, không phải rủi ro cơ chế.

