# REX Primary — Jira Task List (Epic / Task / Sub-task)

> Danh sách để tạo issue trên Jira. Cấu trúc: **Epic → Task (2–4/epic) → Sub-task**. Nguồn: `docs/09-rex-primary-production-plan.md`.
> Project key giả định: `REX`.
>
> ⚠️ **Đang chờ David xác nhận** phần Matching (retail cầm wRWA thật, hay REX phát vault token?).
> Sub-task phụ thuộc quyết định này để **TBD** + đánh dấu 🔒. Sub-task chờ research để **TBD** + đánh dấu ⏳.
> **Legend:** ⭐ làm trước · 🔒 chờ David · ⏳ chờ research.

---

## EPIC E0 — Research & Validation nền tảng
*Xác thực Pruv + Hyperlane + oracle bằng doc & script chạy được trước khi thiết kế.*

- **T0.1 — Research Pruv Finance**
  - Sub: bóc interface `RWAToken`/`RWAConversion`/`RWAFee`/`Whitelist` + bảng hàm → `docs/research/pruv-interface.md`
  - Sub: test deposit/redeem trên PRUV Testnet (ví whitelisted), log tx, đối chiếu `previewDeposit/Redeem`
  - Sub: quy trình cấp Whitelist cho Executor (+ 1 địa chỉ test được cấp token ID 1)
  - Sub: NAV — ai `setValue`, cadence, đề xuất ngưỡng staleness
  - Sub: Fee — script đọc `feeOnRaw/feeOnTotal` live + mức bps/recipient/timing
- **T0.2 — Research Hyperlane Bridge**
  - Sub: cơ chế collateral↔synthetic, `transferRemote`, quote fee, ISM
  - Sub: script bridge USDC round-trip testnet + đo latency + failure modes/recovery
  - Sub: Warp route wRWA sang Sepolia — reuse hay deploy? (kết luận)
- **T0.3 — Research Oracle + Compliance + Decimals**
  - Sub: so sánh oracle (relay-tự-ký / Hyperlane-message / Chainlink) → ADR (mặc định: Hyperlane message) + threat note
  - Sub: compliance nhẹ — xác nhận "Executor KYC, retail no-KYC" + cờ đỏ pháp lý
  - Sub: decimal reconciliation — đọc `decimals()` on-chain, lập bảng chuẩn

## EPIC E1 — Architecture & Design (ra docs)
*Hiểu luồng async cross-chain trước khi code.*

- **T1.1 — Diagrams (sequence + architecture)** ⭐
  - Sub: sequence subscribe / redeem / matching / launchpad / wind-down
  - Sub: sequence nhánh lỗi bridge + retry, oracle NAV update
  - Sub: architecture diagram đa chain (Sepolia ↔ Hyperlane ↔ PRUV) + ranh giới trust
  - Sub: render `.mmd` → `.png`, review team
- **T1.2 — State machine + message spec**
  - Sub: state machine mở rộng (in-flight/settling) + bảng transition + chống double-process/timeout
  - Sub: cross-chain message spec (sub/redeem-delta, return-wRWA/USDC) + idempotency/ordering/replay/versioning
  - Sub: liệt kê bất biến giữ trong in-flight
- **T1.3 — Production spec + PRD reconciliation**
  - Sub: viết `docs/spec/rex-primary.md` bám PRD (receipt 7540/7887, phân phối)
  - Sub: mục "Assumptions & PRD reconciliation" (chốt §Matching)
  - Sub: 🔒 matching math (share vs token thuần) *(chờ David)*

## EPIC E2 — Contracts home chain (Sepolia)
*⚠️ Một số task phụ thuộc quyết định matching của David.*

- **T2.1 — Core: state machine + queue + receipt/cancel**
  - Sub: 5 trạng thái + transition + unit test
  - Sub: subscription queue + redemption queue
  - Sub: `requestDeposit`/`requestRedeem` cấp receipt (7540)
  - Sub: `cancelRequest` trước window + hoàn tiền/tài sản + hook phí cancel
- **T2.2 — Matching + distribution** 🔒
  - Sub: net USDC-sub vs wRWA-redeem theo NAV; test số 10k/4k khớp PRD
  - Sub: 🔒 cơ chế settle matched (chuyển token thật vs mint/burn share) *(chờ David)*
  - Sub: 🔒 phân phối cho subscriber (wRWA vs share) *(chờ David)*
  - Sub: phân phối USDC cho redeemer theo NAV
- **T2.3 — Epoch async + bridge adapters**
  - Sub: `initiateEpoch` (tính delta + gửi bridge) / `settleEpoch` (nhận về + phân phối)
  - Sub: chống double-settle + assert `assets ≥ obligations` suốt in-flight
  - Sub: `IBridge` adapter (USDC + wRWA, out/in) idempotent theo message id + xử lý phí
- **T2.4 — Launchpad + wind-down + fee + access control**
  - Sub: Launchpad (gom USDC min ticket; success→subscribe&phân phối; fail→refund 100%)
  - Sub: Wind-down (khoá sub, refund pending, redeem wRWA ở Pruv); 🔒 có ép redeem hộ wRWA retail không *(chờ David)*
  - Sub: FeeModule (cancel + redeem, bps cấu hình, recipient, preview no-hidden-fee)
  - Sub: access control + pausable + `nonReentrant` (claim/refund/settle)

