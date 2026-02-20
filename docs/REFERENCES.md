# REFERENCES.md — Cairo & OpenZeppelin 3.0.0 Code Reference

This file contains **real, working code patterns** from OpenZeppelin Cairo Contracts 3.0.0
and the broader Cairo/StarkNet ecosystem. Claude Code should use these as the canonical
reference for how to write Cairo code in this project.

> **IMPORTANT**: If you're unsure about ANY Cairo syntax or OpenZeppelin API,
> use WebSearch to check the current docs before guessing. The OZ Cairo API
> changes significantly between versions. These examples are for v3.0.0.

## Required Toolchain

```
scarb 2.13.1 (a76aed7 2025-10-30)
cairo: 2.13.1
sierra: 1.7.0
```

---

## 1. ERC20 Contract (Canonical OZ 3.0.0 Pattern)

This is the official example from the OZ Cairo 3.0.0 docs. All component patterns follow this structure.

```cairo
#[starknet::contract]
mod MyERC20Token {
    use openzeppelin_token::erc20::{ERC20Component, ERC20HooksEmptyImpl, DefaultConfig};
    use starknet::ContractAddress;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    // ERC20 Mixin — exposes ALL standard ERC20 functions externally
    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        fixed_supply: u256,
        recipient: ContractAddress
    ) {
        self.erc20.initializer(name, symbol);
        self.erc20.mint(recipient, fixed_supply);
    }
}
```

### Key Points:
- `component!` macro: declares the component with path, storage name, and event name
- `#[abi(embed_v0)]`: makes the impl's functions part of the contract's ABI
- `#[substorage(v0)]`: gives the contract access to the component's storage
- `#[flat]`: flattens the component event (removes component ID from event key)
- `ERC20HooksEmptyImpl`: REQUIRED even if you don't use hooks — import it to satisfy the trait
- `DefaultConfig`: provides default configuration for the ERC20 component

---

## 2. ERC1155 Contract (What Stela Needs for Lender Shares)

```cairo
#[starknet::contract]
mod MyERC1155 {
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::erc1155::{ERC1155Component, ERC1155HooksEmptyImpl};
    use starknet::ContractAddress;

    component!(path: ERC1155Component, storage: erc1155, event: ERC1155Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    // ERC1155 Mixin (includes SRC5)
    #[abi(embed_v0)]
    impl ERC1155MixinImpl = ERC1155Component::ERC1155MixinImpl<ContractState>;
    impl ERC1155InternalImpl = ERC1155Component::InternalImpl<ContractState>;

    // SRC5
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc1155: ERC1155Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC1155Event: ERC1155Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, base_uri: ByteArray) {
        self.erc1155.initializer(base_uri);
    }
}
```

### Key ERC1155 Internal Functions (for minting/burning shares):
```cairo
// Mint shares to a lender
self.erc1155.mint_with_acceptance_check(to, token_id, value, array![].span());

// Burn shares on redeem
self.erc1155.burn(from, token_id, value);

// Check balance
let balance = self.erc1155.balance_of(account, token_id);
```

**IMPORTANT**: ERC1155 requires SRC5Component (interface detection). Always include both.

---

## 3. Ownable Component (Admin Functions)

```cairo
use openzeppelin_access::ownable::OwnableComponent;

component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

#[abi(embed_v0)]
impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

// In storage:
#[substorage(v0)]
ownable: OwnableComponent::Storage,

// In events:
#[flat]
OwnableEvent: OwnableComponent::Event,

// In constructor:
self.ownable.initializer(owner);

// In protected functions:
self.ownable.assert_only_owner();
```

---

## 4. ReentrancyGuard (from openzeppelin_security)

```cairo
use openzeppelin_security::reentrancyguard::ReentrancyGuardComponent;

component!(path: ReentrancyGuardComponent, storage: reentrancy_guard, event: ReentrancyGuardEvent);

impl ReentrancyGuardInternalImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;

// In storage:
#[substorage(v0)]
reentrancy_guard: ReentrancyGuardComponent::Storage,

// In events:
#[flat]
ReentrancyGuardEvent: ReentrancyGuardComponent::Event,

// Usage in functions:
fn sign_inscription(ref self: ContractState, ...) {
    self.reentrancy_guard.start();
    // ... do work ...
    self.reentrancy_guard.end();
}
```

---

## 5. Storage Patterns

### Simple Storage
```cairo
#[storage]
struct Storage {
    counter: u256,
    owner: ContractAddress,
    is_active: bool,
}
```

### Storage Maps
```cairo
use starknet::storage::Map;

#[storage]
struct Storage {
    balances: Map<ContractAddress, u256>,
    inscriptions: Map<u256, StoredInscription>,
    // Composite keys via tuple
    inscription_assets: Map<(u256, u32), Asset>,
}

// Reading:
let balance = self.balances.read(address);

// Writing:
self.balances.write(address, new_balance);
```

### Storing Dynamic Arrays via Indexed Maps
Cairo storage doesn't support dynamic arrays in structs. Use this pattern:

