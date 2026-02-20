# SPEC.md — Stela Protocol Specification

## Overview

Stela is a P2P inscriptions protocol. Any user can create an inscription (order) defining:
- What they want to borrow (debt assets)
- What they'll pay as interest (interest assets)
- What they'll lock as collateral (collateral assets)
- How long they need (duration)
- When the offer expires (deadline)

Any counterparty can fill this inscription. Once filled:
1. Collateral locks into a token-bound account (TBA) owned by the borrower's NFT
2. Debt tokens transfer from lender to borrower
3. A timelock begins (duration)
4. If the borrower repays (principal + interest) before the timelock expires → collateral is released
5. If the timelock expires without repayment → anyone can liquidate, collateral goes to lender(s)

## Inscription Types

### Standard Loan (duration > 0)
Borrower locks collateral, receives debt tokens, has `duration` seconds to repay.

### OTC Swap (duration = 0)
Instant asset exchange. The lender can unlock/claim the collateral immediately upon filling.
This enables trustless OTC trades without a lending component.

## Multi-Asset Support

Inscriptions support multiple asset types in any combination:
- **ERC-20 equivalents**: Fungible tokens (USDC, ETH, etc.)
- **ERC-721 equivalents**: NFTs
- **ERC-1155 equivalents**: Semi-fungible tokens
- **ERC-4626 equivalents**: Vault shares (treated as ERC-20 for transfers)

A single inscription can have mixed collateral (e.g., 1 NFT + 1000 USDC) against mixed debt (e.g., 5000 DAI).

## Multi-Lender Support

Inscriptions can be partially filled by multiple lenders:
- Each lender specifies what percentage of the debt they want to fund (in BPS, max 10,000 = 100%)
- Each lender receives ERC-1155 shares proportional to their contribution
- Shares are redeemable after repayment or liquidation for a proportional slice of the underlying

Example: A 10,000 USDC loan can be filled by Lender A (60%) and Lender B (40%). They receive proportional ERC-1155 shares.

## Token-Bound Accounts (Lockers)

Each active inscription creates a token-bound account (SNIP-14 on StarkNet). This is critical because:

1. **Proof of control**: The borrower's NFT owns the TBA, which holds the collateral. Anyone can verify on-chain that the borrower "controls" these assets. This matters for DAOs, treasuries, and anyone who needs to prove solvency.

2. **Restricted execution**: The TBA allows the borrower to interact with locked assets (voting with governance tokens, claiming airdrops, delegating) but BLOCKS transfers, approvals, and any action that would move assets out.

3. **Transferability**: The inscription NFT (which owns the TBA) is itself transferable. This means:
   - A borrower can sell their debt position
   - A lender can sell their claim (via ERC-1155 shares)
   - Positions can be moved to treasury contracts

4. **Only the Stela contract can move assets**: The locker has a special `pull_assets` function callable only by the Stela contract, used during repayment and liquidation.

## Protocol Fee

A small fee (configurable, default 10 BPS) is taken from lender shares and minted to the protocol treasury.

## Inscription Lifecycle — Detailed

### 1. Create Inscription
- Caller: Borrower OR Lender (the `is_borrow` flag determines which)
- Validation: debt_assets.len() > 0, duration >= 0, collateral_assets.len() > 0, deadline > now
- Computes a unique inscription ID via hash of all parameters + timestamp
- Stores the inscription in the mapping
- Emits `InscriptionCreated` event
- No asset transfers happen at this stage

### 2. Sign/Fill Inscription
Two variants:
- **On-chain**: Counterparty calls `sign_inscription(inscription_id, issued_debt_percentage)`
- **Off-chain** (future): Counterparty submits a signed inscription with the creator's signature

On first fill:
- Mints an NFT to the borrower
- Creates a TBA via the SNIP-14 registry, linked to the NFT
- Records the TBA address as the locker for this inscription

On every fill:
- Validates issued_debt_percentage doesn't exceed remaining (total can't exceed 100%)
- Mints ERC-1155 shares to the lender
- Mints fee shares to treasury
- Locks proportional collateral from borrower into the TBA
- Transfers proportional debt from lender to borrower
- Updates `issued_debt_percentage` on the inscription
- Emits `InscriptionSigned` event

