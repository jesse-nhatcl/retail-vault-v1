# Alt-1 + 1a — Open Questions & Unresolved Points · Câu hỏi & điểm chưa giải quyết

> Song ngữ. Gói gọn mọi thứ **chưa chốt** cho hướng OTC early-exit theo **Alt-1 + variant 1a**.
> Bilingual. A short checklist of everything **still open** for the OTC early-exit path (**Alt-1 + variant 1a**).
> Liên quan / related: `07-otc-early-exit-alt1-1a.md`, `...-breakdown.md`.

---

## A. Cần hỏi người vẽ diagram (mơ hồ trong sketch) · Ask the diagram author (sketch ambiguities)

**A1. Chiều tiền — buyer trả thẳng cho seller?**
EN: Money flow — does the buyer's USDC go straight to the seller? The sketch never states this; we assumed it.

**A2. "total 13,000 USDC" nghĩa là gì?**
EN: What does "total 13,000 USDC" mean — available buyer-side liquidity, or something else?

**A3. "redeemed for ~5.1% USDC" (1a) nghĩa là gì?**
EN: What does "redeemed for ~5.1% USDC" / the "short exchange.net" note actually mean?

**A4. Phần vToken ế có quay về seller không?**
EN: Does the unsold vToken return to the seller, or stay queued? The sketch only shows "queued for redemption".

---

## B. Quyết định thiết kế chưa chốt · Design decisions not yet locked

**B1. Buyer phải redeem hay được giữ share?**
EN: Must the buyer redeem, or may they just hold the shares as a vault investor? (BidVault auto-queue vs hold.)

**B2. Đọc NAV lúc nào — đặt lệnh hay lúc settle?**
EN: When is NAV read — at bid time or at settle time? (Fixes the arb window.)

**B3. Escrow giữ ở đâu trước settle — OTCMarket hay BidVault?**
EN: Where is escrow held before settle — in OTCMarket or in BidVault?

**B4. ROuter tin cậy tới đâu — settle on-chain validate hết, hay cần chữ ký (EIP-712)?**
EN: How much do we trust ROuter — fully on-chain validated settle, or signed orders (EIP-712)?

**B5. Hủy lệnh & wind-down: hủy được tới khi nào, đóng OTC ra sao khi WindDown?**
EN: Cancel & wind-down semantics: cancel until when, and how does OTC close on WindDown?

**B6. Có thu phí trên discount không? (POC = 0%)**
EN: Any fee on the discount? (0% for the POC; leave one hook.)

---

## C. Giả định rủi ro cần kiểm chứng · Risky assumptions to validate

**C1. (Nặng nhất) Share có được tự do chuyển nhượng không?**
EN: (Biggest) Are shares freely transferable? Real RWA often has KYC / accredited / lockup limits — could kill the whole idea.

**C2. Có thật sự có người mua ở discount không?**
EN: Does real buyer demand at a discount actually exist? No buyers → OTC adds nothing, everything falls to the queue.

**C3. NAV có đáng tin không? (Alt-1 set tay, không enforce)**
EN: Is NAV trustworthy? In Alt-1 it is admin-set and unenforced — a stale/gamed NAV makes the discount meaningless.

**C4. Fallback queue có luôn trả đủ NAV không?**
EN: Does the fallback queue always pay full NAV? Pruv partial-fill rollover is currently deferred — not guaranteed.

**C5. Có nhiều người bán cùng lúc thì khớp thế nào?**
EN: How does matching work with multiple competing sellers? The sketch models only one seller, one lot.

---

## D. Riêng cho 1a · Specific to variant 1a

**D1. Chi phí deploy 1 ERC-4626 + 1 LP token cho MỖI bid có chấp nhận được?**
EN: Is deploying one ERC-4626 + one LP token **per bid** acceptable cost? (1a's core expense.)

**D2. LP token không fungible giữa các bid — có cản người mua thoát tiếp không?**
EN: LP tokens are non-fungible across bids — does that block buyers from reselling/exiting later?

---

### Ưu tiên xử lý trước khi code · Resolve before coding
1. **C1** transferability — nếu hỏng thì dừng. / if broken, stop.
2. **A1** chiều tiền — nền của mọi logic. / money flow — foundation of all logic.
3. **C2 / C3** cầu thật + NAV tin cậy. / real demand + trustworthy NAV.
4. **C4** fallback trả đủ NAV. / fallback pays full NAV.
