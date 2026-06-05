# Nghiên cứu Fee Model — Retail Access Vault

**Project:** Retail Access Vault (PRD Alternative 1 — Vault + Custody, mix liquid/illiquid)
**Ngày:** 2026-06-05
**Trạng thái:** Nghiên cứu — CHƯA quyết định phương án
**Tài liệu liên quan:** `research-raw.md` (data thô + citation đầy đủ), `options.md` (3 phương án), `05-spec.md` (spec POC)

---

## Mục lục

1. [Tóm tắt cho người đọc nhanh](#1-tóm-tắt-cho-người-đọc-nhanh)
2. [Bối cảnh — fee nằm đâu trong model](#2-bối-cảnh--fee-nằm-đâu-trong-model)
3. [Danh mục đầy đủ: mọi hành động có thể thu phí](#3-danh-mục-đầy-đủ-mọi-hành-động-có-thể-thu-phí)
4. [Benchmark — các nền tảng khác thu phí thế nào](#4-benchmark--các-nền-tảng-khác-thu-phí-thế-nào)
5. [Cơ chế kỹ thuật — thu phí on-chain thế nào](#5-cơ-chế-kỹ-thuật--thu-phí-on-chain-thế-nào)
6. [Rủi ro đặc thù của model này](#6-rủi-ro-đặc-thù-của-model-này)
7. [Ba phương án fee structure](#7-ba-phương-án-fee-structure)
8. [Tiêu chí quyết định & câu hỏi mở](#8-tiêu-chí-quyết-định--câu-hỏi-mở)

---

## 1. Tóm tắt cho người đọc nhanh

- PRD **không nói gì về fee** — spec hiện tại để 0% toàn bộ (Q6 deferred). Report này trả lời: *có thể thu phí ở đâu, các nền tảng khác làm thế nào, cơ chế kỹ thuật ra sao, và các phương án khả thi*.
- Model của chúng ta có **16 điểm có thể thu phí**, chia 3 nhóm: theo giao dịch (flow), theo thời gian/AUM (stock), và vận hành/ngầm (implicit). Xem §3.
- Thị trường chia 2 cực rõ rệt:
  - **Treasury wrappers** (BUIDL, USTB, BENJI…): mgmt fee 0.15–0.50%, gần như không fee gì khác.
  - **Private credit / evergreen** (đúng asset class của chúng ta): mgmt 1.0–1.75%, perf fee 10–12.5% trên hurdle, early-exit 2% nếu rút sớm <12 tháng.
- Về kỹ thuật, vault async (ERC-7540) **thu phí tại settlement** (`processEpoch`), không phải lúc user request — khớp tự nhiên với thiết kế của chúng ta.
- Hai phát hiện quan trọng nhất riêng cho model này:
  1. **Fee leakage qua matching**: nếu thu exit fee trên *net* flow, volume được match P2P sẽ né được fee → phải thu trên **gross từng request**. (§6.1)
  2. **Performance fee + NAV do admin set bằng tay là tổ hợp nguy hiểm**: admin có thể bơm giá để crystallize fee. Cần guardrails nếu đi hướng này. (§6.2)
- Ba phương án tổng hợp ở §7 — **chưa chốt**, kèm tiêu chí quyết định ở §8.

---

## 2. Bối cảnh — fee nằm đâu trong model

Nhắc lại kiến trúc đã chốt (ADR-001): 2 contract **Vault** (ERC-7540 queue, epoch, state machine) + **Custody** (giữ wRWA illiquid + liquid buffer + USDC). NAV do admin set thủ công qua `setPrice()`. Mỗi epoch, một hàm `processEpoch()` xử lý cả subscription lẫn redemption qua 3 lớp: matching → liquid buffer → illiquid Pruv.

Fee chạm vào model ở mọi điểm tiền đổi chủ hoặc giá trị được chốt:

```
  VÒNG ĐỜI VAULT vs ĐIỂM THU PHÍ TIỀM NĂNG
  ═════════════════════════════════════════════════════════════════

  Initialized ──▶ LaunchpadStart ──▶ EpochBased ──────────▶ WindDown
                       │                  │                     │
                  [F1] lock USDC     [F3] sub settle       [F16] thanh lý
                  [F2] claim shares  [F4] redeem settle
                                     [F5] early-exit
                                     [F6] cancel (7887)
                                     [F7] claim
                                     ┌─────────────────┐
                                     │ mỗi processEpoch│
                                     │ [F10] mgmt fee  │
                                     │ [F11] perf fee  │
                                     │ [F15] keeper gas│
                                     └─────────────────┘
                                     ngầm / liên tục:
                                     [F12] yield spread
                                     [F13] swap spread
                                     [F14] idle-cash yield
                                     [F17] Pruv pass-through
  ═════════════════════════════════════════════════════════════════
```

Mã số `[F*]` tham chiếu danh mục đầy đủ ở §3.

---

## 3. Danh mục đầy đủ: mọi hành động có thể thu phí

Đây là danh sách **vét cạn** — liệt kê cả những điểm *không nên* thu, để quyết định sau này là quyết định có chủ đích chứ không phải bỏ sót.

Cột **#** kèm verdict nhanh: **✅ thu (đề xuất POC)** · **🔶 thu ở production / tương lai** · **❌ không thu / loại**.

### Nhóm 1 — Fee theo giao dịch (flow-based): thu khi tiền/share di chuyển


| #   | Hành động                                                                                   | Ai trả                     | Thời điểm thu                        | Cơ chế                                                                  | Tiền lệ thị trường                                                                                    | Nhận xét                                                                                                                                                    |
| --- | ------------------------------------------------------------------------------------------- | -------------------------- | ------------------------------------ | ----------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| F1 ❌ | **Launchpad deposit** — user lock USDC giai đoạn gọi vốn                                    | User sub                   | Khi lock, hoặc khi launchpad success | Trừ % trên USDC lock                                                    | ADDX thu sub fee từ 0.5% cho HL SCOPE; Securitize thu 0%                                              | Thu lúc này **cản fundraise** — giai đoạn cần đạt minimum ticket. Hầu hết để 0. Nếu thu, chỉ nên thu khi success (fail thì refund nguyên vẹn)               |
| F2 ❌ | **Claim launchpad shares** — user nhận vault token sau khi launchpad success                | User sub                   | Khi claim                            | Mint ít share hơn giá trị deposit                                       | Không có tiền lệ đáng kể                                                                              | Tương đương F1 về kinh tế, nhưng UX tệ hơn (user thấy mình nhận thiếu). Tránh                                                                               |
| F3 ❌ | **Subscription settlement** — USDC trong queue được convert thành shares tại `processEpoch` | User sub                   | Tại settlement (rate frozen)         | Entry fee bps trên gross USDC của từng request, trước matching          | OpenEden 5 bps; Backed 20 bps; đa số còn lại 0%                                                       | Điểm thu entry fee *đúng chuẩn* của vault 7540. Mức thị trường thấp (0–20 bps)                                                                              |
| F4 ✅ | **Redemption settlement** — shares trong queue được convert thành USDC tại `processEpoch`   | User redeem                | Tại settlement                       | Exit fee bps trên gross giá trị shares của từng request, trước matching | OpenEden 5 bps; Backed 20 bps; Midas 7 bps; Securitize 0%                                             | Điểm thu exit fee chuẩn. **Bắt buộc thu trên gross per-request** nếu thu — xem fee leakage §6.1                                                             |
| F5 🔶 | **Early-exit penalty** — redeem khi holding chưa đủ N epochs                                | User redeem sớm            | Tại settlement, cộng thêm vào F4     | Track epoch deposit per-user; trừ % nếu tuổi holding < ngưỡng           | Chuẩn TradFi interval fund: **2% nếu rút trong 12 tháng**; HL SCOPE feeder không công bố              | Đúng bản chất asset class (illiquid). Chống yield-tourist vào ra theo epoch. Đổi lại: phải track tuổi holding per-deposit — thêm state                      |
| F6 ❌ | **Cancel request** (ERC-7887) — user rút lại request trước khi settle                       | User cancel                | Khi cancel                           | Phí cố định hoặc bps trên amount cancel                                 | Không tìm thấy tiền lệ thu phí cancel                                                                 | Mục đích duy nhất là chống spam queue. Thường 0; gas tự nhiên đã là rào cản                                                                                 |
| F7 ❌ | **Claim sau settlement** — user nhận shares/USDC đã settle                                  | User                       | Khi claim                            | Trừ vào amount claim                                                    | Không có — anti-pattern                                                                               | Kinh tế học tệ: phạt user vì... nhận tiền của mình. Tránh tuyệt đối                                                                                         |
| F8 🔶 | **Instant exit** — nhận USDC *ngay lập tức* từ liquid buffer, bỏ qua nhịp epoch. ⚠️ Dễ nhầm: thiết kế hiện tại KHÔNG có đường này — đang giữ shares thì muốn rút phải `requestRedeem` → chờ `processEpoch` → claim; "rút bất kỳ lúc nào" chỉ đúng ở nghĩa *gửi request* bất kỳ lúc nào (và cancel khi request còn pending), tiền chỉ về khi epoch settle | User muốn thanh khoản ngay | Khi swap tức thì                     | Spread/phí cao hơn queue path                                           | Ondo OUSG: instant redeem "may incur additional fees"; Maple: spread DEX ~12 bps, giãn khi buffer cạn | Two-tier liquidity: **queue = phí chuẩn, instant = phí cao hơn** — bù chi phí giữ buffer + chống bank-run. Tính năng tương lai, không trong POC/PRD |

*(Không có F9 — mục fee-on-transfer trên secondary transfer đã bỏ khỏi danh mục sau review; giữ nguyên mã số các mục sau để không vỡ tham chiếu.)*


### Nhóm 2 — Fee theo thời gian / AUM (stock-based): thu trên giá trị đang quản lý


| #   | Hành động                                      | Ai trả                | Thời điểm thu                                      | Cơ chế                                                                                | Tiền lệ thị trường                                                                                                               | Nhận xét                                                                                                                                   |
| --- | ---------------------------------------------- | --------------------- | -------------------------------------------------- | ------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| F10 ✅ | **Management fee** — % NAV mỗi năm             | Mọi holder (pro-rata) | Crystallize mỗi `processEpoch`                     | Mint fee shares cho treasury (share dilution), hoặc trừ NAV trước khi tính giá (skim) | Treasury wrappers 0.15–0.50%; HL SCOPE feeder **1.75%**; TradFi evergreen credit **1.0–1.5%**                                    | Fee "xương sống" của mọi fund. Epoch model của chúng ta cho điểm crystallize tự nhiên. Chi tiết cơ chế §5.2                                |
| F11 🔶 | **Performance fee** — % phần NAV tăng vượt mốc | Mọi holder            | Crystallize tại epoch khi giá vượt high-water mark | HWM per-share on-chain; mint fee shares trên phần profit                              | Midas 10% trên interest; TradFi credit 10–12.5% trên hurdle ~5%; HL PAF 10% (bỏ hurdle từ 2025); Lagoon có HWM on-chain, cap 50% | Hợp lý về incentive, nhưng **nguy hiểm khi NAV do admin set** — xem §6.2. Lưu ý: chưa protocol DeFi lớn nào implement hurdle rate on-chain |


### Nhóm 3 — Fee vận hành / ngầm (implicit): không hiện trên biểu phí


| #   | Hành động                                                                 | Ai trả                  | Thời điểm thu                    | Cơ chế                                                       | Tiền lệ thị trường                                                                            | Nhận xét                                                                                                                                                                         |
| --- | ------------------------------------------------------------------------- | ----------------------- | -------------------------------- | ------------------------------------------------------------ | --------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| F12 ❌ | **Yield spread** — credit NAV thấp hơn yield thực của underlying          | Mọi holder (ẩn)         | Liên tục, qua cách admin set giá | Off-chain: underlying 8.8%, NAV tăng 8.0%, platform giữ 0.8% | Ondo USDY giữ ~25 bps; Maple giữ 15–20% gross interest                                        | Vô hình với user ("0 fee!"), không audit được on-chain. Doanh thu phụ thuộc hoàn toàn vào tính trung thực của `setPrice()`                                                       |
| F13 ❌ | **Liquid swap spread** — margin khi Custody swap liquid ↔ USDC            | User redeem (gián tiếp) | Mỗi lần swap layer 2             | Cộng spread vào tỷ giá swap nội bộ                           | Maple: spread thị trường tự nhiên ~12 bps                                                     | Trong POC swap là mock 1:1. Production: chi phí swap *thật* đằng nào cũng tồn tại — câu hỏi là pass-through hay cộng margin                                                      |
| F14 ❌ | **Idle-cash yield** — yield Aave trên USDC nằm trong sub queue            | — (yield từ tiền user)  | Trong thời gian chờ epoch        | USDC queue gửi Aave, rút trước khi settle                    | PRD có nhắc reinvest này. Benchmark: không nền tảng nào công bố giữ riêng phần này            | **Câu hỏi mở quan trọng**: yield này thuộc về user (cộng vào số USDC settle) hay platform (giữ làm doanh thu)? PRD không nói. Hai lựa chọn đều có lý — cần quyết định tường minh |
| F15 ❌ | **Keeper / gas recovery** — bù chi phí gọi `processEpoch`                 | Treasury hoặc holder    | Mỗi epoch                        | Trích bps, hoặc treasury tự trả                              | **Không nền tảng nào thu keeper fee bps riêng** — chi phí ngầm trong mgmt fee (Lagoon, Yearn) | Theo benchmark: không thu riêng, coi như chi phí vận hành đã nằm trong F10                                                                                                       |
| F16 ❌ | **Wind-down / liquidation fee** — phí thanh lý khi đóng vault             | Holder còn lại          | Khi wind-down                    | Trừ % trên proceeds thanh lý                                 | Midas: "liquidation costs embedded" trong redemption; không ai thu fee wind-down tường minh   | Chi phí thanh lý *thật* (swap, redeem Pruv) là pass-through tự nhiên. Thu thêm fee lúc đóng quỹ → rủi ro pháp lý/uy tín cao. Tránh                                               |
| F17 ❌ | **Pruv layer pass-through** — phí sub/redeem của underlying + bridge cost | Tuỳ thiết kế            | Mỗi lần Custody tương tác Pruv   | Pass nguyên chi phí vào rate, hoặc platform nuốt             | Mọi feeder fund đều pass-through chi phí underlying (đó là lý do NAV feeder < NAV gross)      | Không phải "fee của chúng ta" nhưng phải quyết: hiển thị tách bạch hay gộp vào NAV. POC: Pruv là mock, chi phí = 0                                                               |


### Bản đồ tổng hợp lên `processEpoch`

Phần lớn các điểm thu phí hội tụ về một chỗ — đúng như thiết kế single `processEpoch` của chúng ta:

```
  processEpoch() — trình tự với đầy đủ fee hooks
  ═══════════════════════════════════════════════════════════════
  1. setPrice(NAV)            ◀── [F12] spread đã "ẩn" trong giá này
  2. accrue mgmt fee          ◀── [F10] mint fee shares cho treasury
  3. accrue perf fee (nếu có) ◀── [F11] so HWM, mint fee shares
  ──────────────────────────────────────────────────────────────
  4. TÍNH GROSS từng request:
       sub_i  = USDC_i  − entryFee_i      ◀── [F3] per-request
       red_j  = value_j − exitFee_j       ◀── [F4] per-request
                        − earlyExit_j     ◀── [F5] nếu holding < N epochs
     (thu fee TRƯỚC matching — chống leakage, xem §6.1)
  ──────────────────────────────────────────────────────────────
  5. MATCHING: net(Σsub_net, Σred_net)    ◀── không fee tại đây
  6. Layer 2: swap liquid → USDC          ◀── [F13] spread nếu có
  7. Layer 3: redeem Pruv                 ◀── [F17] pass-through
  8. settle, lock rates, cho phép claim   ◀── [F7] KHÔNG thu ở claim
  ═══════════════════════════════════════════════════════════════
```

---

## 4. Benchmark — các nền tảng khác thu phí thế nào

Data đầy đủ kèm citation từng dòng: `research-raw.md`. Dưới đây là bản chắt lọc.

### 4.1 Bảng so sánh


| Nền tảng / sản phẩm                    | Loại tài sản                                       | Mgmt fee/năm                                      | Perf fee                                            | Entry           | Exit / rút sớm                                | Cách thu                              |
| -------------------------------------- | -------------------------------------------------- | ------------------------------------------------- | --------------------------------------------------- | --------------- | --------------------------------------------- | ------------------------------------- |
| BlackRock BUIDL (Securitize)           | T-Bills                                            | 0.20–0.50% (theo chain)                           | —                                                   | —               | —                                             | Trừ NAV; yield trả bằng token mới     |
| Franklin BENJI                         | T-Bills (MMF)                                      | 0.15% (TER 0.20%)                                 | —                                                   | —               | —                                             | Expense ratio trừ NAV                 |
| Superstate USTB                        | T-Bills                                            | 0.15% (giảm còn 0.05% phần >$25M)                 | —                                                   | —               | —                                             | Trừ NAV                               |
| Centrifuge JTRSY (Anemoy/Janus)        | T-Bills                                            | 0.15%                                             | —                                                   | —               | —                                             | Trừ NAV                               |
| Ondo OUSG                              | T-Bills (qua BUIDL)                                | 0.15% (đang miễn đến 7/2026)                      | —                                                   | —               | Instant redeem có phụ phí (bps không công bố) | NAV + phí trên flow instant           |
| Ondo USDY                              | T-Bills + deposits                                 | **~25 bps spread (ẩn)**                           | —                                                   | 0               | ~20 bps (cần xác nhận lại)                    | **Yield spread** — giữ chênh lệch     |
| OpenEden TBILL                         | T-Bills                                            | 0.30%                                             | —                                                   | **5 bps**       | **5 bps**                                     | TER trừ NAV + fee trên flow           |
| Backed bIB01                           | Bond ETF                                           | 0.25%                                             | —                                                   | **20 bps**      | **20 bps**                                    | Fee mint/burn + NAV                   |
| Midas mTBILL                           | T-Bills                                            | 0%                                                | **10% trên interest**                               | 0               | 7 bps                                         | Perf fee thay mgmt fee                |
| Maple syrupUSDC                        | Private credit                                     | Delegate-set; protocol giữ ~15–20% gross interest | (gộp trong đó)                                      | —               | Queue miễn phí / instant = DEX spread ~12 bps | **Cắt từ dòng interest** của borrower |
| Securitize × HL SCOPE feeder           | **Evergreen private credit** ← giống chúng ta nhất | **1.75%** (feeder)                                | 0% ở feeder (underlying không công khai)            | 0               | 0 qua Securitize; redeem theo NAV quý trước   | Trừ NAV feeder                        |
| Hamilton Lane PAF (tham chiếu TradFi)  | Evergreen PE/credit                                | 1.5%                                              | **10%** (12.5%/hurdle 8% trước 2025; nay bỏ hurdle) | —               | —                                             | Trừ NAV + carry quý                   |
| Chuẩn TradFi interval/evergreen credit | Private credit                                     | **1.0–1.5% NAV**                                  | **10–20%, phổ biến 12.5% trên hurdle ~5%**          | Tuỳ share class | **2% nếu rút <12 tháng**; cap redeem 5%/quý   | Trừ NAV + trừ proceeds khi rút sớm    |


### 4.2 Đọc bảng này thế nào

```
   FEE TỔNG (%/năm)
        │
  2.5%  ┤                                    ░ TradFi evergreen
        │                                    ░ (1.5% + perf + 2% early)
  2.0%  ┤                              ▓ HL SCOPE feeder (1.75%)
        │
  1.0%  ┤
        │
  0.5%  ┤      ▒ BUIDL (0.5% ETH)
        │  ▒ OpenEden (0.3+flow)
        │  ▒ Backed (0.25+40bps flow)
  0.15% ┤  ▒ USTB/BENJI/JTRSY/OUSG
        │  ▒ USDY (spread ẩn 25bps)
     0  └──┴──────────┴──────────────┴────────────▶
         Treasury     Hỗn hợp       Private credit
         (thanh khoản cao)          (illiquid — CHÚNG TA Ở ĐÂY)
```

Ba quy luật rút ra:

1. **Fee tỉ lệ thuận độ illiquid của underlying.** Treasury wrapper cạnh tranh nhau về fee thấp (0.15% thành mặt bằng). Private credit giữ fee TradFi gần như nguyên vẹn khi lên chain (1.5–1.75%) — token hoá *chưa* ép giá fee của asset class này.
2. **Entry/exit fee tường minh đang biến mất** ở treasury (0 là chuẩn), nhưng **early-exit penalty vẫn là chuẩn ở evergreen** vì nó bảo vệ holder ở lại khỏi chi phí thanh lý do người rút sớm gây ra.
3. **Hai trường phái doanh thu**: fee tường minh (đa số) vs spread ẩn (USDY, Maple). Spread cho UX "0 fee" nhưng đổi bằng minh bạch.

---

## 5. Cơ chế kỹ thuật — thu phí on-chain thế nào

Mục này trả lời hai câu hỏi: **thu khi nào** (§5.1) và **thu bằng cách nào** — stock fee qua mint fee shares (§5.2), flow fee trừ tại settlement (§5.3), và trường hợp riêng của performance fee (§5.4).

### 5.1 Thu khi nào

Nguyên tắc: **stock fee (quản lý, hiệu suất) thu mỗi epoch, từ toàn bộ vault; flow fee (phí rút, phạt rút sớm) thu một lần, tại settlement của request.** Không fee nào thu lúc claim, và không fee nào "để dành" đến lúc redeem — giá shares phản ánh phí dần đều:

```
  TIMELINE                 epoch 1        epoch 2        epoch 3      user redeem
  ─────────────────────────┼──────────────┼──────────────┼──────────────┼─────▶
                           │              │              │              │
  Phí quản lý (1.5%/năm)   ✂ thu          ✂ thu          ✂ thu          (đã nằm
   → mint fee shares       │              │              │              trong giá,
     cho treasury          │              │              │              không thu nữa)
                           │              │              │
  Phí hiệu suất (10%)      –              ✂ thu nếu giá  –
   → chỉ khi giá vượt đỉnh │                vượt đỉnh cũ │
                           │              │              │              │
  Phí rút (0.5%)           –              –              –              ✂ thu TẠI ĐÂY
                                                                        trừ vào tiền nhận
```

**Vì sao stock fee không dồn vào lúc redeem?**

1. **Giá giữa các kỳ sẽ sai** — phí chưa trừ vào NAV thì người rút trước "ăn" phần phí lẽ ra mình chịu, người ở lại gánh thay. Trừ mỗi epoch → ai giữ bao lâu trả đúng bấy nhiêu.
2. **User giữ lâu bị sốc phí** — giữ 3 năm bị trừ 4.5% một cục; người không bao giờ redeem thì không bao giờ trả.
3. **Kế toán phình to** — phải track thời gian nắm giữ từng khoản deposit, thay vì một phép tính mỗi epoch cho cả vault.

Đây cũng là chuẩn ngành: quỹ TradFi trừ phí quản lý vào NAV hằng ngày; model epoch làm điều tương tự theo nhịp `processEpoch` (Lagoon, Centrifuge cùng pattern).

**Vì sao flow fee thu tại settlement, không phải lúc request hay lúc claim?** Vault async (ERC-7540) không biết giá tại thời điểm user request — giá chỉ chốt khi settle. Claim chỉ là nhận đồ đã chia xong:

```
  request ──▶ pending ──▶ SETTLEMENT ──▶ claimable ──▶ claim
  (user ký,    (có thể     (processEpoch:    (đợi user      (nhận token,
   chưa biết    cancel      RATE FROZEN,      đến lấy)       KHÔNG fee)
   giá)         7887)       FEE THU TẠI ĐÂY)
```

**Bản đồ đầy đủ trên vòng đời vault.** Timeline đầu mục chỉ vẽ 3 fee user thực trả theo đề xuất (F10, F11, F4+F5). Toàn bộ 16 điểm của danh mục §3:

```
              LAUNCHPAD          EPOCH-BASED (lặp lại mỗi epoch)         WIND-DOWN
  ────────────┼──────────────────┼────────────────────────────────────────┼──────▶
              │                  │                                        │
  Thu thật:   –                  ✂ F10 mgmt (mỗi epoch)                   –
              │                  ✂ F11 perf (epoch vượt đỉnh, production) │
              │                  ✂ F4+F5 phí rút + phạt sớm (khi settle   │
              │                     redeem request của user)              │
              │                  │                                        │
  Đề xuất 0:  F1 lock, F2 claim  F3 entry, F6 cancel, F7 claim, F16 đóng quỹ
              │                  │                                        │
  Chi phí ngầm│                  F12 spread (loại), F13 swap, F14 idle    F13+F17
  /pass-thru: │                  yield (→user), F15 gas, F17 Pruv         thanh lý
              │                  │                                        │
  Ngoài epoch:                   F8 instant exit (tương lai, trả phí riêng)
```

- **Thu thật** — F10, F11, F4+F5: như timeline đầu mục.
- **Đề xuất 0 / loại có chủ đích** — F1, F2, F3, F6, F7, F16 (lý do từng điểm: cột Nhận xét, §3).
- **Chi phí ngầm / pass-through** — F12 loại (chọn fee tường minh thay spread ẩn); F13/F17 pass-through gộp vào NAV; F14 trả về user; F15 nằm trong mgmt fee.
- **Ngoài nhịp epoch** — F8 instant exit: tính năng tương lai, đường thanh khoản trả phí riêng bên cạnh queue.

### 5.2 Thu stock fee bằng cách nào — mint fee shares (pha loãng)

Share = quyền sở hữu một phần vault (`giá = totalAssets / totalSupply`), nên thu phí thực chất là **chuyển một phần quyền sở hữu từ user sang treasury**. Mint shares mới cho treasury làm đúng điều đó — không cần di chuyển đồng USDC nào. Ví dụ epoch 1 tháng, mgmt 1.5%/năm:

```
  TRƯỚC                                SAU KHI MINT FEE SHARES
  ─────────────────────────           ─────────────────────────────────
  totalAssets : 1,000,000 USDC        totalAssets : 1,000,000 USDC  (KHÔNG ĐỔI)
  totalSupply : 1,000,000 shares      totalSupply : 1,001,251.6     (tăng)
  giá/share   : 1.00                  giá/share   : 0.99875         (giảm)

  Users    : 1,000,000 sh = $1,000,000    Users    : 1,000,000 sh = $998,750  (−1,250)
  Treasury :         0 sh = $0            Treasury :   1,251.6 sh = $1,250    (+1,250)
                                                          └── đúng bằng phí của kỳ
                                          (1,250 = 1,000,000 × 1.5% × 1/12)
```

Tổng tài sản không đổi; phần của user nhỏ đi đúng 1,250, phần của treasury to ra đúng 1,250 — **phí đã được thu, bằng pha loãng**. Treasury muốn USDC thật thì đưa fee shares vào redemption queue như mọi user khác, hoặc giữ lại để tiếp tục hưởng yield.

Công thức (Yearn v3, MetaMorpho, Lagoon cùng dạng):

```
  feeAssets = totalAssets × mgmtBps × Δt / (365 days × 10 000)
  feeShares = feeAssets × totalSupply / (totalAssets − feeAssets)
                                        ^^^^^^^^^^^^^^^^^^^^^^^
                          mẫu số PHẢI trừ feeAssets (giá sau fee),
                          nếu không treasury bị credit thừa
                          (bug kinh điển — MetaMorpho xử lý đúng)
```

Hai câu hỏi thiết kế đi kèm:

**Vì sao không trả treasury bằng USDC?** Vault không có sẵn cash — 80–90% nằm trong illiquid, buffer liquid để dành trả redemption; mint shares tốn 0 thanh khoản. Quan trọng hơn, treasury "cùng thuyền" với holder: nếu admin bơm NAV để thu phí nhiều hơn, phí nhận về là shares của chính vault đang bị định giá ảo, không phải cash cầm đi luôn.

**Vì sao crystallize mỗi epoch, không liên tục hay trừ thẳng vào giá?** Ba biến thể tồn tại trong thực tế:

|                     | Dilution liên tục (Yearn, Morpho)        | NAV skim (Veda)               | Epoch crystallization (Lagoon, Centrifuge) |
| ------------------- | ---------------------------------------- | ----------------------------- | ------------------------------------------ |
| Cách thu            | Mint fee shares mỗi deposit/withdraw     | Admin post giá đã trừ fee     | Mint fee shares 1 lần tại settle           |
| Gas hot path        | Trung bình                               | Thấp nhất                     | **Thấp (1 lần/epoch)**                     |
| Manipulation        | Thấp nếu interest on-chain               | **Cao nhất** (admin post giá) | Gắn NAV epoch; bound bằng fee cap          |
| Minh bạch           | Cao (event mỗi mint)                     | Thấp (fee tàng hình trong giá)| **Cao (event mỗi epoch)**                  |
| Khớp model chúng ta | Thừa (không có hot path liên tục)        | Trùng hố admin-NAV sẵn có     | ✅ Tự nhiên nhất                            |

### 5.3 Thu flow fee bằng cách nào — trừ tại settlement, công thức OpenZeppelin

Dùng đúng 2 helper của `ERC4626Fees` (đã audit, rounding về phía vault):

```solidity
// fee cộng THÊM trên amount net (user chỉ định net leg):
feeOnRaw(assets, bps)   = assets.mulDiv(bps, 1e4, Ceil);

// fee đã NẰM TRONG amount gross (user chỉ định gross leg):
feeOnTotal(assets, bps) = assets.mulDiv(bps, bps + 1e4, Ceil);
```

Với queue của chúng ta: request luôn là gross (user bỏ X USDC vào queue / Y shares vào queue) → dùng `feeOnTotal` tại settlement.

### 5.4 Performance fee — high-water mark on-chain

Lagoon là tiền lệ sạch nhất:

```
  nếu pricePerShare > HWM:
      profit  = (pricePerShare − HWM) × totalSupply
      perfFee = profit × rate / 10 000          (cap on-chain 50%)
      mint feeShares tương ứng; HWM := pricePerShare
  nếu lỗ: không fee; HWM giữ nguyên → phải gỡ lỗ xong mới được thu tiếp
```

Lưu ý từ benchmark: **không protocol lớn nào implement hurdle rate on-chain** (chuẩn TradFi 5–8%) — nếu muốn hurdle, chúng ta tự viết, không có tiền lệ để copy.

---

## 6. Rủi ro đặc thù của model này

### 6.1 Fee leakage qua matching (điểm độc đáo nhất của model chúng ta)

Matching layer 1 net sub queue với redeem queue. Nếu thu fee **sau** khi net:

```
  SAI — thu fee trên NET flow:
  ┌────────────────────────────────────────────────────────┐
  │  Sub queue: 10 000 USDC      Redeem queue: 4 000 USDC  │
  │                    ╲          ╱                         │
  │                  match 4 000 (KHÔNG fee!)               │
  │                         │                               │
  │              net 6 000 → thu fee chỉ trên 6 000        │
  │                                                         │
  │  → 8 000 USDC volume (4k sub + 4k redeem) NÉ ĐƯỢC FEE  │
  │  → cặp user thông đồng deposit+redeem cùng epoch        │
  │    = rút tiền qua vault MIỄN PHÍ vĩnh viễn              │
  └────────────────────────────────────────────────────────┘

  ĐÚNG — thu fee trên GROSS từng request, TRƯỚC matching:
  ┌────────────────────────────────────────────────────────┐
  │  sub_i  : 10 000 − fee(10 000)  →  net vào matching     │
  │  red_j  :  4 000 − fee(4 000)   →  net vào matching     │
  │                    ╲          ╱                         │
  │                  match trên số ĐÃ TRỪ fee               │
  │                                                         │
  │  → matching chỉ tiết kiệm chi phí swap/Pruv,            │
  │    không bao giờ né được fee                            │
  └────────────────────────────────────────────────────────┘
```

Không nền tảng nào (Centrifuge, Lagoon) công bố cách họ xử lý vụ này — đây là **thiết kế chúng ta phải tự chốt đúng**, và là lý do mạnh nhất để mọi flow fee trong model này thu per-request gross tại settlement.

### 6.2 Performance fee × NAV thủ công = hố đã biết

NAV của chúng ta là admin `setPrice()`. Nếu có perf fee:

```
  Epoch 1: giá thật 1.00 → admin set 1.00         HWM = 1.00
  Epoch 2: giá thật 1.02 → admin set 1.10 (bơm!)  → crystallize perf fee
           trên 0.10 thay vì 0.02 → treasury nhận fee shares ×5
  Epoch 3: admin set lại 1.02 ("điều chỉnh")      → holder gánh lỗ,
                                                     fee không hoàn
```

Mitigation có tiền lệ (đều áp dụng được):

- **Deviation bound**: `setPrice` không được lệch quá X% so với giá trước (Veda).
- **Fee cap on-chain**: perf rate ≤ cap cứng, ví dụ 20% (Morpho/Lagoon cap 50%).
- **Lower-only**: fee rate chỉ giảm được, không tăng được sau deploy (Lagoon).
- **Timelock** cho thay đổi tham số fee.
- Gốc rễ: chừng nào NAV còn thủ công, perf fee là fee có rủi ro governance cao nhất trong danh mục §3.

### 6.3 Early-exit penalty cần state mới

F5 đòi hỏi track **epoch deposit của từng user** (hoặc từng lô deposit). Hiện spec chưa có state này. Câu hỏi thiết kế nếu chọn: tính theo lô (FIFO) hay theo weighted-average epoch? FIFO đúng hơn nhưng tốn state hơn.

### 6.4 Idle-cash yield là quyết định kinh tế, không phải kỹ thuật

F14 (yield Aave trên USDC chờ trong queue — PRD có nhắc): về code chỉ là cộng vào đâu, nhưng về kinh tế là chọn **ai hưởng**: user (settle nhiều USDC hơn) hay platform (doanh thu). Benchmark không có tiền lệ công khai. Cần chốt tường minh trước production; POC hiện không reinvest nên chưa chạm.

---

## 7. Ba phương án fee structure

> ⚠️ **Chưa quyết định.** Ba phương án dưới đây là tổng hợp từ benchmark — trình bày trade-off, không khuyến nghị chốt. Chi tiết đánh giá từng tiêu chí: `options.md`.

### Phương án A — "Spread-only" (kiểu Ondo USDY)

Không fee tường minh nào. Platform giữ chênh lệch yield qua cách set NAV: underlying 8.8% → NAV tăng 8.0% → giữ 0.8%/năm.

- Gồm: F12.
- **+** Zero code thêm; UX "0 fee"; không có flow fee nên không có leakage.
- **−** Opaque hoàn toàn; không demo được cơ chế nào on-chain; dồn toàn bộ trust vào `setPrice()`.

### Phương án B — "Evergreen standard" (đúng chuẩn TradFi của asset class)


| Fee                          | Mức tham chiếu thị trường        | Map danh mục               |
| ---------------------------- | -------------------------------- | -------------------------- |
| Management 1.5%/năm          | TradFi 1.0–1.5%; HL feeder 1.75% | F10, crystallize mỗi epoch |
| Performance 10% trên HWM     | HL PAF 10%; TradFi 10–12.5%      | F11 + guardrails §6.2      |
| Early-exit 2% nếu < N epochs | Chuẩn interval fund 2%/<12 tháng | F5 + state mới §6.3        |


- **+** Giống fund thật nhất; demo đầy đủ cả 3 họ fee; doanh thu cao nhất.
- **−** Nặng nhất (+1.5–2 ngày POC: HWM, tuổi holding, guardrails); ôm rủi ro §6.2.

### Phương án C — "Flow + mgmt lean" (2 cơ chế đại diện)


| Fee                                    | Mức tham chiếu                                  | Map danh mục                  |
| -------------------------------------- | ----------------------------------------------- | ----------------------------- |
| Management 1.5%/năm                    | Như B                                           | F10, crystallize mỗi epoch    |
| Exit fee 50 bps trên gross per-request | OpenEden/Backed 5–20 bps; cộng premium illiquid | F4, thu trước matching (§6.1) |
| Không perf fee, không early-exit       | —                                               | Né §6.2, §6.3                 |


- **+** Nhẹ (+0.5–1 ngày POC); demo được cả stock-fee lẫn flow-fee **và** lời giải fee-leakage (điểm độc đáo của model); risk thấp nhất.
- **−** Thiếu performance-based; doanh thu mô phỏng kém asset class hơn B.

### Đặt cạnh nhau

```
                 A: Spread        B: Evergreen full     C: Lean
                 ─────────        ─────────────────     ───────
  Fee on-chain   (không)          F10+F11+F5            F10+F4
  Effort POC     ~0               +1.5–2 ngày           +0.5–1 ngày
  Minh bạch      ▁                ████████              ██████
  Risk admin-NAV ████████         █████ (cần guardrail) ██
  Giống TradFi   ▁▁               ████████              ████
  Demo mechanism ▁                ████████              ██████
```

---

## 8. Tiêu chí quyết định & câu hỏi mở

### Quyết định phương án nên dựa trên 3 câu hỏi, theo thứ tự:

1. **POC này cần chứng minh điều gì với stakeholder?**
  - Chỉ mechanism vận hành (sub/redeem/matching chạy đúng) → fee có thể để sau (giữ 0% hoặc A).
  - Mechanism **+ economic viability** (L3 trong SUMMARY.md) → cần fee on-chain thật (B hoặc C).
2. **Production có chấp nhận NAV thủ công lâu dài không?**
  - Có → perf fee (B) cần đầy đủ guardrails §6.2, hoặc tránh hẳn (C).
  - Không (sẽ có oracle/attestation) → B trở nên an toàn hơn đáng kể.
3. **Underlying thật (Hamilton Lane qua Pruv) charge chúng ta bao nhiêu?**
  - Fee của chúng ta là lớp chồng lên fee underlying — tổng stack quyết định APY net cho retail có còn hấp dẫn không. Chưa có số này (prospectus SCOPE không truy cập được) → cần lấy qua kênh chính thức trước khi chốt mức %.

### Câu hỏi mở (cần trả lời trước production, không chặn POC)


| #   | Câu hỏi                                                                                             | Liên quan |
| --- | --------------------------------------------------------------------------------------------------- | --------- |
| O1  | Fee stack tổng (underlying + chúng ta) để lại bao nhiêu APY net cho retail? Mức nào còn cạnh tranh? | §8.3      |
| O2  | Idle-cash yield (Aave trên sub queue) thuộc về user hay platform?                                   | F14, §6.4 |
| O3  | Có làm instant-exit path (trả phí) bên cạnh queue (miễn phí) không?                                 | F8        |
| O4  | Treasury nhận fee shares hay USDC? (shares = cùng thuyền với holder; USDC = doanh thu chắc chắn)    | §5.2      |
| O5  | Tham số fee để hardcode, owner-set có timelock, hay immutable sau deploy?                           | §6.2      |
| O6  | Khi có số fee thật của HL SCOPE: pass-through hiển thị tách bạch hay gộp vào NAV?                   | F17       |


### Việc tiếp theo đề xuất

1. Chốt phương án (A/B/C hoặc biến thể) — quyết định ở cấp product, dùng 3 câu hỏi trên.
2. Nếu chọn có fee on-chain: bổ sung interface (`feeConfig`, `treasury`, event `FeeAccrued`) vào ADR-001 và cập nhật `05-spec.md` (pseudocode `processEpoch` bước 2–4 ở §3).
3. Lấy biểu phí chính thức của underlying qua kênh Hamilton Lane/Pruv để trả lời O1.

---

## Phụ lục — Nguồn

Toàn bộ citation chi tiết từng claim (URL + ngày + cờ unverified): xem `research-raw.md`. Các nguồn chính:

- EIP-7540 — [https://eips.ethereum.org/EIPS/eip-7540](https://eips.ethereum.org/EIPS/eip-7540)
- OpenZeppelin ERC4626Fees — [https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/mocks/docs/ERC4626Fees.sol](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/mocks/docs/ERC4626Fees.sol)
- Lagoon fees (HWM on-chain) — [https://docs.lagoon.finance/vault/fees](https://docs.lagoon.finance/vault/fees)
- MetaMorpho fee — [https://docs.morpho.org/curate/concepts/fee/](https://docs.morpho.org/curate/concepts/fee/)
- Yearn v3 accountant — [https://docs.yearn.fi/developers/v3/periphery](https://docs.yearn.fi/developers/v3/periphery)
- Veda BoringVault — [https://docs.veda.tech/architecture-and-flow-of-funds/core-components](https://docs.veda.tech/architecture-and-flow-of-funds/core-components)
- Ondo OUSG/USDY — [https://docs.ondo.finance/qualified-access-products/ousg/fees-and-taxes](https://docs.ondo.finance/qualified-access-products/ousg/fees-and-taxes)
- OpenEden TBILL — [https://docs.openeden.com/tbill/fees](https://docs.openeden.com/tbill/fees)
- Maple instant liquidity — [https://maple.finance/insights/instant-liquidity-for-syrupusdc](https://maple.finance/insights/instant-liquidity-for-syrupusdc)
- Securitize × Hamilton Lane SCOPE — [https://securitize.io/learn/press/securitize-expands-access-to-hamilton-lanes-senior-credit-opportunities-fund-via-polygon](https://securitize.io/learn/press/securitize-expands-access-to-hamilton-lanes-senior-credit-opportunities-fund-via-polygon) ; [https://app.rwa.xyz/assets/HLSCOPE](https://app.rwa.xyz/assets/HLSCOPE)
- HL PAF restructure 2025 — [https://www.transacted.io/hamilton-lane-restructures-retail-fund-carry-model-for-faster-fee-realization](https://www.transacted.io/hamilton-lane-restructures-retail-fund-carry-model-for-faster-fee-realization)
- Interval fund fees (TradFi) — [https://www.morningstar.com/funds/5-things-you-need-know-about-interval-fund-fees](https://www.morningstar.com/funds/5-things-you-need-know-about-interval-fund-fees)
- Swing pricing (TradFi ref) — [https://www.iosco.org/library/pubdocs/pdf/IOSCOPD756.pdf](https://www.iosco.org/library/pubdocs/pdf/IOSCOPD756.pdf)

**Cờ chưa verify được (quan trọng):** biểu phí underlying của HL SCOPE (prospectus bị chặn truy cập) — mọi con số về SCOPE trong report là ở tầng feeder (RWA.xyz) hoặc suy từ fund HL khác (PAF). Cần số chính thức trước khi chốt mức fee production.