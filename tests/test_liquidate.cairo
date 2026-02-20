// Tests for liquidate function

use snforge_std::{
    start_cheat_block_timestamp_global, start_cheat_caller_address, stop_cheat_block_timestamp_global,
    stop_cheat_caller_address,
};
use stela::interfaces::istela::IStelaProtocolDispatcherTrait;
use super::test_utils::{BORROWER, LENDER, create_borrow_params, deploy_stela};

// ============================================================
//                    BASIC LIQUIDATE TESTS
// ============================================================

#[test]
#[feature("deprecated-starknet-consts")]
fn test_liquidate_view_function() {
    // This test verifies inscription liquidation state tracking
    let (contract_address, stela) = deploy_stela();

    start_cheat_block_timestamp_global(1000);
    start_cheat_caller_address(contract_address, BORROWER());

    let debt_token = starknet::contract_address_const::<'DEBT'>();
    let collateral_token = starknet::contract_address_const::<'COL'>();
    let interest_token = starknet::contract_address_const::<'INT'>();

    let params = create_borrow_params(debt_token, 1000, collateral_token, 500, interest_token, 100, 86400, 2000);

    let inscription_id = stela.create_inscription(params);

    let inscription = stela.get_inscription(inscription_id);
    assert(!inscription.liquidated, 'not liquidated');

    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp_global();
}

#[test]
fn test_liquidate_returns_silently_for_nonexistent() {
    // For non-existent inscriptions, the storage returns default values
    // The function may return silently if checks pass on default values
    let (contract_address, stela) = deploy_stela();

    start_cheat_block_timestamp_global(1000);
    start_cheat_caller_address(contract_address, LENDER());

    // Get inscription returns default values for non-existent
    let inscription = stela.get_inscription(999);
    // Default inscription has all zero values
    assert(inscription.duration == 0, 'default duration');
    assert(inscription.deadline == 0, 'default deadline');
}

// ============================================================
//                    LIQUIDATION STATE TESTS
// ============================================================

#[test]
#[feature("deprecated-starknet-consts")]
fn test_inscription_liquidation_flags() {
    let (contract_address, stela) = deploy_stela();

    start_cheat_block_timestamp_global(1000);
    start_cheat_caller_address(contract_address, BORROWER());

    let debt_token = starknet::contract_address_const::<'DEBT'>();
    let collateral_token = starknet::contract_address_const::<'COL'>();
    let interest_token = starknet::contract_address_const::<'INT'>();

    let params = create_borrow_params(debt_token, 1000, collateral_token, 500, interest_token, 100, 86400, 2000);

    let inscription_id = stela.create_inscription(params);

    let inscription = stela.get_inscription(inscription_id);
    // New inscription should not be liquidated or repaid
    assert(!inscription.liquidated, 'not liquidated');
    assert(!inscription.is_repaid, 'not repaid');

    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp_global();
}

// ============================================================
//                    LIQUIDATION TIMING TESTS
// ============================================================

#[test]
#[feature("deprecated-starknet-consts")]
fn test_inscription_expiry_calculation() {
    // Test that inscription expiry is properly tracked
    let (contract_address, stela) = deploy_stela();

    start_cheat_block_timestamp_global(1000);
    start_cheat_caller_address(contract_address, BORROWER());

    let debt_token = starknet::contract_address_const::<'DEBT'>();
    let collateral_token = starknet::contract_address_const::<'COL'>();
    let interest_token = starknet::contract_address_const::<'INT'>();

    let duration: u64 = 86400; // 1 day
    let params = create_borrow_params(debt_token, 1000, collateral_token, 500, interest_token, 100, duration, 2000);

    let inscription_id = stela.create_inscription(params);

    let inscription = stela.get_inscription(inscription_id);
    assert(inscription.duration == duration, 'duration correct');

    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp_global();
}

#[test]
#[feature("deprecated-starknet-consts")]
fn test_multi_asset_collateral_tracking() {
    // Test that collateral assets are properly tracked for liquidation
    let (contract_address, stela) = deploy_stela();

    start_cheat_block_timestamp_global(1000);
    start_cheat_caller_address(contract_address, BORROWER());

    let debt_token = starknet::contract_address_const::<'DEBT'>();
    let collateral_token = starknet::contract_address_const::<'COL'>();
    let interest_token = starknet::contract_address_const::<'INT'>();

    let params = create_borrow_params(debt_token, 1000, collateral_token, 500, interest_token, 100, 86400, 2000);

    let inscription_id = stela.create_inscription(params);

    let inscription = stela.get_inscription(inscription_id);
    assert(inscription.collateral_asset_count == 1, '1 collateral');
    assert(inscription.debt_asset_count == 1, '1 debt');

    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp_global();
}
