# Fee Model — Phương án (Phase I)

**Project:** 2026-06-retail-access-vault
**Ngày:** 2026-06-05
**Input:** `research-raw.md` (benchmark 13 nền tảng + cơ chế on-chain)
**Trạng thái:** Chờ chọn phương án → Phase P

---

## Khung đánh giá

Mỗi phương án được chấm trên 5 tiêu chí:
1. **Khớp epoch model** — cắm vào `processEpoch` hiện tại có tự nhiên không
2. **Độ phức tạp implement** — thêm bao nhiêu effort vào POC
3. **Rủi ro manipulation** — tương tác với admin `setPrice()` (NAV thủ công)
4. **Chống fee leakage** — matching P2P có né được fee không
5. **Giá trị demo** — show được bao nhiêu cơ chế fee cho stakeholder

---

## Phương án A — "Spread-only" (không có fee tường minh)

Mô phỏng Ondo USDY / Maple: platform không charge fee nào trên user.
Doanh thu = chênh lệch giữa yield thực của underlying và yield credit vào NAV.

```
Underlying blended yield  : 8.8%/năm  (80/20 illiquid/liquid)
NAV growth admin set      : 8.0%/năm
Platform giữ lại          : 0.8%/năm  (ẩn, off-chain)
```

| Tiêu chí | Đánh giá |
|---|---|
| Khớp epoch | ✅ Hoàn hảo — chỉ là cách admin tính giá khi `setPrice()` |
| Phức tạp | ✅ Gần như zero — không thêm code |
| Manipulation | ❌ Tệ nhất — fee hoàn toàn opaque, không audit được on-chain |
| Fee leakage | ✅ Không có flow fee nên không có gì để né |
| Giá trị demo | ❌ Không show được cơ chế fee nào trong contract |

**Phù hợp khi:** muốn ship POC nhanh nhất, chấp nhận fee là "chuyện off-chain".

---

## Phương án B — "Evergreen standard" (trọn bộ TradFi)

Mô phỏng đúng chuẩn evergreen private credit fund (asset class của underlying):

| Fee | Mức tham chiếu | Cơ chế on-chain |
|---|---|---|
| Management fee | 1.5%/năm trên NAV | Crystallize mỗi epoch — mint fee shares cho treasury trong `processEpoch` |
| Performance fee | 10% phần NAV vượt high-water mark | HWM per-share on-chain, crystallize tại epoch |
| Early-exit fee | 2% nếu redeem trong vòng N epochs từ lúc deposit | Track tuổi holding per-user, trừ vào proceeds tại settlement |
| Entry/exit fee | 0 | — |

| Tiêu chí | Đánh giá |
|---|---|
| Khớp epoch | ✅ Tốt — crystallization per-epoch là pattern chuẩn (Lagoon/Centrifuge) |
| Phức tạp | ❌ Cao nhất — HWM + per-user holding age + fee shares ≈ +1.5–2 ngày POC |
| Manipulation | ⚠️ Perf fee + admin NAV = hố đã biết; cần guardrails (deviation bounds, fee caps, lower-only rates) |
| Fee leakage | ✅ Early-exit fee charge trên gross per-request |
| Giá trị demo | ✅ Cao nhất — show đủ cả 3 loại fee như fund thật |

**Phù hợp khi:** muốn POC chứng minh được cả economic model, không chỉ mechanism.

---

## Phương án C — "Flow + mgmt lean" (2 cơ chế đại diện)

Giữ đúng 2 loại fee đại diện cho 2 họ cơ chế, bỏ phần rủi ro nhất:

| Fee | Mức tham chiếu | Cơ chế on-chain |
|---|---|---|
| Management fee | 1.5%/năm trên NAV | Crystallize mỗi epoch — mint fee shares cho treasury trong `processEpoch` (share dilution) |
| Exit fee | 50 bps trên gross redemption | Trừ tại settlement, **trên từng request trước khi matching** → chặn fee leakage |
| Performance fee | ❌ Không có | Né hố HWM + admin NAV |
| Entry fee | 0 | Theo đa số benchmark (chỉ OpenEden/Backed charge entry) |

| Tiêu chí | Đánh giá |
|---|---|
| Khớp epoch | ✅ Cả 2 fee đều nằm gọn trong `processEpoch` |
| Phức tạp | ✅ Thấp — ≈ +0.5–1 ngày POC (không HWM, không tracking tuổi holding) |
| Manipulation | ✅ Mgmt fee tỉ lệ thuận NAV nhưng không có cliff như perf fee — risk thấp |
| Fee leakage | ✅ Exit fee charge gross per-request, matching chỉ tiết kiệm swap cost |
| Giá trị demo | ⚠️ Show 2/3 họ cơ chế (stock-based + flow-based, thiếu performance-based) |

**Phù hợp khi:** muốn POC show cơ chế fee thật trong contract nhưng giữ scope gọn.

---

## So sánh nhanh

| | A — Spread | B — Evergreen full | C — Lean |
|---|---|---|---|
| Effort thêm | ~0 | +1.5–2 ngày | +0.5–1 ngày |
| Fee on-chain | Không | Mgmt + Perf + Early-exit | Mgmt + Exit |
| Manipulation risk | Cao (opaque) | Trung bình (cần guardrails) | Thấp |
| Giống thực tế asset class | Thấp | Cao nhất | Trung bình |
| Trả lời Q6 dứt điểm | Một phần | ✅ | ✅ |

## Khuyến nghị

**C cho POC code, B cho thiết kế production** — report cuối sẽ trình bày cả 3, khuyến nghị fee structure production theo B (đúng chuẩn evergreen, có guardrails chống NAV manipulation), và chỉ rõ POC chỉ cần implement subset C để chứng minh cơ chế.

Lý do: mục tiêu POC là *proof of mechanism* — C đủ chứng minh cả hai họ cơ chế fee (accrual theo thời gian + fee theo flow, kèm xử lý fee leakage qua matching vốn là điểm độc đáo nhất của model này). Perf fee + HWM là cơ chế đã được chứng minh ở nơi khác (Lagoon), không cần re-prove, trong khi nó kéo theo guardrail phức tạp nhất.
