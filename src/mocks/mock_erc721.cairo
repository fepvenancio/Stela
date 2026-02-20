// Mock ERC721 token for testing (Inscriptions NFT)
// Simple implementation with mint function for test setup

#[starknet::interface]
pub trait IMockERC721<TContractState> {
    fn name(self: @TContractState) -> ByteArray;
    fn symbol(self: @TContractState) -> ByteArray;
    fn balance_of(self: @TContractState, owner: starknet::ContractAddress) -> u256;
    fn owner_of(self: @TContractState, token_id: u256) -> starknet::ContractAddress;
    fn get_approved(self: @TContractState, token_id: u256) -> starknet::ContractAddress;
    fn is_approved_for_all(
        self: @TContractState, owner: starknet::ContractAddress, operator: starknet::ContractAddress,
    ) -> bool;
    fn approve(ref self: TContractState, to: starknet::ContractAddress, token_id: u256);
    fn set_approval_for_all(ref self: TContractState, operator: starknet::ContractAddress, approved: bool);
    fn transfer_from(
        ref self: TContractState, from: starknet::ContractAddress, to: starknet::ContractAddress, token_id: u256,
    );
    // Test helper - mintable by anyone for testing
    fn mint(ref self: TContractState, to: starknet::ContractAddress, token_id: u256);
}

#[starknet::contract]
pub mod MockERC721 {
    use core::num::traits::Zero;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    struct Storage {
        name: ByteArray,
        symbol: ByteArray,
        owners: Map<u256, ContractAddress>,
        balances: Map<ContractAddress, u256>,
        token_approvals: Map<u256, ContractAddress>,
        operator_approvals: Map<(ContractAddress, ContractAddress), bool>,
    }

    #[constructor]
    fn constructor(ref self: ContractState, name: ByteArray, symbol: ByteArray) {
        self.name.write(name);
        self.symbol.write(symbol);
    }

    #[abi(embed_v0)]
    impl MockERC721Impl of super::IMockERC721<ContractState> {
        fn name(self: @ContractState) -> ByteArray {
            self.name.read()
        }

        fn symbol(self: @ContractState) -> ByteArray {
            self.symbol.read()
        }

        fn balance_of(self: @ContractState, owner: ContractAddress) -> u256 {
            self.balances.read(owner)
        }

        fn owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
            let owner = self.owners.read(token_id);
            assert(!owner.is_zero(), 'ERC721: invalid token ID');
            owner
        }

        fn get_approved(self: @ContractState, token_id: u256) -> ContractAddress {
            self.token_approvals.read(token_id)
        }

        fn is_approved_for_all(self: @ContractState, owner: ContractAddress, operator: ContractAddress) -> bool {
            self.operator_approvals.read((owner, operator))
        }

        fn approve(ref self: ContractState, to: ContractAddress, token_id: u256) {
            let owner = self.owners.read(token_id);
            let caller = get_caller_address();
            assert(caller == owner || self.operator_approvals.read((owner, caller)), 'ERC721: not authorized');
            self.token_approvals.write(token_id, to);
        }

        fn set_approval_for_all(ref self: ContractState, operator: ContractAddress, approved: bool) {
            let owner = get_caller_address();
            self.operator_approvals.write((owner, operator), approved);
        }

        fn transfer_from(ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256) {
            let owner = self.owners.read(token_id);
            assert(owner == from, 'ERC721: wrong owner');

            let caller = get_caller_address();
            let is_approved = caller == owner
                || self.token_approvals.read(token_id) == caller
                || self.operator_approvals.read((owner, caller));
            assert(is_approved, 'ERC721: not authorized');

            // Clear approval
            let zero: ContractAddress = Zero::zero();
            self.token_approvals.write(token_id, zero);

            // Update balances
            let from_balance = self.balances.read(from);
            self.balances.write(from, from_balance - 1);
            let to_balance = self.balances.read(to);
            self.balances.write(to, to_balance + 1);

            // Transfer ownership
            self.owners.write(token_id, to);
        }

        fn mint(ref self: ContractState, to: ContractAddress, token_id: u256) {
            let zero: ContractAddress = Zero::zero();
            let current_owner = self.owners.read(token_id);
            assert(current_owner == zero, 'ERC721: token already minted');

            self.owners.write(token_id, to);
            let balance = self.balances.read(to);
            self.balances.write(to, balance + 1);
        }
    }
}
