# REX Primary — Production Plan (task breakdown)

> **Nguồn sự thật: `PRD REX Primary.pdf`** (Overview / Objectives / States / Launchpad / Epoch-based
> Group Subscription & Redemption / Matching System / Fees / Wind-down). POC trong repo này
> (`src/Vault.sol`, `src/Custody.sol`, `src/otc/*`) chỉ là **tham chiếu pattern** (matching pro-rata,
> queue cap 100, ERC-7887 cancel) — **không** phải nguồn thiết kế. Production **khác POC ở nền tảng**:
> đa chain, oracle NAV, không custody, retail cầm wRWA.

## 0. Kiến trúc chốt (theo PRD + xác nhận của David Kurniawan)

- **Home chain = Sepolia** (EVM bất kỳ, tạm Sepolia). Retail tương tác ở đây bằng **USDC**.
- **Pruv chain = PRUV Testnet** — `RWAToken` (ERC-4626), `RWAConversion` (NAV), `RWAFee`, `Whitelist`.
- **Bridge = Hyperlane Warp Route**, 2 token, **2 chiều**: **USDC** (Sepolia↔PRUV) và **wRWA** (PRUV↔Sepolia).
- **KHÔNG custody.** Retail subscribe → nhận **wRWA (synthetic bridged)** và **giữ trực tiếp**.
- **NAV qua Oracle** (không nhập tay): đọc `RWAConversion.value()` ở PRUV → publish lên Sepolia.
- **Retail KHÔNG KYC.** Chỉ **`PruvExecutor`** trên PRUV là địa chỉ được cấp Whitelist (token ID 1).

### Component
| Nơi | Contract/Service | Vai trò |
|---|---|---|
| Sepolia | `REXPrimary` | State machine 5 trạng thái, sub/redeem queue, receipt (7540/7887), matching, epoch async (initiate/settle), phân phối |
| Sepolia | `NavOracleConsumer` | Lưu NAV mới nhất từ PRUV + guard staleness |
| Sepolia | `FeeModule` | Phí cancel + phí redeem (PRD Fees) |
| Sepolia | Bridge adapters | Gửi/nhận USDC & wRWA qua Hyperlane |
| PRUV | `PruvExecutor` | Địa chỉ whitelisted; nhận USDC → `RWAToken.deposit` → bridge wRWA về; nhận wRWA → `redeem` → bridge USDC về |
| Off-chain | Epoch Keeper | initiate epoch → theo dõi bridge → settle |
| Off-chain | NAV Oracle Relay | đọc `value()` PRUV → ký/đẩy lên `NavOracleConsumer` |
| Off-chain | Bridge Monitor | theo dõi relay, cảnh báo message kẹt |
| Backend | Indexer + API | queue, request, epoch, cross-chain status cho UI |
| Frontend | dApp | subscribe/redeem/claim, hiển thị NAV/preview/fee/in-flight |

### Luồng (bám PRD)
- **Subscribe** (PRD §Group Subscription 1–8): lock USDC → receipt → được cancel trước window (7887)
  → epoch: **match** sub↔redeem → phần USDC dư **bridge sang Pruv → deposit → wRWA bridge về →
  distribute wRWA** theo receipt.
- **Redeem** (PRD §Group Redemption): lock wRWA → receipt → epoch: match → phần wRWA dư **bridge sang
  Pruv → redeem → USDC bridge về → distribute USDC** theo receipt.
- **Matching** (PRD §Matching System): net USDC-sub vs wRWA-redeem (định giá theo **NAV oracle**); phần
  match P2P: wRWA của redeemer → subscriber, USDC của subscriber → redeemer (không round-trip Pruv);
  chỉ **delta** chạm Pruv. Ví dụ 10k/4k của PRD là acceptance số học bắt buộc.
- **Launchpad** (PRD §Launchpad): gom USDC đạt min ticket → thành công thì subscribe Pruv, phân phối
  wRWA theo receipt; thất bại → refund USDC 100%.
- **Wind-down** (PRD §Wind-down): khoá sub mới; refund sub pending; redeem toàn bộ wRWA ở Pruv theo
  window; phân phối USDC; đóng.
- **Fees** (PRD §Fees): phí **cancel subscription** + phí **redemption** ở tầng REX. Pruv còn thu
  entry/exit riêng qua `RWAFee` khi Executor deposit/redeem.
  **Best-practice đề xuất (theo PRD + phân bổ chi phí công bằng):**
  - Hai loại phí PRD (cancel + redeem) là **phí sản phẩm của REX**, bps cấu hình được, recipient = treasury REX.
  - Phí Pruv (entry/exit) là **chi phí của chân Pruv** → chỉ tính cho **phần delta thực sự round-trip
    Pruv**; phần **match P2P không chạm Pruv nên không gánh phí Pruv** (thưởng cho việc netting — đúng
    tinh thần Matching System của PRD). Phí Pruv trừ thẳng vào tài sản nhận về của nhóm delta, minh
    bạch trên UI (`previewDeposit/Redeem` đã phản ánh).
  - Không phí ẩn: mọi phí hiển thị trước khi user ký (preview).