```cairo
#[storage]
struct Storage {
    // Store the count
    inscription_debt_asset_count: Map<u256, u32>,
    // Store each asset by (inscription_id, index)
    inscription_debt_assets: Map<(u256, u32), Asset>,
}

// Writing an array to storage:
fn _store_assets(
    ref self: ContractState,
    inscription_id: u256,
    assets: Span<Asset>,
    count_map: /* storage ref */,
    asset_map: /* storage ref */,
) {
    let len = assets.len();
    count_map.write(inscription_id, len);
    let mut i: u32 = 0;
    while i < len {
        asset_map.write((inscription_id, i), *assets.at(i));
        i += 1;
    };
}

// Reading back:
fn _load_assets(
    self: @ContractState,
    inscription_id: u256,
) -> Array<Asset> {
    let count = self.inscription_debt_asset_count.read(inscription_id);
    let mut assets = ArrayTrait::new();
    let mut i: u32 = 0;
    while i < count {
        assets.append(self.inscription_debt_assets.read((inscription_id, i)));
        i += 1;
    };
    assets
}
```

---

## 6. Events

```cairo
#[event]
#[derive(Drop, starknet::Event)]
enum Event {
    InscriptionCreated: InscriptionCreated,
    InscriptionSigned: InscriptionSigned,
    InscriptionRepaid: InscriptionRepaid,
    InscriptionLiquidated: InscriptionLiquidated,
    SharesRedeemed: SharesRedeemed,
    // Component events:
    #[flat]
    ERC1155Event: ERC1155Component::Event,
}

#[derive(Drop, starknet::Event)]
struct InscriptionCreated {
    #[key]
    inscription_id: u256,
    #[key]
    creator: ContractAddress,
    is_borrow: bool,
}

// Emitting:
self.emit(InscriptionCreated {
    inscription_id,
    creator: get_caller_address(),
    is_borrow: params.is_borrow,
});
```

---

## 7. Error Handling

```cairo
// Define errors as felt252 constants
pub mod Errors {
    pub const UNAUTHORIZED: felt252 = 'STELA: unauthorized';
    pub const INVALID_INSCRIPTION: felt252 = 'STELA: invalid inscription';
}

// Use with assert:
assert(caller == self.owner.read(), Errors::UNAUTHORIZED);

// Or with panic:
if caller != self.owner.read() {
    panic!("STELA: unauthorized");
}
```

---

## 8. Common Imports

```cairo
// Core StarkNet
use starknet::{ContractAddress, get_caller_address, get_block_timestamp, get_contract_address};
use starknet::storage::Map;

// OZ Token components
use openzeppelin_token::erc20::{ERC20Component, ERC20HooksEmptyImpl, DefaultConfig};
use openzeppelin_token::erc721::ERC721Component;
use openzeppelin_token::erc1155::{ERC1155Component, ERC1155HooksEmptyImpl};

// OZ Access
use openzeppelin_access::ownable::OwnableComponent;

// OZ Security
use openzeppelin_security::reentrancyguard::ReentrancyGuardComponent;

// OZ Introspection
use openzeppelin_introspection::src5::SRC5Component;

// OZ Interfaces (for dispatchers — calling external contracts)
use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin_token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};
use openzeppelin_token::erc1155::interface::{IERC1155Dispatcher, IERC1155DispatcherTrait};
```

---

## 9. Calling External Contracts (Dispatchers)

In Cairo, you call other contracts using dispatchers:

```cairo
// Transfer ERC20 tokens from user to this contract
let erc20 = IERC20Dispatcher { contract_address: token_address };
erc20.transfer_from(from, to, amount);

// Transfer ERC721
let erc721 = IERC721Dispatcher { contract_address: nft_address };
erc721.transfer_from(from, to, token_id);

// Transfer ERC1155
let erc1155 = IERC1155Dispatcher { contract_address: token_address };
erc1155.safe_transfer_from(from, to, token_id, amount, array![].span());
```

---

## 10. Hashing (for Inscription IDs)

Use Poseidon hash (native and cheap on StarkNet):

```cairo
use core::poseidon::PoseidonTrait;
use core::hash::{HashStateTrait, HashStateExTrait};

fn compute_inscription_id(
    borrower: ContractAddress,
    lender: ContractAddress,
    duration: u64,
    deadline: u64,
    timestamp: u64,
) -> u256 {
    let hash = PoseidonTrait::new()
        .update_with(borrower)
        .update_with(lender)
        .update_with(duration)
        .update_with(deadline)
        .update_with(timestamp)
        .finalize();
    hash.into()  // felt252 → u256
}
```

---

## 11. Testing with StarkNet Foundry (snforge)

```cairo
use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait,
    start_cheat_caller_address, stop_cheat_caller_address,
    start_cheat_block_timestamp_global, stop_cheat_block_timestamp_global,
};

fn deploy_contract() -> ContractAddress {
    let contract = declare("Stela").unwrap().contract_class();
    let constructor_args = array![/* constructor params as felt252 */];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    contract_address
}

#[test]
fn test_create_inscription() {
    let contract_address = deploy_contract();
    let stela = IStelaProtocolDispatcher { contract_address };

    // Impersonate BORROWER
    start_cheat_caller_address(contract_address, BORROWER());

    // Set block timestamp
    start_cheat_block_timestamp_global(1000);

    let inscription_id = stela.create_inscription(/* params */);
    assert(inscription_id != 0, 'should return valid id');

    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: 'STELA: inscription expired')]
fn test_create_inscription_expired_deadline() {
    // ...
}
```

