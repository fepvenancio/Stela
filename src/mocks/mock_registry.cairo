// Mock SNIP-14 Registry for testing
// Creates token-bound accounts (LockerAccount) for NFTs

#[starknet::interface]
pub trait IMockRegistry<TContractState> {
    /// Create a token-bound account for an NFT.
    /// Returns the address of the deployed account.
    fn create_account(
        ref self: TContractState,
        implementation_hash: felt252,
        token_contract: starknet::ContractAddress,
        token_id: u256,
    ) -> starknet::ContractAddress;

    /// Get the account address for a given NFT (without deploying).
    fn get_account(
        self: @TContractState, implementation_hash: felt252, token_contract: starknet::ContractAddress, token_id: u256,
    ) -> starknet::ContractAddress;

    /// Update the Stela contract address (for resolving circular deploy dependency).
    fn set_stela_contract(ref self: TContractState, stela_contract: starknet::ContractAddress);
}

#[starknet::contract]
pub mod MockRegistry {
    use core::hash::{HashStateExTrait, HashStateTrait};
    use core::num::traits::Zero;
    use core::poseidon::PoseidonTrait;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::syscalls::deploy_syscall;
    use starknet::{ClassHash, ContractAddress};

    #[storage]
    struct Storage {
        // Stores the Stela contract address (passed to locker on creation)
        stela_contract: ContractAddress,
        // Maps (token_contract, token_id) to deployed account address
        accounts: Map<(ContractAddress, u256), ContractAddress>,
        // Counter for unique salts
        nonce: felt252,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.nonce.write(0);
    }

    #[abi(embed_v0)]
    impl MockRegistryImpl of super::IMockRegistry<ContractState> {
        fn create_account(
            ref self: ContractState, implementation_hash: felt252, token_contract: ContractAddress, token_id: u256,
        ) -> ContractAddress {
            // Check if already deployed
            let existing = self.accounts.read((token_contract, token_id));
            if !existing.is_zero() {
                return existing;
            }

            // Deploy the locker account
            let stela = self.stela_contract.read();

            // Constructor calldata: stela_contract
            let mut constructor_calldata: Array<felt252> = array![];
            stela.serialize(ref constructor_calldata);

            // Generate unique salt using Poseidon hash
            let nonce = self.nonce.read();
            let salt = PoseidonTrait::new()
                .update_with(token_contract)
                .update_with(token_id)
                .update_with(nonce)
                .finalize();

            self.nonce.write(nonce + 1);

            // Deploy the contract
            let class_hash: ClassHash = implementation_hash.try_into().unwrap();
            let (deployed_address, _) = deploy_syscall(class_hash, salt, constructor_calldata.span(), false).unwrap();

            // Store the mapping
            self.accounts.write((token_contract, token_id), deployed_address);

            deployed_address
        }

        fn get_account(
            self: @ContractState, implementation_hash: felt252, token_contract: ContractAddress, token_id: u256,
        ) -> ContractAddress {
            self.accounts.read((token_contract, token_id))
        }

        fn set_stela_contract(ref self: ContractState, stela_contract: ContractAddress) {
            self.stela_contract.write(stela_contract);
        }
    }
}
