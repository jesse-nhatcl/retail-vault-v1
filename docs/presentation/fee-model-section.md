# Fee Model — Bản chắt lọc cho trình bày

> **Nguồn:** `docs/fee-research.md` (503 dòng, citation đầy đủ tại `research-raw.md`).
> **Trạng thái:** Nghiên cứu — **CHƯA chốt phương án**. POC hiện tại để **fee = 0%** (Q6 deferred).
> **Mục đích file này:** nội dung nguồn để dựng một section "Fee Model" trong `feasibility-brief.html`.

---

## 1. Năm điều cần nhớ (lớp exec)

1. **PRD không nói gì về fee** — đây là vùng thiết kế mở. Research trả lời 4 câu: thu được ở đâu, thị trường làm thế nào, cơ chế on-chain ra sao, và phương án nào khả thi.
2. **Thị trường chia 2 cực rõ rệt** — và **fee tỉ lệ thuận với độ illiquid của tài sản nền**:
  - Treasury wrappers (BUIDL, BENJI, USTB…): **0.15–0.50%**, gần như không phí gì khác.
  - Private credit / evergreen — **đúng nhóm tài sản của chúng ta**: **mgmt 1.0–1.75% + perf 10–12.5% trên hurdle + early-exit 2%** nếu rút sớm.
3. **Token hoá chưa ép được fee của nhóm private credit** — lên chain vẫn giữ gần nguyên mức TradFi (1.5–1.75%). Chúng ta nằm ở **cực cao**, không phải cực 0.15%.
4. **Kiến trúc async (ERC-7540) của chúng ta thu phí tại `processEpoch`** — không phải lúc user request, không phải lúc claim. Điều này khớp tự nhiên với thiết kế single-`processEpoch`.
5. **Một rủi ro thật riêng cho model này** (§4): performance fee cộng với NAV set tay → **hố thao túng giá**, nối thẳng vào quyết định oracle. (Một chi tiết nhỏ khi code *flow fee*: thu trên gross từng request — §4.2.)

---

## 2. Thị trường thu phí thế nào — bảng benchmark chắt lọc

Chọn các sản phẩm tiêu biểu cho 2 cực + sản phẩm **giống chúng ta nhất** (HL SCOPE).


| Nền tảng                                  | Tài sản nền                  | Mgmt/năm                   | Perf                      | Entry     | Exit / rút sớm               |
| ----------------------------------------- | ---------------------------- | -------------------------- | ------------------------- | --------- | ---------------------------- |
| BlackRock BUIDL                           | T-Bills                      | 0.20–0.50%                 | —                         | —         | —                            |
| Franklin BENJI                            | T-Bills                      | 0.15%                      | —                         | —         | —                            |
| OpenEden TBILL                            | T-Bills                      | 0.30%                      | —                         | 5 bps     | 5 bps                        |
| Backed bIB01                              | Bond ETF                     | 0.25%                      | —                         | 20 bps    | 20 bps                       |
| Midas mTBILL                              | T-Bills                      | 0%                         | **10% trên lãi**          | 0         | 7 bps                        |
| Maple syrupUSDC                           | Private credit               | giữ ~15–20% gross interest | (gộp)                     | —         | queue free / instant ~12 bps |
| **Securitize × HL SCOPE** ⟵ giống ta nhất | **Evergreen private credit** | **1.75%** (feeder)         | n/a feeder                | 0         | redeem theo NAV quý trước    |
| Hamilton Lane PAF (TradFi)                | Evergreen PE/credit          | 1.5%                       | **10%**                   | —         | —                            |
| Chuẩn interval/evergreen credit           | Private credit               | **1.0–1.5%**               | **12.5% trên hurdle ~5%** | tuỳ class | **2% nếu rút <12 tháng**     |


**Hình dung 1 dòng:** càng sang phải (tài sản càng kém thanh khoản), fee càng cao.
`Treasury 0.15%  →  hỗn hợp 0.25–0.5%  →  private credit 1.5–1.75% + perf + early-exit`  ← **chúng ta ở cực này**.

