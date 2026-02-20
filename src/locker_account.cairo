// Locker Account — Token-Bound Account for Collateral
// SNIP-14 compliant account that restricts asset transfers while allowing other interactions.

#[starknet::contract(account)]
pub mod LockerAccount {
    use openzeppelin_interfaces::erc1155::{IERC1155Dispatcher, IERC1155DispatcherTrait};

    // Token dispatchers
    use openzeppelin_interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin_interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
    use starknet::account::Call;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address, get_contract_address};

    // Local imports
    use crate::errors::Errors;
    use crate::types::asset::{Asset, AssetType};

    // ============================================================
    //                    BLOCKED SELECTORS
    // ============================================================

    // These selectors are blocked to prevent unauthorized asset transfers.
    // Computed using selector!("function_name") macro.
    mod BlockedSelectors {
        // ERC20 snake_case
        pub const TRANSFER: felt252 = selector!("transfer");
        pub const TRANSFER_FROM: felt252 = selector!("transfer_from");
        pub const APPROVE: felt252 = selector!("approve");
        pub const INCREASE_ALLOWANCE: felt252 = selector!("increase_allowance");
        pub const DECREASE_ALLOWANCE: felt252 = selector!("decrease_allowance");

        // ERC20 camelCase (OZ dual dispatch)
        pub const TRANSFER_FROM_CAMEL: felt252 = selector!("transferFrom");
        pub const INCREASE_ALLOWANCE_CAMEL: felt252 = selector!("increaseAllowance");
        pub const DECREASE_ALLOWANCE_CAMEL: felt252 = selector!("decreaseAllowance");

        // ERC721/ERC1155 snake_case
        pub const SAFE_TRANSFER_FROM: felt252 = selector!("safe_transfer_from");
        pub const SET_APPROVAL_FOR_ALL: felt252 = selector!("set_approval_for_all");

        // ERC721/ERC1155 camelCase (OZ dual dispatch)
        pub const SAFE_TRANSFER_FROM_CAMEL: felt252 = selector!("safeTransferFrom");
        pub const SET_APPROVAL_FOR_ALL_CAMEL: felt252 = selector!("setApprovalForAll");

        // ERC1155 batch transfer
        pub const SAFE_BATCH_TRANSFER_FROM: felt252 = selector!("safe_batch_transfer_from");
        pub const SAFE_BATCH_TRANSFER_FROM_CAMEL: felt252 = selector!("safeBatchTransferFrom");

        // Burn functions (prevent token destruction)
        pub const BURN: felt252 = selector!("burn");
        pub const BURN_FROM: felt252 = selector!("burn_from");
        pub const BURN_FROM_CAMEL: felt252 = selector!("burnFrom");

        // ERC20 permit (gasless approval bypass)
        pub const PERMIT: felt252 = selector!("permit");

        // ERC4626 vault withdrawal functions
        pub const WITHDRAW: felt252 = selector!("withdraw");
        pub const REDEEM: felt252 = selector!("redeem");
    }

    // ============================================================
    //                          STORAGE
    // ============================================================

    #[storage]
    struct Storage {
        // The Stela protocol contract address (only address that can pull assets)
        stela_contract: ContractAddress,
        // Whether the locker is unlocked (restrictions removed)
        unlocked: bool,
    }

    // ============================================================
    //                          EVENTS
    // ============================================================

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        LockerUnlocked: LockerUnlocked,
        AssetsPulled: AssetsPulled,
    }

    #[derive(Drop, starknet::Event)]
    pub struct LockerUnlocked {
        #[key]
        pub locker: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct AssetsPulled {
        #[key]
        pub locker: ContractAddress,
        pub asset_count: u32,
    }

    // ============================================================
    //                        CONSTRUCTOR
    // ============================================================

    #[constructor]
    fn constructor(ref self: ContractState, stela_contract: ContractAddress) {
        self.stela_contract.write(stela_contract);
        self.unlocked.write(false);
    }

    // ============================================================
    //                    ACCOUNT INTERFACE
    // ============================================================

    #[abi(per_item)]
    #[generate_trait]
    impl AccountImpl of AccountTrait {
        /// Validate a transaction.
        /// For a TBA, we typically validate based on the NFT owner.
        /// For simplicity, we return VALIDATED if the locker is unlocked,
        /// or if the call doesn't target blocked selectors.
        #[external(v0)]
        fn __validate__(self: @ContractState, calls: Span<Call>) -> felt252 {
            // If unlocked, allow all calls
            if self.unlocked.read() {
                return starknet::VALIDATED;
            }

            // Check each call for blocked selectors
            let mut i: u32 = 0;
            let len = calls.len();
            while i < len {
                let call = *calls.at(i);
                assert(!_is_blocked_selector(call.selector), Errors::FORBIDDEN_SELECTOR);
                i += 1;
            }

            starknet::VALIDATED
        }

        /// Execute calls.
        /// If locked, blocked selectors are rejected.
        #[external(v0)]
        fn __execute__(ref self: ContractState, calls: Span<Call>) -> Array<Span<felt252>> {
            // If locked, verify no blocked selectors
            if !self.unlocked.read() {
                let mut i: u32 = 0;
                let len = calls.len();
                while i < len {
                    let call = *calls.at(i);
                    assert(!_is_blocked_selector(call.selector), Errors::FORBIDDEN_SELECTOR);
                    i += 1;
                };
            }

            // Execute all calls
            _execute_calls(calls)
        }

        /// Validate a declare transaction.
        #[external(v0)]
        fn __validate_declare__(self: @ContractState, class_hash: felt252) -> felt252 {
            starknet::VALIDATED
        }
    }

    // ============================================================
    //                    LOCKER INTERFACE
    // ============================================================

    #[abi(embed_v0)]
    impl LockerAccountImpl of crate::interfaces::ilocker::ILockerAccount<ContractState> {
        /// Pull assets from the locker to the Stela contract.
        /// Only callable by the Stela contract.
        fn pull_assets(ref self: ContractState, assets: Array<Asset>) {
            let caller = get_caller_address();
            let stela = self.stela_contract.read();
            assert(caller == stela, Errors::UNAUTHORIZED);

            let this_contract = get_contract_address();
            let mut i: u32 = 0;
            let len = assets.len();

            while i < len {
                let asset = *assets.at(i);
                _transfer_asset(asset, this_contract, stela);
                i += 1;
            }

            self.emit(AssetsPulled { locker: this_contract, asset_count: len });
        }

        /// Unlock the locker, removing execution restrictions.
        /// Only callable by the Stela contract.
        fn unlock(ref self: ContractState) {
            let caller = get_caller_address();
            let stela = self.stela_contract.read();
            assert(caller == stela, Errors::UNAUTHORIZED);

            self.unlocked.write(true);
            self.emit(LockerUnlocked { locker: get_contract_address() });
        }

        /// Check if the locker is currently unlocked.
        fn is_unlocked(self: @ContractState) -> bool {
            self.unlocked.read()
        }
    }

    // ============================================================
    //                   INTERNAL FUNCTIONS
    // ============================================================

    /// Check if a selector is blocked.
    fn _is_blocked_selector(selector: felt252) -> bool {
        // ERC20 snake_case + camelCase
        selector == BlockedSelectors::TRANSFER
            || selector == BlockedSelectors::TRANSFER_FROM
            || selector == BlockedSelectors::TRANSFER_FROM_CAMEL
            || selector == BlockedSelectors::APPROVE
            || selector == BlockedSelectors::INCREASE_ALLOWANCE
            || selector == BlockedSelectors::DECREASE_ALLOWANCE
            || selector == BlockedSelectors::INCREASE_ALLOWANCE_CAMEL
            || selector == BlockedSelectors::DECREASE_ALLOWANCE_CAMEL
            // ERC721/ERC1155 snake_case + camelCase
            || selector == BlockedSelectors::SAFE_TRANSFER_FROM
            || selector == BlockedSelectors::SAFE_TRANSFER_FROM_CAMEL
            || selector == BlockedSelectors::SET_APPROVAL_FOR_ALL
            || selector == BlockedSelectors::SET_APPROVAL_FOR_ALL_CAMEL
            // ERC1155 batch transfers
            || selector == BlockedSelectors::SAFE_BATCH_TRANSFER_FROM
            || selector == BlockedSelectors::SAFE_BATCH_TRANSFER_FROM_CAMEL
            // Burn functions
            || selector == BlockedSelectors::BURN
            || selector == BlockedSelectors::BURN_FROM
            || selector == BlockedSelectors::BURN_FROM_CAMEL
            // Permit + ERC4626 vault
            || selector == BlockedSelectors::PERMIT
            || selector == BlockedSelectors::WITHDRAW
            || selector == BlockedSelectors::REDEEM
    }

    /// Execute a list of calls.
    fn _execute_calls(mut calls: Span<Call>) -> Array<Span<felt252>> {
        let mut results: Array<Span<felt252>> = array![];

        while let Option::Some(call) = calls.pop_front() {
            let result = starknet::syscalls::call_contract_syscall(*call.to, *call.selector, *call.calldata).unwrap();
            results.append(result);
        }

        results
    }

    /// Transfer a single asset to a destination.
    fn _transfer_asset(asset: Asset, from: ContractAddress, to: ContractAddress) {
        match asset.asset_type {
            AssetType::ERC20 => {
                let erc20 = IERC20Dispatcher { contract_address: asset.asset };
                erc20.transfer(to, asset.value);
            },
            AssetType::ERC721 => {
                let erc721 = IERC721Dispatcher { contract_address: asset.asset };
                erc721.transfer_from(from, to, asset.token_id);
            },
            AssetType::ERC1155 => {
                let erc1155 = IERC1155Dispatcher { contract_address: asset.asset };
                erc1155.safe_transfer_from(from, to, asset.token_id, asset.value, array![].span());
            },
            AssetType::ERC4626 => {
                // ERC4626 is ERC20-compatible
                let erc20 = IERC20Dispatcher { contract_address: asset.asset };
                erc20.transfer(to, asset.value);
            },
        }
    }
}
