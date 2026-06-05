# 00-brief — PRD Retail Access (Source Material)

**Source:** `/Users/jesse/Downloads/PRD Retail Access (1).pdf` (8 pages)
**Imported:** 2026-06-02
**Scope chosen by user:** Implement **Alternative 1** (custody mình tự build + mix liquid/illiquid). Local POC, proof of mechanism only — không phải production product.

---

## Background

### Overview
PRD covers basic functionality marketing RWA token to retail market:
- **Subscription**: Retail users mua RWA token permissionlessly.
- **Redemption**: Retail users redeem investment back to liquid format.

### Objectives
- Market own token to retail market (không phụ thuộc web3 foundations)
- Solve early redemption issue mà không tốn own liquidity
- Hit minimum ticket size để fulfill private fund requirements

### Product Vision
Enable to market Evergreen Private Credit funds (e.g. Hamilton Lane) với minimum capital needed from us.

---

## Main Protocol — 5 States

| State | Mô tả |
|-------|-------|
| `Initialized` | Vault deployed, countdown to launchpad. All contracts disabled. |
| `Launchpad Start` | Retail investors lock USDC để meet minimum ticket size. |
| `Launchpad Fail` | Không đạt minimum sau time limit. Refund all locked stablecoin. |
| `Epoch-based` | Normal operating phase. Subscription + Redemption queues. |
| `Wind-down` | Decommission vault. Refund pending → liquidate → settle redemptions. |

### Admin Init Inputs
- **Fixed**: vault token name, symbol, stablecoin used, launchpad period, minimum amount needed
- **Editable**: asset contract address, default % per asset

---

## Phase Details

### Initialized
Vault deployed nhưng launchpad chưa bắt đầu. Mọi transaction disabled.

### Launchpad Start
- Retail lock stablecoin → nhận **receipt (không phải token)**
- Nếu đủ minimum trong time limit → success → platform takes stablecoin → bridges to Pruv → subscribes to RWA token → bridges wrapped RWA back to original network → mints + distributes vault token to retail
- Nếu không đủ → fail → pool unlocked for refund

### Launchpad Fail
All deposits disabled. Users claim refund.

### Epoch-based — Subscription

ERC-7540 queued/pooled subscription. 2 lý do:
1. Wait for subscription window of underlying asset
2. Aggregate small subs để fulfill minimum subsequent subscription

**Alternative 1 (CHỌN):**
1. User input amount, click Subscribe
2. Sign tx send stable to subscription queue (ERC-7540)
3. Before window open → có thể withdraw (ERC-7887)
4. Window open → smart contract takes stablecoin in queue, subscribes Pruv token
5. Asset locked in **custody (self-built)**
6. Vault mints + distributes vault token

**Alternative 2 (KHÔNG chọn):**
Tương tự nhưng lock asset vào **Balancer pool**, Balancer mint ETF token, vault lock ETF token. `totalAssets()` đọc giá trị ETF token.

### Asset Combination

| Main Illiquid (80-90%) | Buffer Liquid (10-20%) |
|-----------------------|------------------------|
| Higher yield (~10% APY) | Lower yield (~4% APY) |
| Evergreen fund, period sub/redemption window | Swap-able with stablecoin anytime |

Example: 80/20 mix → blended APY ~8.8%

### Epoch-based — Redemption

ERC-7540 queue. Upon epoch, redemption process 3 layers:
1. **Matching** — net subscription vs redemption queue (xem section dưới)
2. **Liquid redemption** — nếu còn liquidity buffer trong custody → swap thành stablecoin
3. **Illiquid redemption** — buffer hết → redeem illiquid asset → pay redemption

---

## Auxiliary Systems

### Matching System
End of epoch, net stablecoin in sub queue vs vault token value in redemption queue. Chỉ process delta.

**Case 1 — Sub > Redemption**:
10,000 USDC sub queue + 4,000 USDC worth redemption queue.
→ 4,000 USDC swap 4,000 USDC worth vault tokens (matched internally).
→ Remaining 6,000 USDC subscribe underlying asset.

**Case 2 — Redemption > Sub**:
4,000 USDC sub + 10,000 USDC worth redemption.
→ 4,000 USDC swap 4,000 USDC worth vault tokens.
→ Remaining 6,000 USDC worth vault tokens burned, exchanged with 6,000 USDC from swapping liquid asset in custody. Nếu không đủ → bán illiquid.

### Reinvest Stablecoin in Sub Queue
Idle stablecoin in queue → deposit Aave để earn yield → before epoch swap back to USDC → use to subscribe.

---

## Wind-down
Admin trigger anytime trong epoch-based.
- Disable new subscription requests
- Refund pending subscription queue
- Exchange all liquid assets → stablecoin
- Stablecoin pays redemption queue
- Per redemption window, empty illiquid assets and redeem
- Vault left with stablecoin → users redeem vault token for stablecoin trong time limit

---

## Required to Work (Open Questions in PRD)

### Curve Swap
- Check pool formula
- Whether value can read from Pruv Finance (from vault)
- Check which type of swap is best suited (pros & cons)

---

## User's Implementation Intent (2026-06-02)

> "chúng ta sẽ implement theo alt-1 (the one still using custody, and mix of liquid and illiquid). Đây sẽ là 1 bản local implement để chứng minh tính khả thi của phương pháp, mục tiêu không phải là làm được sản phẩm, mà show ra được cơ chế cơ bản, vì vậy chúng ta cần discuss với nhau kỹ xem cách tiếp cận là gì."

**Key constraints:**
- LOCAL only (no production deployment)
- Goal: prove feasibility of mechanism
- NOT a product
- Must discuss approach carefully before implementing
