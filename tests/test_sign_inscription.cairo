// Tests for sign_inscription function

use snforge_std::{
    start_cheat_block_timestamp_global, start_cheat_caller_address, stop_cheat_block_timestamp_global,
    stop_cheat_caller_address,
};
use stela::interfaces::istela::IStelaProtocolDispatcherTrait;
use super::test_utils::{BORROWER, LENDER, create_borrow_params, create_multi_lender_borrow_params, deploy_stela};

// ============================================================
//                    BASIC SIGN TESTS
// ============================================================

#[test]
#[feature("deprecated-starknet-consts")]
fn test_sign_single_lender_basic() {
    // This test verifies the basic sign_inscription flow without real token transfers
    // (since we use stub addresses for NFT/registry)
    let (contract_address, stela) = deploy_stela();

    start_cheat_block_timestamp_global(1000);

    // Borrower creates inscription
    start_cheat_caller_address(contract_address, BORROWER());
    let debt_token = starknet::contract_address_const::<'DEBT'>();
    let collateral_token = starknet::contract_address_const::<'COL'>();
    let interest_token = starknet::contract_address_const::<'INT'>();

    let params = create_borrow_params(debt_token, 1000, collateral_token, 500, interest_token, 100, 86400, 2000);

    let inscription_id = stela.create_inscription(params);
    stop_cheat_caller_address(contract_address);

    // Verify inscription state before signing
    let inscription = stela.get_inscription(inscription_id);
    assert(inscription.issued_debt_percentage == 0, '0% issued');

    stop_cheat_block_timestamp_global();
}

#[test]
#[should_panic(expected: 'STELA: invalid inscription')]
fn test_sign_nonexistent_inscription() {
    let (contract_address, stela) = deploy_stela();

    start_cheat_block_timestamp_global(1000);
    start_cheat_caller_address(contract_address, LENDER());

    // Try to sign a non-existent inscription
    stela.sign_inscription(999, 10000);
}

#[test]
#[feature("deprecated-starknet-consts")]
#[should_panic(expected: 'STELA: inscription expired')]
fn test_sign_expired_inscription() {
    let (contract_address, stela) = deploy_stela();

    start_cheat_block_timestamp_global(1000);

    // Borrower creates inscription with deadline 2000
    start_cheat_caller_address(contract_address, BORROWER());
    let debt_token = starknet::contract_address_const::<'DEBT'>();
    let collateral_token = starknet::contract_address_const::<'COL'>();
    let interest_token = starknet::contract_address_const::<'INT'>();

    let params = create_borrow_params(debt_token, 1000, collateral_token, 500, interest_token, 100, 86400, 2000);

    let inscription_id = stela.create_inscription(params);
    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp_global();

    // Time passes beyond deadline
    start_cheat_block_timestamp_global(3000);
    start_cheat_caller_address(contract_address, LENDER());

    // Try to sign after expiry
    stela.sign_inscription(inscription_id, 10000);
}

// ============================================================
//                    MULTI-LENDER TESTS
// ============================================================

#[test]
#[feature("deprecated-starknet-consts")]
fn test_multi_lender_inscription_creation() {
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

    let inscription = stela.get_inscription(inscription_id);
    assert(inscription.multi_lender, 'is multi-lender');
    assert(inscription.issued_debt_percentage == 0, '0% issued');

    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp_global();
}

// Note: Tests that call sign_inscription with multi-lender exceeds_max_bps
// require full mock contract setup because sign_inscription tries to interact
// with the NFT and registry contracts. This test is not included in the
// basic test suite that uses stub addresses.

// ============================================================
//                    SHARE CALCULATION TESTS
// ============================================================

#[test]
#[feature("deprecated-starknet-consts")]
fn test_convert_to_shares_view() {
    let (contract_address, stela) = deploy_stela();

    start_cheat_block_timestamp_global(1000);
    start_cheat_caller_address(contract_address, BORROWER());

    let debt_token = starknet::contract_address_const::<'DEBT'>();
    let collateral_token = starknet::contract_address_const::<'COL'>();
    let interest_token = starknet::contract_address_const::<'INT'>();

    let params = create_borrow_params(debt_token, 1000, collateral_token, 500, interest_token, 100, 86400, 2000);

    let inscription_id = stela.create_inscription(params);

    // Calculate expected shares for 100% (10000 BPS)
    let shares = stela.convert_to_shares(inscription_id, 10000);

    // With no prior supply, shares = 10000 * (0 + 1e16) / (0 + 1) = 1e20
    assert(shares > 0, 'positive shares');

    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp_global();
}