### 3. Repay
- Callable by anyone (third-party repayment allowed)
- Conditions: inscription is active (past deadline, within deadline + duration), not already repaid, not liquidated
- Pulls principal + interest from caller to the Stela contract
- Marks inscription as repaid
- Unlocks collateral (TBA releases assets back to borrower)
- Emits `InscriptionRepaid` event
- Repay timing: The loan activates when sign_inscription is first called (stored as signed_at). The borrower can repay anytime between signed_at and signed_at + duration. The deadline field is ONLY for offer expiry — it has nothing to do with the repayment window. For OTC swaps (duration=0), repay is not applicable — the counterparty can claim collateral immediately after signing.
- Cancellation: The inscription creator can cancel an unfilled inscription (issued_debt_percentage == 0) anytime before someone signs it.


### 4. Liquidate
- Callable by anyone
- Conditions: deadline + duration has passed, not repaid, not already liquidated
- Pulls all collateral from the TBA to the Stela contract
- Marks inscription as liquidated
- Emits `InscriptionLiquidated` event

### 5. Redeem
- Callable by ERC-1155 share holders
- Conditions: inscription is repaid OR liquidated
- Burns caller's shares
- Transfers proportional assets:
  - If repaid: proportional share of debt + interest tokens
  - If liquidated: proportional share of collateral tokens
- Emits `SharesRedeemed` event

## Share Math

Shares use a virtual offset pattern (similar to ERC-4626) to prevent inflation attacks:

```
convertToShares(inscriptionId, issuedDebtPercentage):
  return issuedDebtPercentage * (totalSupply + 1e16) / (inscription.issuedDebtPercentage + 1)

convertToAssets(inscriptionId, shares):
  percentage = shares * (inscription.issuedDebtPercentage + 1) / (totalSupply + 1e16)
  return assets scaled by percentage
```

## Constants

- MAX_BPS: 10,000 (represents 100%)
- Default inscription fee: 10 BPS (0.1%)
- Virtual share offset: 1e16

## Security Considerations

- **Reentrancy**: All state changes before external calls. Use reentrancy guard on sign/repay/liquidate/redeem.
- **Front-running**: Inscription IDs include block.timestamp to prevent prediction.
- **Partial fills**: Must validate cumulative issued_debt_percentage never exceeds MAX_BPS.
- **Single-lender double-sign**: Single-lender inscriptions must reject a second sign_inscription call. Enforced via `assert(issued_debt_percentage == 0)` in the single-lender branch.
- **Multi-lender zero-percentage DOS**: Multi-lender `sign_inscription` must reject 0% fills to prevent griefing (triggering first-fill with no funding, permanently DOSing the inscription).
- **Selector blocklist (locker)**: OpenZeppelin Cairo registers BOTH snake_case and camelCase selectors. The locker must block all variants plus batch transfers, burns, permit, and ERC4626 vault functions.
- **Fee cap**: `set_inscription_fee` rejects fees > MAX_BPS to prevent excessive dilution.
- **Zero-address validation**: Constructor and admin setters reject zero addresses for treasury, registry, and NFT contract. Constructor also rejects zero `implementation_hash`.
- **Asset validation**: `create_inscription` rejects zero-address asset contracts, zero-value fungible assets, and ERC721/ERC1155 in debt/interest arrays (ERC721 can't be scaled/split; ERC1155 debt/interest would lock funds on redeem since redeem functions use IERC20Dispatcher).
- **Asset array cap**: Each asset array (debt, interest, collateral) capped at 10 to prevent gas griefing via unbounded loops.
- **NFT collateral fairness**: Known limitation — in multi-lender liquidation with NFT collateral, the first redeemer gets the entire NFT regardless of share size (inherent to NFT indivisibility).
- **Redemption math**: Uses pro-rata `tracked_balance * shares / total_supply`, NOT percentage-based scaling. The tracked balances already account for partial fills, so using `convert_to_percentage` would double-count.
- **Liquidation proportionality**: `_pull_collateral_from_locker` scales fungible values by `issued_debt_percentage` to match actual locked amounts. Without this, partial fill liquidation reverts.
- **Double liquidation/repayment**: Both are guarded by `already_liquidated`/`already_repaid` checks.
- **Cancel after sign**: Cancelled only if `issued_debt_percentage == 0`.
- **Weird tokens**: The locker blocks standard transfer selectors, but non-standard token functions could bypass this. Document as known limitation.
- **Duration = 0**: OTC swaps — lender gets claim on collateral immediately. Repay window is instant (signed_at to signed_at). Liquidation available at signed_at + 1.
