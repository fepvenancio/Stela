// IRegistry — SNIP-14 Token-Bound Account Registry Interface

use starknet::ContractAddress;

#[starknet::interface]
pub trait IRegistry<TContractState> {
    /// Create a token-bound account for an NFT.
    ///
    /// # Arguments
    /// * `implementation_hash` - Class hash of the account implementation to deploy
    /// * `token_contract` - Address of the NFT contract
    /// * `token_id` - Token ID of the NFT
    ///
    /// # Returns
    /// The address of the deployed token-bound account
    fn create_account(
        ref self: TContractState, implementation_hash: felt252, token_contract: ContractAddress, token_id: u256,
    ) -> ContractAddress;

    /// Get the account address for a given NFT (may or may not be deployed).
    fn get_account(
        self: @TContractState, implementation_hash: felt252, token_contract: ContractAddress, token_id: u256,
    ) -> ContractAddress;
}
