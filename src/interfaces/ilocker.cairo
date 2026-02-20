// ILockerAccount — Token-bound account (TBA) interface for collateral locking
// Phase 2: Define the full interface

use crate::types::asset::Asset;

#[starknet::interface]
pub trait ILockerAccount<TContractState> {
    /// Pull assets from the locker to the Stela contract.
    /// Only callable by the Stela contract.
    fn pull_assets(ref self: TContractState, assets: Array<Asset>);

    /// Unlock the locker, removing execution restrictions.
    /// Only callable by the Stela contract.
    fn unlock(ref self: TContractState);

    /// Check if the locker is currently unlocked.
    fn is_unlocked(self: @TContractState) -> bool;
}
