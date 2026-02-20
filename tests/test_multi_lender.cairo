// Tests for multi-lender functionality

use snforge_std::{
    start_cheat_block_timestamp_global, start_cheat_caller_address, stop_cheat_block_timestamp_global,
    stop_cheat_caller_address,
};
use stela::interfaces::istela::IStelaProtocolDispatcherTrait;
use super::test_utils::{BORROWER, create_multi_lender_borrow_params, deploy_stela};

// ============================================================
//                    MULTI-LENDER CREATION TESTS
// ============================================================

#[test]
#[feature("deprecated-starknet-consts")]
fn test_create_multi_lender_inscription() {
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

#[test]
#[feature("deprecated-starknet-consts")]
fn test_multi_lender_flag_persists() {
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

    // Read multiple times to ensure flag persists
    let inscription1 = stela.get_inscription(inscription_id);
    let inscription2 = stela.get_inscription(inscription_id);

    assert(inscription1.multi_lender == inscription2.multi_lender, 'flag persists');
    assert(inscription1.multi_lender, 'is multi-lender');

    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp_global();
}

// ============================================================
//                    SHARE TRACKING TESTS
// ============================================================

#[test]
#[feature("deprecated-starknet-consts")]
fn test_issued_debt_percentage_initial() {
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
    // Initially no debt has been issued
    assert(inscription.issued_debt_percentage == 0, 'start at 0%');

    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp_global();
}

#[test]
#[feature("deprecated-starknet-consts")]
fn test_share_conversion_multi_lender() {
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

    // Test share calculations at different percentages
    let shares_25 = stela.convert_to_shares(inscription_id, 2500); // 25%
    let shares_50 = stela.convert_to_shares(inscription_id, 5000); // 50%
    let shares_75 = stela.convert_to_shares(inscription_id, 7500); // 75%
    let shares_100 = stela.convert_to_shares(inscription_id, 10000); // 100%

    // Should be proportional
    assert(shares_50 > shares_25, '50% > 25%');
    assert(shares_75 > shares_50, '75% > 50%');
    assert(shares_100 > shares_75, '100% > 75%');

    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp_global();
}

// ============================================================
//                    VALIDATION TESTS
// ============================================================

// Note: Tests that call sign_inscription with stub NFT/registry addresses
// would fail because sign_inscription tries to call those contracts.
// The exceeds_max_bps check happens BEFORE NFT interaction, so it should work
// but the test below is commented out until full mock setup is implemented.

// Integration tests with sign_inscription require full mock contract setup
// and are not included in this basic test suite.

// ============================================================
//                    MULTI-LENDER SCENARIO TESTS
// ============================================================

#[test]
#[feature("deprecated-starknet-consts")]
fn test_large_debt_amount() {
    let (contract_address, stela) = deploy_stela();

    start_cheat_block_timestamp_global(1000);
    start_cheat_caller_address(contract_address, BORROWER());

    let debt_token = starknet::contract_address_const::<'DEBT'>();
    let collateral_token = starknet::contract_address_const::<'COL'>();
    let interest_token = starknet::contract_address_const::<'INT'>();

    // Large amounts to test overflow protection
    let params = create_multi_lender_borrow_params(
        debt_token,
        1000000000000000000000, // 1e21
        collateral_token,
        500000000000000000000, // 5e20
        interest_token,
        100000000000000000000, // 1e20
        86400,
        2000,
    );

    let inscription_id = stela.create_inscription(params);

    let inscription = stela.get_inscription(inscription_id);
    assert(inscription.multi_lender, 'handles large amounts');

    // Share calculations should still work
    let shares = stela.convert_to_shares(inscription_id, 5000); // 50%
    assert(shares > 0, 'calculates shares');

    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp_global();
}

#[test]
#[feature("deprecated-starknet-consts")]
fn test_multiple_inscriptions_independent() {
    let (contract_address, stela) = deploy_stela();

    start_cheat_block_timestamp_global(1000);
    start_cheat_caller_address(contract_address, BORROWER());

    let debt_token = starknet::contract_address_const::<'DEBT'>();
    let collateral_token = starknet::contract_address_const::<'COL'>();
    let interest_token = starknet::contract_address_const::<'INT'>();

    // Create two multi-lender inscriptions
    let params1 = create_multi_lender_borrow_params(
        debt_token, 10000, collateral_token, 5000, interest_token, 1000, 86400, 2000,
    );

    let params2 = create_multi_lender_borrow_params(
        debt_token, 20000, collateral_token, 10000, interest_token, 2000, 86400, 3000,
    );

    let inscription_id_1 = stela.create_inscription(params1);
    let inscription_id_2 = stela.create_inscription(params2);

    // Inscriptions should be independent
    assert(inscription_id_1 != inscription_id_2, 'different IDs');

    let inscription1 = stela.get_inscription(inscription_id_1);
    let inscription2 = stela.get_inscription(inscription_id_2);

    assert(inscription1.deadline == 2000, 'inscription1 deadline');
    assert(inscription2.deadline == 3000, 'inscription2 deadline');

    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp_global();
}