---

## PHASE 0 — Research & Validation nền tảng (ra docs + test script chạy được)

**Phân công:** Core (2 người).

- **R1. Bóc interface Pruv thật**
  *Mô tả:* đọc `RWAToken`/`RWAConversion`/`RWAFee`/`Whitelist` ([pruv-docs](https://github.com/d3labs-io/pruv-docs)); xác định decimals, cap, min ticket, subscription window (nếu có ở tầng nghiệp vụ).
  *AC:* doc `docs/research/pruv-interface.md` + bảng hàm; kết luận deposit/redeem đồng bộ.
- **R2. Test deposit/redeem Pruv trên PRUV Testnet**
  *Mô tả:* chạy script pruv-docs với ví whitelisted.
  *AC:* script log tx: deposit→share, redeem→asset; `previewDeposit/Redeem` khớp on-chain.
- **R3. Quy trình cấp Whitelist cho `PruvExecutor`**
  *AC:* doc quy trình + 1 địa chỉ test đã được cấp token ID 1 thành công.
- **R4. NAV (`RWAConversion`) — nguồn & cadence cho oracle**
  *AC:* doc: ai `setValue`, tần suất, độ trễ chấp nhận, ngưỡng staleness đề xuất.
- **R5. Fee Pruv (`RWAFee`) — entry/exit thực tế**
  *AC:* script đọc `feeOnRaw/feeOnTotal` live; doc mức bps + recipient.
- **R6. Hyperlane Warp Route — cơ chế + test round-trip**
  *Mô tả:* hiểu collateral↔synthetic, `transferRemote`, quote fee, relay latency, ISM/security, failure modes.
  *AC:* script bridge round-trip **USDC** thành công (testnet); đo latency; doc mode lỗi + cách recover.
- **R7. Warp Route cho wRWA sang Sepolia — reuse hay tự deploy?**
  *Mô tả:* route sẵn có là PRUV↔Kaia; ta cần PRUV↔Sepolia. Kiểm tra khả năng enroll Sepolia / tự deploy synthetic.
  *AC:* doc kết luận + (nếu tự deploy) danh sách contract cần deploy.
- **R8. Oracle cross-chain — chọn cơ chế (đã có đề xuất best-practice)**
  *Mô tả:* so sánh (a) relay off-chain tự ký + `setNav`, (b) **Hyperlane interchain message như oracle**,
  (c) Chainlink/CCIP.
  **Đề xuất mặc định = (b):** ta *đã* tích hợp Hyperlane cho bridge → dùng luôn Hyperlane messaging tải
  NAV (một `NavReporter` trên PRUV đọc `RWAConversion.value()` và dispatch sang `NavOracleConsumer` trên
  Sepolia). Lý do best-practice: **một mô hình bảo mật duy nhất** (cùng ISM đã vet cho bridge), **không
  thêm nhà cung cấp trust thứ hai** (Chainlink), độ trễ bám theo relay đã đo ở R6. Bổ sung phòng thủ:
  **staleness guard** + **sanity bound** (từ chối cập nhật NAV lệch quá X% so với giá trị trước — chống
  message giả/lỗi).
  *AC:* ADR chốt cơ chế + threat note (ai được đẩy NAV, chống giả mạo/replay, giới hạn biến động).
- **R9. Compliance nhẹ (retail no-KYC)**
  *Mô tả:* xác nhận mô hình "Executor là holder KYC duy nhất, retail permissionless qua wRWA" ổn về vận hành.
  *AC:* doc 1 trang; cờ đỏ pháp lý (nếu có) gửi ngoài eng.
- **R10. Decimal reconciliation**
  *AC:* bảng decimals thật (RWA, USDC, NAV `value()` 18-dec) verify bằng `decimals()` on-chain.

## PHASE 1 — Architecture & Design (diagram trước khi build → ra docs)

**Phân công:** Core dẫn dắt; FE review để nắm luồng.

- **D1. Sequence diagram luồng tổng quát (LÀM ĐẦU TIÊN)** ⭐
  *Mô tả:* vẽ sequence async cross-chain cho: subscribe, redeem, matching/epoch, launchpad, wind-down, **bridge-fail/retry**, **oracle update**.
  *AC:* `docs/02-architecture/diagrams/rex-*.mmd` + `.png`; cover happy path + nhánh lỗi bridge/oracle; review OK trước khi code.
- **D2. Architecture diagram đa chain** — Sepolia ↔ Hyperlane ↔ PRUV, mọi component + ranh giới trust. *AC:* diagram + mô tả.
- **D3. State machine mở rộng** — thêm **in-flight/settling** (epoch không atomic), chống double-process, timeout. *AC:* diagram state + bảng transition + bất biến giữ trong in-flight.
- **D4. Cross-chain message spec** — message subscribe-delta/redeem-delta/return-wRWA/return-USDC; idempotency, ordering, replay-protection, versioning. *AC:* spec + cơ chế idempotent.
- **D5. Production spec tổng thể** — viết `docs/spec/rex-primary.md` bám PRD; định nghĩa receipt (7540/7887), matching math theo NAV, phân phối. *AC:* spec self-contained; số ví dụ 10k/4k khớp PRD.

## PHASE 2 — Contracts home chain (Sepolia)

**Phân công:** Core.

- **HC1. `REXPrimary` core: state machine 5 trạng thái + queue** *AC:* Initialized→Launchpad→(Fail|Epoch)→Wind-down; sub/redeem queue; unit test.
- **HC2. Receipt & cancel (ERC-7540/7887)** *AC:* requestDeposit/Redeem cấp receipt; cancel trước window hoàn tiền/tài sản; phí cancel gọi FeeModule.
- **HC3. Matching engine (net theo NAV oracle)** *AC:* match P2P wRWA↔USDC pro-rata; số 10k/4k khớp PRD; matching chạy trước net-delta.
- **HC4. Epoch async: `initiateEpoch` / `settleEpoch`** *AC:* initiate tính delta + gửi bridge; settle khi wRWA/USDC về + phân phối; chống double-settle; bất biến `assets ≥ obligations` suốt in-flight.
- **HC5. Distribution wRWA/USDC theo receipt** *AC:* subscriber nhận wRWA đúng tỷ lệ receipt; redeemer nhận USDC đúng NAV.
- **HC6. Bridge adapters (USDC out/in, wRWA out/in)** qua `IBridge`. *AC:* round-trip mock bridge; xử lý phí bridge; idempotent theo message id.
- **HC7. Launchpad** — gom USDC min ticket, thành công subscribe & phân phối wRWA, thất bại refund. *AC:* 2 nhánh test.
- **HC8. Wind-down** — khoá sub, refund pending, redeem toàn bộ wRWA ở Pruv, phân phối USDC. *AC:* không user nào kẹt tiền.
- **HC9. FeeModule (cancel + redeem)** — PRD Fees. *AC:* phí đúng; recipient nhận đủ; admin cấu hình.
- **HC10. Access control + pausable + reentrancy guard** *AC:* admin-gated đúng; nonReentrant ở claim/refund/settle.

## PHASE 3 — Contract Pruv chain (PRUV)

**Phân công:** Core.

- **PC1. `PruvExecutor`** — nhận USDC bridged → `RWAToken.deposit` → bridge wRWA về; nhận wRWA bridged → `RWAToken.redeem` → bridge USDC về. *AC:* test deposit/redeem qua executor trên testnet; chỉ nhận lệnh bridge hợp lệ.
- **PC2. Whitelist holder + guard** — executor giữ token ID 1; xử lý mất whitelist. *AC:* revert đúng lỗi khi chưa/không còn whitelisted.
- **PC3. Recovery/sweep khi bridge lỗi** *AC:* admin recover fund kẹt; test relay-fail.
- **PC4. Hạch toán fee Pruv (`RWAFee`)** — trừ entry/exit khi deposit/redeem. *AC:* số về khớp `previewDeposit/Redeem` thật.

## PHASE 4 — Bridge integration (Hyperlane)

**Phân công:** Core.

- **BR1. Warp route USDC Sepolia↔PRUV** (config/deploy + enroll 2 chiều). *AC:* round-trip USDC testnet.
- **BR2. Warp route wRWA PRUV↔Sepolia** (reuse/deploy theo R7). *AC:* round-trip wRWA testnet; synthetic wRWA mint đúng trên Sepolia.
- **BR3. Fee quoting + relay monitoring** *AC:* quote phí trước gửi; theo dõi delivery theo message id.
- **BR4. Failure/timeout/retry + stuck recovery** *AC:* message fail → retry/recover; không double-mint/double-pay (test).

## PHASE 5 — Oracle NAV

**Phân công:** Core.

- **OR1. `NavOracleConsumer` (Sepolia)** — lưu NAV + timestamp + staleness guard. *AC:* `nav()` trả value mới nhất; revert `StalePrice` khi quá ngưỡng.
- **OR2. NAV relay qua Hyperlane (best-practice mặc định, xem R8)** — `NavReporter` (PRUV) đọc
  `RWAConversion.value()` → dispatch interchain message → `NavOracleConsumer.setNav` (Sepolia) chỉ nhận
  từ sender/domain hợp lệ. *AC:* NAV Sepolia khớp PRUV trong ngưỡng trễ; chống replay; sanity-bound chặn cập nhật lệch bất thường.
- **OR3. Tích hợp NAV vào matching/settle** *AC:* matching & định giá redeem dùng NAV oracle; test S7-tương đương (NAV +10% → redeemer nhận nhiều hơn 10%).

## PHASE 6 — Off-chain orchestration / keeper

**Phân công:** Core.

- **OC1. Epoch Keeper** — initiate → theo dõi bridge delivery → trigger settle. *AC:* chạy full epoch async testnet end-to-end.
- **OC2. Bridge/relay Monitor + alerting** *AC:* phát hiện message trễ/kẹt → cảnh báo.
- **OC3. Ops config & keys management** *AC:* quản lý key relay/keeper an toàn (không hardcode); rotate được.

## PHASE 7 — Backend / Indexer / API

**Phân công:** FE (chính) + Core hỗ trợ event schema.

- **BE1. Indexer** — subscribe/redeem request, receipt, epoch state, cross-chain status (queued/in-flight/claimable). *AC:* API trả đúng trạng thái mỗi request.
- **BE2. API cho UI** — NAV, previewDeposit/Redeem, phí, lịch sử, launchpad status. *AC:* endpoint khớp on-chain.

## PHASE 8 — Frontend / dApp

**Phân công:** FE.

- **FE1. Subscribe/Redeem/Claim** + hiển thị NAV/preview/fee/**trạng thái in-flight** (đang bridge). *AC:* chạy full flow testnet qua ví.
- **FE2. Launchpad UI** — đếm ngược, min ticket, refund khi fail. *AC:* hiển thị đúng state.
- **FE3. Wind-down UI + lịch sử giao dịch** *AC:* user thấy nghĩa vụ đang settle & claim được.

## PHASE 9 — Testing & QA

**Phân công:** cả team.

- **T1. Unit tests contracts (Sepolia + PRUV)** *AC:* coverage mục tiêu; forge test xanh.
- **T2. Integration cross-chain (mock bridge + mock Pruv local)** *AC:* subscribe/redeem async end-to-end; matching 10k/4k đúng số.
- **T3. Testnet E2E script (point 3)** — retail nạp USDC Sepolia → nhận wRWA (qua bridge+Pruv thật) → redeem → nhận USDC. *AC:* script chạy được, log toàn bộ tx 2 chain.
- **T4. Invariant/fuzz** — value conservation, no stranded fund cross-chain, no double-distribute. *AC:* fuzz 0 vi phạm.

## PHASE 10 — Security & Audit

**Phân công:** Core + auditor ngoài.

- **S1. Threat model cross-chain** — bridge trust, replay, reorg, NAV oracle manipulation, message ordering. *AC:* doc threat model + mitigation.
- **S2. Static analysis + internal review** *AC:* slither sạch; checklist review 2 chain.
- **S3. External audit** *AC:* report + fix findings.

## PHASE 11 — Deployment & Ops

**Phân công:** Core.

- **DP1. Deploy scripts đa chain + verify** *AC:* deploy reproducible; verify explorer 2 chain.
- **DP2. Admin key / multisig / upgradeability** *AC:* mô hình owner rõ; multisig cho hành động nhạy cảm.
- **DP3. Monitoring/dashboards** — epoch, bridge, NAV staleness, TVL, fund in-flight. *AC:* dashboard + alert.
- **DP4. Runbooks** — bridge kẹt, NAV stale, wind-down, cấp/thu whitelist Executor. *AC:* runbook incident.

---

## Sắp xếp cho team 3 người (1 FE + 2 Core)

```
Tuần đầu:  R1..R10 (Core)  ||  FE học PRD + wireframe (FE)
Rồi:       D1 ⭐ → D2..D5 (Core dẫn, FE review)
Song song sau design:
  Core-1: HC (Sepolia contracts) + FeeModule
  Core-2: PC (Executor) + BR (bridge) + OR (oracle) + OC (keeper)
  FE:     BE indexer/API → FE dApp (dùng mock/testnet khi contract sẵn sàng)
Chốt:      T (test) chung → S (audit) → DP (deploy)
```

**Đường găng (critical path):** R6/R7 (bridge khả thi?) → D1/D3/D4 (thiết kế async) → HC4 + PC1 + BR1/BR2
(vòng subscribe async chạy được end-to-end) → T3 testnet E2E. Ưu tiên chứng minh **1 vòng subscribe
async xuyên 2 chain** sớm nhất (walking skeleton) rồi mới bọc launchpad/wind-down/fee/UI.