> ⚠️ **Cờ chưa verify:** biểu phí *underlying* của HL SCOPE bị chặn truy cập (prospectus). Mọi con số SCOPE ở đây là tầng **feeder** (RWA.xyz) hoặc suy từ quỹ HL khác (PAF). Cần số chính thức trước khi chốt mức % cho production.

---

## 3. Phí gắn vào model của chúng ta ở đâu

Hầu hết điểm thu phí **hội tụ về một chỗ: `processEpoch`** — đúng tinh thần thiết kế.

```
processEpoch():
  1. setPrice(NAV)              ◀ spread ẩn (nếu chọn) nằm trong giá này
  2. accrue management fee      ◀ mỗi epoch, mint fee shares cho treasury
  3. accrue performance fee     ◀ chỉ khi NAV vượt high-water mark
  4. tính GROSS từng request:
        sub  = USDC  − entryFee
        red  = value − exitFee − earlyExitPenalty   ◀ flow fee: gross, trước matching (§4.2)
  5. MATCHING                   ◀ KHÔNG thu phí tại đây
  6. Layer 2/3 sourcing         ◀ chi phí swap/Pruv = pass-through
  7. settle → claim             ◀ KHÔNG bao giờ thu phí lúc claim
```

**Quy tắc thời điểm:**

- **Stock fee** (quản lý, hiệu suất): thu **mỗi epoch**, trên toàn vault → ai giữ lâu trả nhiều, công bằng giữa các holder.
- **Flow fee** (phí rút, phạt rút sớm): thu **một lần tại settlement** của request.
- **Không bao giờ thu lúc claim** — claim chỉ là nhận phần đã chia; thu ở đó = phạt user vì nhận tiền của chính mình.

**Đề xuất nên / không nên thu** (verdict trong research):

- ✅ Nên thu: **Management fee** (xương sống mọi quỹ), **Exit fee** (chuẩn vault 7540).
- 🔶 Để production / tương lai: **Performance fee** (cần guardrails), **Early-exit penalty** (cần thêm state), **Instant-exit** (đường thanh khoản trả phí riêng).
- ❌ Không thu: phí lúc lock launchpad, lúc claim, lúc cancel, lúc wind-down — đều phản tác dụng hoặc không có tiền lệ.

---

## 4. Điểm cần lưu ý khi áp phí vào model này

### 4.1 Performance fee × NAV thủ công = hố đã biết (rủi ro thật)

NAV của chúng ta do admin `setPrice()`. Nếu có perf fee, admin có thể **bơm giá để chốt phí ảo**:

```
Epoch 2: giá thật 1.02 → admin set 1.10 → crystallize perf fee trên 0.10 (×5)
Epoch 3: set lại 1.02 "điều chỉnh"       → holder gánh lỗ, fee không hoàn
```

**Mitigation có tiền lệ:** deviation bound trên `setPrice` (Veda) · fee cap on-chain (Morpho/Lagoon cap 50%) · rate chỉ-giảm sau deploy (Lagoon) · timelock đổi tham số. **Gốc rễ:** chừng nào NAV còn thủ công, perf fee là loại phí rủi ro governance cao nhất → liên quan trực tiếp tới seam `INavSource` và quyết định oracle.

### 4.2 Flow fee thu trên gross từng request (chi tiết khi code, không phải vấn đề lớn)

Chỉ áp dụng cho **flow fee** (entry/exit/early-exit) — phí tính theo % số tiền *một lệnh*. **Stock fee (management/performance) miễn nhiễm**: chúng tính trên AUM đang giữ, mà matching không đổi `totalAssets` → mint-share dilution không liên quan gì tới net/gross.

Với flow fee: nếu thu trên *net* (sau matching) thì phần được match né được phí (cặp deposit+redeem cùng epoch = rút qua vault free). Cách đúng: trừ phí trên **gross từng request, trước matching** — matching khi đó chỉ tiết kiệm chi phí swap/Pruv, không né được phí. Một dòng cần nhớ lúc implement, không phải điểm bán hàng.

---

## 5. Thu phí on-chain bằng cách nào (lớp kỹ thuật)

