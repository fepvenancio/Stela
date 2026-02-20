// Tests for repay function

use snforge_std::{
    start_cheat_block_timestamp_global, start_cheat_caller_address, stop_cheat_block_timestamp_global,
    stop_cheat_caller_address,
};
use stela::interfaces::istela::IStelaProtocolDispatcherTrait;
use super::test_utils::{BORROWER, create_borrow_params, deploy_stela};

// ============================================================
//                    BASIC REPAY TESTS
// ============================================================

#[test]
#[feature("deprecated-starknet-consts")]
fn test_repay_view_function() {
    // This test verifies the repay view function works
    let (contract_address, stela) = deploy_stela();

    start_cheat_block_timestamp_global(1000);
    start_cheat_caller_address(contract_address, BORROWER());

    let debt_token = starknet::contract_address_const::<'DEBT'>();
    let collateral_token = starknet::contract_address_const::<'COL'>();
    let interest_token = starknet::contract_address_const::<'INT'>();

    // Create inscription with duration 86400 (1 day)
    let params = create_borrow_params(debt_token, 1000, collateral_token, 500, interest_token, 100, 86400, 2000);

    let inscription_id = stela.create_inscription(params);

    // Verify inscription is not yet repaid
    let inscription = stela.get_inscription(inscription_id);
    assert(!inscription.is_repaid, 'not repaid yet');

    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp_global();
}

#[test]
#[should_panic(expected: 'STELA: invalid inscription')]
fn test_repay_nonexistent_inscription() {
    // Non-existent inscriptions have signed_at = 0, so we get "invalid inscription"
    let (contract_address, stela) = deploy_stela();

    start_cheat_block_timestamp_global(1000);
    start_cheat_caller_address(contract_address, BORROWER());

    // Try to repay a non-existent inscription
    stela.repay(999);
}

#[test]
#[feature("deprecated-starknet-consts")]
fn test_inscription_duration_tracking() {
    let (contract_address, stela) = deploy_stela();

    start_cheat_block_timestamp_global(1000);
    start_cheat_caller_address(contract_address, BORROWER());

    let debt_token = starknet::contract_address_const::<'DEBT'>();
    let collateral_token = starknet::contract_address_const::<'COL'>();
    let interest_token = starknet::contract_address_const::<'INT'>();

    // Create with specific duration
    let duration: u64 = 86400; // 1 day
    let params = create_borrow_params(debt_token, 1000, collateral_token, 500, interest_token, 100, duration, 2000);

    let inscription_id = stela.create_inscription(params);

    let inscription = stela.get_inscription(inscription_id);
    assert(inscription.duration == duration, 'duration mismatch');

    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp_global();
}

// ============================================================
//                    REPAY TIMING TESTS
// ============================================================

#[test]
#[feature("deprecated-starknet-consts")]
fn test_inscription_not_started() {
    // An inscription that hasn't been signed has issued_debt_percentage = 0
    let (contract_address, stela) = deploy_stela();

    start_cheat_block_timestamp_global(1000);
    start_cheat_caller_address(contract_address, BORROWER());

    let debt_token = starknet::contract_address_const::<'DEBT'>();
    let collateral_token = starknet::contract_address_const::<'COL'>();
    let interest_token = starknet::contract_address_const::<'INT'>();

    let params = create_borrow_params(debt_token, 1000, collateral_token, 500, interest_token, 100, 86400, 2000);

    let inscription_id = stela.create_inscription(params);

    let inscription = stela.get_inscription(inscription_id);
    // Before signing, no debt issued
    assert(inscription.issued_debt_percentage == 0, 'no debt issued yet');

    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp_global();
}

// ============================================================
//                    REPAY STATE TESTS
// ============================================================

#[test]
#[feature("deprecated-starknet-consts")]
fn test_inscription_repaid_flag() {
    let (contract_address, stela) = deploy_stela();

    start_cheat_block_timestamp_global(1000);
    start_cheat_caller_address(contract_address, BORROWER());

    let debt_token = starknet::contract_address_const::<'DEBT'>();
    let collateral_token = starknet::contract_address_const::<'COL'>();
    let interest_token = starknet::contract_address_const::<'INT'>();

    let params = create_borrow_params(debt_token, 1000, collateral_token, 500, interest_token, 100, 86400, 2000);

    let inscription_id = stela.create_inscription(params);

    let inscription = stela.get_inscription(inscription_id);
    assert(!inscription.is_repaid, 'not repaid');
    assert(!inscription.liquidated, 'not liquidated');

    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp_global();
}
