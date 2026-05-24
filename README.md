# 🎰 Slot Machine MCP Server

A **provably fair** on-chain slot machine exposed via [MCP](https://modelcontextprotocol.io/) (Model Context Protocol) on the [Internet Computer](https://internetcomputer.org/). Every spin uses ICP's native `raw_rand()` — cryptographic randomness from subnet consensus that no single node can predict or influence.

**MCP URL:** `https://xgjwt-hyaaa-aaaaj-a6quq-cai.icp0.io/mcp`

## Tools

| Tool | Auth | Description |
|------|------|-------------|
| `spin` | ✅ | Spin the 3-reel slot machine (bet 1–100 credits) |
| `get_balance` | ✅ | Check your credit balance and lifetime stats |
| `get_spin_history` | ✅ | Browse your past spins with results and payouts |
| `claim_faucet` | ✅ | Get 100 free credits (once per 24 hours) |
| `get_machine_stats` | 🌐 | Global stats, payout table, and symbol weights |
| `verify_spin` | 🌐 | Re-derive any spin's outcome from its seed |

## How It Works

### 3-Reel Symbols (weighted)
🍒 Cherry (25%) · 🍋 Lemon (25%) · 🔔 Bell (20%) · ⭐ Star (15%) · 💎 Diamond (10%) · 🎰 Seven (5%)

### Payout Table

| Combo | Multiplier |
|-------|-----------|
| 🎰🎰🎰 Three Sevens | **100x** JACKPOT! |
| 💎💎💎 Three Diamonds | **50x** |
| ⭐⭐⭐ Three Stars | **25x** |
| 🔔🔔🔔 Three Bells | **10x** |
| 🍋🍋🍋 Three Lemons | **5x** |
| 🍒🍒🍒 Three Cherries | **3x** |
| Any Pair | **1x** (push) |
| No Match | **0x** (loss) |

### Provably Fair

1. Each spin calls ICP's `raw_rand()` — 32 bytes of threshold BLS randomness from subnet consensus
2. The random bytes are mapped to reel symbols using a fixed, public algorithm:
   - 4 bytes per reel → big-endian Nat32 → mod 100 → weighted symbol lookup
3. Every spin's seed, outcome, and payout are stored on-chain immutably
4. Use `verify_spin` to re-derive any outcome from its seed

## Development

```bash
npm install
mops install --lock ignore --no-toolchain
icp build slot_machine
npm test  # 33/33 tests pass
```

## Deployment

Deployed on ICP mainnet via [ICForge](https://icforge.dev). Every push to `main` triggers an automatic build and upgrade.

- **Canister ID:** `xgjwt-hyaaa-aaaaj-a6quq-cai`
- **Namespace:** `io.github.jneums.slot-machine`

## License

MIT
