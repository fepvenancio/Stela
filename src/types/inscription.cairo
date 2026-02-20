// Inscription types for Stela protocol
// Phase 1: Implement these types

use starknet::ContractAddress;

/// Parameters for creating a new inscription.
/// Passed by the caller — either a borrower or a lender.
#[derive(Drop, Serde)]
pub struct InscriptionParams {
    pub is_borrow: bool,
    pub debt_assets: Array<super::asset::Asset>,
    pub interest_assets: Array<super::asset::Asset>,
    pub collateral_assets: Array<super::asset::Asset>,
    pub duration: u64,
    pub deadline: u64,
    pub multi_lender: bool,
}

/// On-chain stored inscription state.
///
/// NOTE: Cairo storage doesn't natively support dynamic arrays in structs.
/// The actual implementation will store assets in separate indexed maps.
/// This struct stores the scalar fields only.
#[derive(Drop, Copy, Serde, starknet::Store, PartialEq)]
pub struct StoredInscription {
    pub borrower: ContractAddress,
    pub lender: ContractAddress,
    pub duration: u64,
    pub deadline: u64,
    pub signed_at: u64,
    pub issued_debt_percentage: u256,
    pub is_repaid: bool,
    pub liquidated: bool,
    pub multi_lender: bool,
    pub debt_asset_count: u32,
    pub interest_asset_count: u32,
    pub collateral_asset_count: u32,
}
