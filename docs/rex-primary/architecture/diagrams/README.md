# REX Primary — Sequence Diagrams

Flow diagrams for REX Primary. Source `.mmd` and rendered `.png` are in **this folder** (dark-theme,
high-resolution). Each corresponds to a flow in [`../../specs/spec.md`](../../specs/spec.md) §7.

| Flow | Files | Spec |
|---|---|---|
| Subscribe (async cross-chain) | [`rex-01-subscribe-async.png`](rex-01-subscribe-async.png) · [.mmd](rex-01-subscribe-async.mmd) | §7.2, §7.4-7.6 |
| Redeem (async cross-chain) | [`rex-02-redeem-async.png`](rex-02-redeem-async.png) · [.mmd](rex-02-redeem-async.mmd) | §7.3 |
| Epoch matching (net-delta) | [`rex-03-epoch-matching.png`](rex-03-epoch-matching.png) · [.mmd](rex-03-epoch-matching.mmd) | §8 |
| Bridge failure + recovery | [`rex-04-bridge-failure.png`](rex-04-bridge-failure.png) · [.mmd](rex-04-bridge-failure.mmd) | §11, RS8 |
| Oracle NAV relay | [`rex-05-oracle-nav.png`](rex-05-oracle-nav.png) · [.mmd](rex-05-oracle-nav.mmd) | §9 |
| Launchpad | [`rex-06-launchpad.png`](rex-06-launchpad.png) · [.mmd](rex-06-launchpad.mmd) | §7.1 |
| Wind-down | [`rex-07-winddown.png`](rex-07-winddown.png) · [.mmd](rex-07-winddown.mmd) | §7.7 |

## Re-rendering

```bash
# from this folder
for f in rex-0*.mmd; do
  mmdc -i "$f" -o "${f%.mmd}.png" -t dark -b '#0b0e14' --scale 3 --width 1900
done
```

> The matching diagram (`rex-03`) carries an inline note that matched settlement is a raw token
> transfer (no share mint), per [`../../decisions/ADR-002-no-vault-token.md`](../../decisions/ADR-002-no-vault-token.md).
> If that ADR is ever overturned, this diagram and `../../specs/spec.md` §8 change together.