### Test Helper Addresses
```cairo
fn BORROWER() -> ContractAddress {
    starknet::contract_address_const::<'BORROWER'>()
}

fn LENDER() -> ContractAddress {
    starknet::contract_address_const::<'LENDER'>()
}

fn ADMIN() -> ContractAddress {
    starknet::contract_address_const::<'ADMIN'>()
}
```

---

## 12. Account Contracts (for the Locker)

StarkNet accounts must implement `__validate__` and `__execute__`:

```cairo
#[starknet::contract(account)]
mod LockerAccount {
    use starknet::account::Call;

    #[storage]
    struct Storage {
        stela_contract: ContractAddress,
        unlocked: bool,
    }

    #[abi(per_item)]
    #[generate_trait]
    impl ExternalImpl of ExternalTrait {
        #[external(v0)]
        fn __validate__(self: @ContractState, calls: Array<Call>) -> felt252 {
            // Validate the transaction signature
            // Return starknet::VALIDATED if valid
            starknet::VALIDATED
        }

        #[external(v0)]
        fn __execute__(ref self: ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
            // If locked, check each call's selector against blocked list
            if !self.unlocked.read() {
                _assert_no_forbidden_selectors(@calls);
            }
            // Execute the calls
            _execute_calls(calls)
        }

        #[external(v0)]
        fn __validate_declare__(self: @ContractState, class_hash: felt252) -> felt252 {
            starknet::VALIDATED
        }

        #[external(v0)]
        fn __validate_deploy__(
            self: @ContractState,
            class_hash: felt252,
            salt: felt252,
        ) -> felt252 {
            starknet::VALIDATED
        }
    }
}
```

---

## 13. Blocked Selectors on StarkNet

On StarkNet, function selectors are `sn_keccak(function_name)` truncated to felt252.
Pre-compute these as constants:

```cairo
// sn_keccak("transfer") — but compute these properly!
// Use: core::keccak::compute_keccak_byte_array(@"transfer")
// Or hardcode after computing once

mod BlockedSelectors {
    // These should be computed with sn_keccak and verified.
    // Search for the actual values or compute at contract init.
    const TRANSFER: felt252 = selector!("transfer");
    const TRANSFER_FROM: felt252 = selector!("transfer_from");
    const APPROVE: felt252 = selector!("approve");
    const SAFE_TRANSFER_FROM: felt252 = selector!("safe_transfer_from");
    const SET_APPROVAL_FOR_ALL: felt252 = selector!("set_approval_for_all");
}
```

Note: `selector!("fn_name")` is a Cairo macro that computes the StarkNet selector at compile time.

---

## 14. Math Operations

Cairo uses u256 (two 128-bit limbs). For share math:

```cairo
// Full precision multiply-then-divide (no intermediate overflow for u256)
fn full_mul_div(a: u256, b: u256, denominator: u256) -> u256 {
    assert(denominator != 0, 'division by zero');
    // For u256, we need to be careful about overflow
    // Option 1: Use checked math
    let product = a * b;  // May overflow for very large values
    product / denominator

    // Option 2: For production, implement wide multiplication
    // using u512 intermediary (Alexandria has this)
}

// Constants
const MAX_BPS: u256 = 10_000;
const VIRTUAL_SHARE_OFFSET: u256 = 10_000_000_000_000_000; // 1e16
```

---

## Key URLs for Claude Code to Search

When stuck, search or fetch these URLs:

- **OZ Cairo 3.0.0 Docs**: https://docs.openzeppelin.com/contracts-cairo/3.x
- **OZ Cairo GitHub (source code)**: https://github.com/OpenZeppelin/cairo-contracts
- **OZ Wizard for Cairo**: https://wizard.openzeppelin.com/cairo
- **Cairo Book**: https://book.cairo-lang.org
- **StarkNet Foundry Docs**: https://foundry-rs.github.io/starknet-foundry/
- **Horus Labs TBA (SNIP-14)**: https://github.com/horuslabsio/TBA
- **Scarb Docs**: https://docs.swmansion.com/scarb/

---

## Version Compatibility Matrix

| Package | Version | Notes |
|---------|---------|-------|
| scarb | 2.13.1 | Required for Cairo 2.13.1 |
| cairo | 2.13.1 | Language version |
| openzeppelin_token | 3.0.0 | ERC20, ERC721, ERC1155 |
| openzeppelin_access | 3.0.0 | Ownable, AccessControl |
| openzeppelin_security | 3.0.0 | ReentrancyGuard |
| openzeppelin_introspection | 3.0.0 | SRC5 |
| openzeppelin_account | 3.0.0 | Account abstraction |
| openzeppelin_testing | 6.4.0 | Test utilities (dev) |
| snforge_std | 0.56.0 | StarkNet Foundry (dev) |