## EPIC E3 — Contract Pruv chain (PruvExecutor)

- **T3.1 — Executor deposit/redeem + whitelist + fee**
  - Sub: nhận USDC bridged → `RWAToken.deposit` → bridge wRWA về
  - Sub: nhận wRWA bridged → `RWAToken.redeem` → bridge USDC về; chỉ nhận lệnh bridge hợp lệ
  - Sub: giữ Whitelist token ID 1 + revert khi mất/không whitelisted
  - Sub: hạch toán fee Pruv (`RWAFee`) — số về khớp preview thật
- **T3.2 — Recovery/sweep khi bridge lỗi**
  - Sub: admin recover fund kẹt
  - Sub: test relay-fail

## EPIC E4 — Bridge integration (Hyperlane)

- **T4.1 — Warp routes (USDC + wRWA)**
  - Sub: route USDC Sepolia↔PRUV — config/deploy + enroll 2 chiều + test round-trip
  - Sub: ⏳ route wRWA PRUV↔Sepolia — reuse/deploy theo kết luận T0.2 + test synthetic mint đúng
- **T4.2 — Fee/monitoring + failure recovery**
  - Sub: quote phí trước gửi + track delivery theo message id
  - Sub: test message fail → retry + stuck recovery (không double-mint/double-pay)

## EPIC E5 — Oracle & Off-chain Services
*Gộp Oracle NAV + Keeper + Backend/Indexer/API + Monitoring.*

- **T5.1 — Oracle NAV (contracts + relay + tích hợp)**
  - Sub: `NavOracleConsumer` (Sepolia) — lưu NAV+timestamp, staleness guard, sanity bound
  - Sub: `NavReporter` (PRUV) đọc `value()` + dispatch qua Hyperlane; consumer chỉ nhận sender/domain hợp lệ + chống replay
  - Sub: tích hợp NAV vào matching/settle; test NAV +10% → redeemer nhận nhiều hơn 10%
- **T5.2 — Epoch Keeper**
  - Sub: initiate epoch → theo dõi bridge delivery → trigger settle
  - Sub: test full epoch async testnet end-to-end
- **T5.3 — Backend: Indexer + API**
  - Sub: indexer request/receipt/epoch + cross-chain status (queued/in-flight/claimable)
  - Sub: API cho UI — NAV/preview/fee + lịch sử + launchpad status
- **T5.4 — Monitoring + ops/keys**
  - Sub: bridge/relay monitor + alerting (message trễ/kẹt)
  - Sub: quản lý key relay/keeper (không hardcode) + rotate

## EPIC E6 — Frontend / dApp

- **T6.1 — Subscribe/Redeem/Claim UI**
  - Sub: form subscribe/redeem + hiển thị NAV/preview/fee
  - Sub: trạng thái in-flight (đang bridge) + test full flow testnet
- **T6.2 — Launchpad + Wind-down UI**
  - Sub: Launchpad (đếm ngược, min ticket, refund khi fail)
  - Sub: Wind-down (nghĩa vụ đang settle) + lịch sử giao dịch + claim

## EPIC E7 — Testing & QA

- **T7.1 — Unit + integration tests**
  - Sub: unit test contracts (Sepolia + PRUV) đạt coverage mục tiêu
  - Sub: integration cross-chain (mock bridge + mock Pruv) — subscribe/redeem async, matching 10k/4k đúng số
- **T7.2 — Testnet E2E + invariant/fuzz**
  - Sub: E2E script — nạp USDC Sepolia → nhận wRWA (bridge+Pruv thật) → redeem → USDC, log tx 2 chain
  - Sub: invariant/fuzz — value conservation, no stranded fund cross-chain, no double-distribute

## EPIC E8 — Security & Audit

- **T8.1 — Threat model + review nội bộ**
  - Sub: threat model cross-chain (bridge trust/replay/reorg/NAV manipulation/ordering) + mitigation
  - Sub: static analysis (slither 2 chain) + checklist review
- **T8.2 — External audit**
  - Sub: chọn auditor + scope
  - Sub: fix findings

## EPIC E9 — Deployment & Ops

- **T9.1 — Deploy + admin/upgradeability**
  - Sub: deploy scripts Sepolia + PRUV + verify explorer
  - Sub: admin key/multisig + mô hình proxy/upgradeability
- **T9.2 — Monitoring + runbooks**
  - Sub: dashboard epoch/bridge/NAV/TVL/in-flight + alert
  - Sub: runbooks (bridge kẹt / NAV stale / wind-down / cấp-thu whitelist Executor)

---

## Tổng hợp mục TBD (cần gỡ chặn)

| Task | Sub-task TBD | Chặn bởi |
|---|---|---|
| 🔒 T1.3 | matching math (share vs token) | David — Matching |
| 🔒 T2.2 | cơ chế settle matched + phân phối subscriber | David — Matching |
| 🔒 T2.4 | wind-down có ép redeem wRWA retail không | David / D-phase |
| ⏳ T0.2 / T4.1 | reuse/deploy warp route wRWA | kết luận research T0.2 |

**Tổng:** 9 epic · 26 task · sub-task chi tiết. Mỗi epic 2–4 task.