**Stock fee = mint fee shares (pha loãng).** Thu phí = chuyển một phần quyền sở hữu sang treasury, không cần di chuyển USDC. Ví dụ epoch 1 tháng, mgmt 1.5%/năm trên vault 1,000,000:

```
                  TRƯỚC                 SAU
  totalAssets     1,000,000 USDC        1,000,000 USDC   (không đổi)
  totalSupply     1,000,000 shares      1,001,251.6      (tăng)
  giá/share       1.00                  0.99875          (giảm)
  Holder          $1,000,000            $998,750         (−1,250)
  Treasury        $0                    $1,250           (+1,250 = đúng phí kỳ)
```

- **Vì sao mint shares, không trả USDC?** Vault không có sẵn cash (80–90% nằm illiquid); mint shares tốn 0 thanh khoản và giữ treasury "cùng thuyền" với holder.
- **Vì sao crystallize mỗi epoch?** Khớp nhịp `processEpoch`, gas thấp (1 lần/epoch), minh bạch (event mỗi kỳ). Cùng pattern Lagoon/Centrifuge.
- **Flow fee:** dùng `ERC4626Fees.feeOnTotal` của OpenZeppelin (đã audit, làm tròn về phía vault) — request luôn là gross nên dùng `feeOnTotal`.
- **Lưu ý invariant:** fee mint shares **phá** bất biến hiện tại *"supply chỉ đổi qua sub/redeem"* → phải bổ sung "fee mint" là nguồn hợp lệ thứ ba. Đây là thay đổi khái niệm, không phải bug.

---

## 6. Ba phương án (chưa chốt)


|                  | **A — Spread-only** | **B — Evergreen full**                   | **C — Lean**                            |
| ---------------- | ------------------- | ---------------------------------------- | --------------------------------------- |
| Gồm              | giữ chênh yield ẩn  | mgmt 1.5% + perf 10%/HWM + early-exit 2% | mgmt 1.5% + exit 50 bps                 |
| Fee on-chain     | (không)             | F10 + F11 + F5                           | F10 + F4                                |
| Effort POC       | ~0                  | +1.5–2 ngày                              | +0.5–1 ngày                             |
| Minh bạch        | ▁ thấp              | ████ cao                                 | ███ cao                                 |
| Rủi ro admin-NAV | ████ cao            | ███ (cần guardrail)                      | ██ thấp                                 |
| Giống TradFi     | ▁                   | ████                                     | ███                                     |
| Demo cơ chế      | ▁                   | ████                                     | ███                                     |


- **A** đơn giản nhất nhưng đục mờ, dồn hết trust vào `setPrice`, không demo được gì on-chain.
- **B** giống quỹ thật nhất, doanh thu cao nhất, nhưng nặng và ôm rủi ro §4.1 (perf fee × NAV thủ công).
- **C** nhẹ, rủi ro thấp nhất, demo được cả **stock-fee lẫn flow-fee** — đánh đổi: thiếu performance-based.

---

## 7. Điều còn phải quyết (trước production, không chặn POC)

**Ba câu hỏi định hướng chọn phương án:**

1. POC cần chứng minh gì? Chỉ *mechanism* → giữ 0%/A. *Mechanism + tính khả thi kinh tế* → B hoặc C.
2. Production có chấp nhận NAV thủ công lâu dài? Có → perf fee cần đủ guardrails (hoặc tránh, chọn C). Không (sẽ có oracle) → B an toàn hơn nhiều.
3. Underlying (HL qua Pruv) charge chúng ta bao nhiêu? Fee của ta chồng lên fee underlying → tổng stack quyết định APY net cho retail. **Chưa có số này.**

**Câu hỏi mở:** idle-cash yield (Aave trên sub queue) thuộc user hay platform? · treasury nhận fee shares hay USDC? · tham số fee hardcode / owner-set có timelock / immutable? · pass-through chi phí underlying hiển thị tách hay gộp NAV?

---

*Mọi con số truy về `docs/fee-research.md` §3–§7. Section HTML nên giữ verdict (§1) + bảng benchmark (§2) + 2 phát hiện (§4) ở lớp đọc nhanh; đẩy §5 cơ chế và §6 phương án xuống lớp "under the hood".*