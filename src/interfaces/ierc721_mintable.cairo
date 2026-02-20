// IERC721Mintable — ERC721 with mint capability
// Used for the Inscriptions NFT contract

use starknet::ContractAddress;

#[starknet::interface]
pub trait IERC721Mintable<TContractState> {
    /// Mint a new NFT to an address.
    ///
    /// # Arguments
    /// * `to` - Address to mint the NFT to
    /// * `token_id` - Token ID to mint
    fn mint(ref self: TContractState, to: ContractAddress, token_id: u256);
}
