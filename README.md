# Stela — P2P Inscriptions Protocol on StarkNet

> Named after ancient Egyptian stone slabs used to publicly record inscriptions and decrees.

Stela is a trustless peer-to-peer lending and OTC swap protocol. Borrowers create inscriptions specifying collateral, debt, interest, and duration. Any counterparty can fill the inscription — collateral locks into a token-bound account, debt transfers to the borrower, and a repayment timer begins.

## Features

- **P2P Lending** — No liquidity pools, no oracles. Direct borrower-lender inscriptions.
- **OTC Swaps** — Set duration to 0 for instant trustless asset exchanges.
- **Multi-Asset** — Mix ERC-20, ERC-721, ERC-1155, and ERC-4626 in a single inscription.
- **Multi-Lender** — Inscriptions can be partially filled by multiple lenders via ERC-1155 shares.
- **Token-Bound Collateral** — Locked assets sit in a TBA owned by the borrower's NFT. The borrower retains proof of control (governance voting, airdrop claiming) but cannot transfer assets out.
- **Transferable Positions** — Both borrower NFTs and lender shares are transferable, enabling secondary markets for debt positions.

## How It Works

```
1. Create   — Borrower posts an inscription (collateral, debt, interest, duration)
2. Sign     — Lender fills the inscription (full or partial)
3. Repay    — Borrower repays principal + interest before the deadline
4. Redeem   — Lender burns shares to claim repaid assets
   — OR —
4. Liquidate — If unpaid, anyone triggers liquidation; lender claims collateral
```

## Build & Test

Requires [Scarb](https://docs.swmansion.com/scarb/download.html) and [StarkNet Foundry](https://foundry-rs.github.io/starknet-foundry/getting-started/installation.html).

```bash
scarb build          # Compile contracts
snforge test         # Run all tests (76 tests)
```

## Project Structure

```
src/
├── stela.cairo              # Core protocol contract
├── locker_account.cairo     # Token-bound account for collateral locking
├── errors.cairo             # Error constants
├── types/
│   ├── asset.cairo          # Asset struct & AssetType enum
│   └── inscription.cairo      # Inscription structs
├── interfaces/
│   ├── istela.cairo         # Protocol interface
│   ├── ilocker.cairo        # Locker interface
│   ├── iregistry.cairo      # SNIP-14 registry interface
│   └── ierc721_mintable.cairo
└── utils/
    └── share_math.cairo     # Share conversion math (ERC-4626 style)

tests/
├── test_create_inscription.cairo
├── test_sign_inscription.cairo
├── test_repay.cairo
├── test_liquidate.cairo
├── test_redeem.cairo
├── test_multi_lender.cairo
├── test_otc_swap.cairo
├── test_e2e.cairo           # Full lifecycle integration
├── test_security.cairo      # Security invariant tests
├── test_utils.cairo         # Test helpers & deployment
└── mocks/                   # Mock contracts
```

## Security

The protocol includes guards against:
- Reentrancy on all state-mutating functions
- Double signing, double liquidation, double repayment
- Zero-percentage griefing on multi-lender inscriptions
- NFT collateral transfer bypass via selector blocklist (snake_case + camelCase)
- Fee manipulation (capped at 100%)
- Gas griefing via unbounded asset arrays (capped at 10)

See `docs/SPEC.md` for the full specification and known limitations.

## Dependencies

- StarkNet 2.13.1
- OpenZeppelin Cairo 3.0.0

## License

MIT
