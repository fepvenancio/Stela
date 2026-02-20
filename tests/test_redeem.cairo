// Tests for redeem function

use snforge_std::{
    start_cheat_block_timestamp_global, start_cheat_caller_address, stop_cheat_block_timestamp_global,
    stop_cheat_caller_address,
};
use stela::interfaces::istela::IStelaProtocolDispatcherTrait;
use super::test_utils::{BORROWER, LENDER, create_borrow_params, create_multi_lender_borrow_params, deploy_stela};

// ============================================================
//                    BASIC REDEEM TESTS
// ============================================================

#[test]
#[feature("deprecated-starknet-consts")]
fn test_redeem_view_functions() {
    // Test share conversion functions that support redeem
    let (contract_address, stela) = deploy_stela();

    start_cheat_block_timestamp_global(1000);
    start_cheat_caller_address(contract_address, BORROWER());

    let debt_token = starknet::contract_address_const::<'DEBT'>();
    let collateral_token = starknet::contract_address_const::<'COL'>();
    let interest_token = starknet::contract_address_const::<'INT'>();

    let params = create_borrow_params(debt_token, 1000, collateral_token, 500, interest_token, 100, 86400, 2000);

    let inscription_id = stela.create_inscription(params);

    // Test convert_to_shares
    let shares = stela.convert_to_shares(inscription_id, 5000); // 50%
    assert(shares > 0, 'positive shares');

    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp_global();
}

#[test]
#[should_panic(expected: 'STELA: not redeemable')]
fn test_redeem_nonexistent_inscription() {
    let (contract_address, stela) = deploy_stela();

    start_cheat_block_timestamp_global(1000);
    start_cheat_caller_address(contract_address, LENDER());

    // Try to redeem from a non-existent inscription
    // Returns "not redeemable" because default inscription has is_repaid=false, liquidated=false
    stela.redeem(999, 1000);
}

// ============================================================
//                    SHARE CALCULATION TESTS
// ============================================================

#[test]
#[feature("deprecated-starknet-consts")]
fn test_share_math_basic() {
    let (contract_address, stela) = deploy_stela();

    start_cheat_block_timestamp_global(1000);
    start_cheat_caller_address(contract_address, BORROWER());

    let debt_token = starknet::contract_address_const::<'DEBT'>();
    let collateral_token = starknet::contract_address_const::<'COL'>();
    let interest_token = starknet::contract_address_const::<'INT'>();

    let params = create_borrow_params(debt_token, 1000, collateral_token, 500, interest_token, 100, 86400, 2000);

    let inscription_id = stela.create_inscription(params);

    // Convert BPS to shares
    let shares_100 = stela.convert_to_shares(inscription_id, 10000); // 100%
    let shares_50 = stela.convert_to_shares(inscription_id, 5000); // 50%

    // 100% should give more shares than 50%
    assert(shares_100 > shares_50, '100% > 50%');
    assert(shares_100 > 0, 'positive shares');

    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp_global();
}

#[test]
#[feature("deprecated-starknet-consts")]
fn test_multi_lender_share_calculation() {
    let (contract_address, stela) = deploy_stela();

    start_cheat_block_timestamp_global(1000);
    start_cheat_caller_address(contract_address, BORROWER());

    let debt_token = starknet::contract_address_const::<'DEBT'>();
    let collateral_token = starknet::contract_address_const::<'COL'>();
    let interest_token = starknet::contract_address_const::<'INT'>();

    let params = create_multi_lender_borrow_params(
        debt_token, 10000, collateral_token, 5000, interest_token, 1000, 86400, 2000,
    );

    let inscription_id = stela.create_inscription(params);

    // Each lender taking 50% should get equal shares
    let shares_50_percent = stela.convert_to_shares(inscription_id, 5000);
    let shares_100_percent = stela.convert_to_shares(inscription_id, 10000);

    // 100% should be roughly double 50%
    assert(shares_100_percent > shares_50_percent, '100% > 50%');

    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp_global();
}

// ============================================================
//                    REDEEM STATE TESTS
// ============================================================

#[test]
#[feature("deprecated-starknet-consts")]
fn test_inscription_state_for_redeem() {
    // Test that inscription tracks state needed for redeem
    let (contract_address, stela) = deploy_stela();

    start_cheat_block_timestamp_global(1000);
    start_cheat_caller_address(contract_address, BORROWER());

    let debt_token = starknet::contract_address_const::<'DEBT'>();
    let collateral_token = starknet::contract_address_const::<'COL'>();
    let interest_token = starknet::contract_address_const::<'INT'>();

    let params = create_borrow_params(debt_token, 1000, collateral_token, 500, interest_token, 100, 86400, 2000);

    let inscription_id = stela.create_inscription(params);

    let inscription = stela.get_inscription(inscription_id);

    // These states determine what can be redeemed
    // is_repaid: true -> lender gets debt + interest
    // liquidated: true -> lender gets collateral
    // neither: nothing to redeem yet
    assert(!inscription.is_repaid, 'not repaid');
    assert(!inscription.liquidated, 'not liquidated');

    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp_global();
}

#[test]
#[feature("deprecated-starknet-consts")]
fn test_interest_asset_tracking() {
    // Test that interest assets are properly tracked for redeem
    let (contract_address, stela) = deploy_stela();

    start_cheat_block_timestamp_global(1000);
    start_cheat_caller_address(contract_address, BORROWER());

    let debt_token = starknet::contract_address_const::<'DEBT'>();
    let collateral_token = starknet::contract_address_const::<'COL'>();
    let interest_token = starknet::contract_address_const::<'INT'>();

    let params = create_borrow_params(debt_token, 1000, collateral_token, 500, interest_token, 100, 86400, 2000);

    let inscription_id = stela.create_inscription(params);

    let inscription = stela.get_inscription(inscription_id);
    assert(inscription.interest_asset_count == 1, '1 interest asset');
    assert(inscription.debt_asset_count == 1, '1 debt asset');

    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp_global();
}
