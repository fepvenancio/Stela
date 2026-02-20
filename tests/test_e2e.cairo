// End-to-end integration tests for the full inscription lifecycle.
// These tests use deploy_full_setup() with real mock contracts.

use core::num::traits::Zero;
use openzeppelin_interfaces::erc1155::{IERC1155Dispatcher, IERC1155DispatcherTrait};
use snforge_std::{
    start_cheat_block_timestamp_global, start_cheat_caller_address, stop_cheat_block_timestamp_global,
    stop_cheat_caller_address,
};
use stela::interfaces::istela::IStelaProtocolDispatcherTrait;
use stela::types::inscription::InscriptionParams;
use stela::utils::share_math::MAX_BPS;
use super::mocks::mock_erc20::IMockERC20DispatcherTrait;
use super::test_utils::{
    BORROWER, LENDER, LENDER_2, create_borrow_params_from_setup, create_erc20_asset,
    create_multi_lender_params_from_setup, deploy_full_setup, setup_borrower_for_repayment,
    setup_borrower_with_collateral, setup_lender_with_debt,
};

/// Helper: get ERC1155 share balance via separate dispatcher.
/// Stela contract IS an ERC1155, so we dispatch on the same address.
fn get_shares(stela_address: starknet::ContractAddress, account: starknet::ContractAddress, token_id: u256) -> u256 {
    let erc1155 = IERC1155Dispatcher { contract_address: stela_address };
    erc1155.balance_of(account, token_id)
}

// ============================================================
//         LIFECYCLE: CREATE → SIGN → REPAY → REDEEM
// ============================================================

#[test]
#[feature("deprecated-starknet-consts")]
fn test_full_lifecycle_repay() {
    let setup = deploy_full_setup();
    let stela = setup.stela;
    let stela_address = setup.stela_address;

    let debt_amount: u256 = 1000;
    let collateral_amount: u256 = 500;
    let interest_amount: u256 = 100;
    let duration: u64 = 86400;
    let deadline: u64 = 2000;

    // === Setup token balances ===
    setup_borrower_with_collateral(@setup, BORROWER(), collateral_amount);
    setup_lender_with_debt(@setup, LENDER(), debt_amount);

    // === 1. Create inscription (borrower) ===
    start_cheat_block_timestamp_global(1000);
    start_cheat_caller_address(stela_address, BORROWER());

    let params = create_borrow_params_from_setup(
        @setup, debt_amount, collateral_amount, interest_amount, duration, deadline,
    );
    let inscription_id = stela.create_inscription(params);
    stop_cheat_caller_address(stela_address);

    // Verify: inscription created
    let inscription = stela.get_inscription(inscription_id);
    assert(inscription.borrower == BORROWER(), 'borrower set');
    assert(inscription.issued_debt_percentage == 0, 'no debt issued yet');

    // === 2. Sign inscription (lender fills 100%) ===
    start_cheat_caller_address(stela_address, LENDER());
    stela.sign_inscription(inscription_id, MAX_BPS);
    stop_cheat_caller_address(stela_address);

    let inscription = stela.get_inscription(inscription_id);
    assert(inscription.issued_debt_percentage == MAX_BPS, '100% issued');
    assert(inscription.signed_at == 1000, 'signed_at set');
    assert(inscription.lender == LENDER(), 'lender set');

    // Verify token movements
    assert(setup.debt_token.balance_of(BORROWER()) == debt_amount, 'borrower got debt');
    assert(setup.collateral_token.balance_of(BORROWER()) == 0, 'collateral locked');

    let lender_shares = get_shares(stela_address, LENDER(), inscription_id);
    assert(lender_shares > 0, 'lender has shares');

    let locker = stela.get_locker(inscription_id);
    assert(!locker.is_zero(), 'locker created');

    // === 3. Repay (within window) ===
    setup_borrower_for_repayment(@setup, BORROWER(), debt_amount, interest_amount);

    stop_cheat_block_timestamp_global();
    start_cheat_block_timestamp_global(50000);

    start_cheat_caller_address(stela_address, BORROWER());
    stela.repay(inscription_id);
    stop_cheat_caller_address(stela_address);

    let inscription = stela.get_inscription(inscription_id);
    assert(inscription.is_repaid, 'is repaid');
    assert(!inscription.liquidated, 'not liquidated');

    // === 4. Redeem (lender claims debt + interest) ===
    start_cheat_caller_address(stela_address, LENDER());
    stela.redeem(inscription_id, lender_shares);
    stop_cheat_caller_address(stela_address);

    assert(setup.debt_token.balance_of(LENDER()) > 0, 'lender got debt back');
    assert(setup.interest_token.balance_of(LENDER()) > 0, 'lender got interest');
    assert(get_shares(stela_address, LENDER(), inscription_id) == 0, 'shares burned');

    stop_cheat_block_timestamp_global();
}

// ============================================================
//       LIFECYCLE: CREATE → SIGN → LIQUIDATE → REDEEM
// ============================================================

#[test]
#[feature("deprecated-starknet-consts")]
fn test_full_lifecycle_liquidate() {
    let setup = deploy_full_setup();
    let stela = setup.stela;
    let stela_address = setup.stela_address;

    setup_borrower_with_collateral(@setup, BORROWER(), 500);
    setup_lender_with_debt(@setup, LENDER(), 1000);

    start_cheat_block_timestamp_global(1000);
    start_cheat_caller_address(stela_address, BORROWER());
    let params = create_borrow_params_from_setup(@setup, 1000, 500, 100, 86400, 2000);
    let inscription_id = stela.create_inscription(params);
    stop_cheat_caller_address(stela_address);

    start_cheat_caller_address(stela_address, LENDER());
    stela.sign_inscription(inscription_id, MAX_BPS);
    stop_cheat_caller_address(stela_address);

    let lender_shares = get_shares(stela_address, LENDER(), inscription_id);

    // Advance past due_to (signed_at=1000, duration=86400)
    stop_cheat_block_timestamp_global();
    start_cheat_block_timestamp_global(1000 + 86400 + 1);

    start_cheat_caller_address(stela_address, LENDER());
    stela.liquidate(inscription_id);
    stop_cheat_caller_address(stela_address);

    let inscription = stela.get_inscription(inscription_id);
    assert(inscription.liquidated, 'is liquidated');
    assert(!inscription.is_repaid, 'not repaid');

    // Redeem — lender gets collateral
    start_cheat_caller_address(stela_address, LENDER());
    stela.redeem(inscription_id, lender_shares);
    stop_cheat_caller_address(stela_address);

    assert(setup.collateral_token.balance_of(LENDER()) > 0, 'lender got collateral');

    stop_cheat_block_timestamp_global();
}

// ============================================================
//            TIMING ENFORCEMENT
// ============================================================

/// In #[should_panic] tests we avoid @setup references because TestSetup
/// doesn't implement Drop/PanicDestruct. All setup is done inline.

#[test]
#[feature("deprecated-starknet-consts")]
#[should_panic(expected: 'STELA: repay window closed')]
fn test_repay_after_window_fails() {
    let setup = deploy_full_setup();
    let stela = setup.stela;
    let stela_address = setup.stela_address;
    let debt_token = setup.debt_token;
    let debt_token_address = setup.debt_token_address;
    let collateral_token = setup.collateral_token;
    let collateral_token_address = setup.collateral_token_address;
    let interest_token = setup.interest_token;
    let interest_token_address = setup.interest_token_address;

    // Setup balances inline
    collateral_token.mint(BORROWER(), 500);
    start_cheat_caller_address(collateral_token_address, BORROWER());
    collateral_token.approve(stela_address, 500);
    stop_cheat_caller_address(collateral_token_address);

    debt_token.mint(LENDER(), 1000);
    start_cheat_caller_address(debt_token_address, LENDER());
    debt_token.approve(stela_address, 1000);
    stop_cheat_caller_address(debt_token_address);

    start_cheat_block_timestamp_global(1000);

    // Create — inline params (no @setup)
    start_cheat_caller_address(stela_address, BORROWER());
    let params = InscriptionParams {
        is_borrow: true,
        debt_assets: array![create_erc20_asset(debt_token_address, 1000)],
        interest_assets: array![create_erc20_asset(interest_token_address, 100)],
        collateral_assets: array![create_erc20_asset(collateral_token_address, 500)],
        duration: 86400,
        deadline: 2000,
        multi_lender: false,
    };
    let inscription_id = stela.create_inscription(params);
    stop_cheat_caller_address(stela_address);

    // Sign
    start_cheat_caller_address(stela_address, LENDER());
    stela.sign_inscription(inscription_id, MAX_BPS);
    stop_cheat_caller_address(stela_address);

    // Setup repayment tokens
    debt_token.mint(BORROWER(), 1000);
    interest_token.mint(BORROWER(), 100);
    start_cheat_caller_address(debt_token_address, BORROWER());
    debt_token.approve(stela_address, 1000);
    stop_cheat_caller_address(debt_token_address);
    start_cheat_caller_address(interest_token_address, BORROWER());
    interest_token.approve(stela_address, 100);
    stop_cheat_caller_address(interest_token_address);

    // Advance past repay window
    stop_cheat_block_timestamp_global();
    start_cheat_block_timestamp_global(87401);

    start_cheat_caller_address(stela_address, BORROWER());
    stela.repay(inscription_id); // Should panic
}

#[test]
#[feature("deprecated-starknet-consts")]
#[should_panic(expected: 'STELA: not yet liquidatable')]
fn test_liquidate_before_expiry_fails() {
    let setup = deploy_full_setup();
    let stela = setup.stela;
    let stela_address = setup.stela_address;
    let collateral_token = setup.collateral_token;
    let collateral_token_address = setup.collateral_token_address;
    let debt_token = setup.debt_token;
    let debt_token_address = setup.debt_token_address;
    let interest_token_address = setup.interest_token_address;

    collateral_token.mint(BORROWER(), 500);
    start_cheat_caller_address(collateral_token_address, BORROWER());
    collateral_token.approve(stela_address, 500);
    stop_cheat_caller_address(collateral_token_address);

    debt_token.mint(LENDER(), 1000);
    start_cheat_caller_address(debt_token_address, LENDER());
    debt_token.approve(stela_address, 1000);
    stop_cheat_caller_address(debt_token_address);

    start_cheat_block_timestamp_global(1000);

    // Create — inline params (no @setup)
    start_cheat_caller_address(stela_address, BORROWER());
    let params = InscriptionParams {
        is_borrow: true,
        debt_assets: array![create_erc20_asset(debt_token_address, 1000)],
        interest_assets: array![create_erc20_asset(interest_token_address, 100)],
        collateral_assets: array![create_erc20_asset(collateral_token_address, 500)],
        duration: 86400,
        deadline: 2000,
        multi_lender: false,
    };
    let inscription_id = stela.create_inscription(params);
    stop_cheat_caller_address(stela_address);

    start_cheat_caller_address(stela_address, LENDER());
    stela.sign_inscription(inscription_id, MAX_BPS);
    stop_cheat_caller_address(stela_address);

    // Try to liquidate before duration expires
    stop_cheat_block_timestamp_global();
    start_cheat_block_timestamp_global(50000); // Before 1000 + 86400

    start_cheat_caller_address(stela_address, LENDER());
    stela.liquidate(inscription_id); // Should panic
}

// ============================================================
//            CANCELLATION
// ============================================================

#[test]
#[feature("deprecated-starknet-consts")]
fn test_cancel_unfilled_inscription() {
    let setup = deploy_full_setup();
    let stela = setup.stela;
    let stela_address = setup.stela_address;

    start_cheat_block_timestamp_global(1000);
    start_cheat_caller_address(stela_address, BORROWER());

    let params = create_borrow_params_from_setup(@setup, 1000, 500, 100, 86400, 2000);
    let inscription_id = stela.create_inscription(params);

    stela.cancel_inscription(inscription_id);
    stop_cheat_caller_address(stela_address);

    let inscription = stela.get_inscription(inscription_id);
    assert(inscription.borrower.is_zero(), 'borrower cleared');
    assert(inscription.lender.is_zero(), 'lender cleared');
    assert(inscription.duration == 0, 'duration cleared');

    stop_cheat_block_timestamp_global();
}

#[test]
#[feature("deprecated-starknet-consts")]
#[should_panic(expected: 'STELA: not creator')]
fn test_cancel_by_non_creator_fails() {
    let setup = deploy_full_setup();
    let stela = setup.stela;
    let stela_address = setup.stela_address;
    let debt_token_address = setup.debt_token_address;
    let collateral_token_address = setup.collateral_token_address;
    let interest_token_address = setup.interest_token_address;

    start_cheat_block_timestamp_global(1000);

    // Create — inline params (no @setup)
    start_cheat_caller_address(stela_address, BORROWER());
    let params = InscriptionParams {
        is_borrow: true,
        debt_assets: array![create_erc20_asset(debt_token_address, 1000)],
        interest_assets: array![create_erc20_asset(interest_token_address, 100)],
        collateral_assets: array![create_erc20_asset(collateral_token_address, 500)],
        duration: 86400,
        deadline: 2000,
        multi_lender: false,
    };
    let inscription_id = stela.create_inscription(params);
    stop_cheat_caller_address(stela_address);

    // Lender tries to cancel — should fail
    start_cheat_caller_address(stela_address, LENDER());
    stela.cancel_inscription(inscription_id); // Should panic
}

// ============================================================
//            MULTI-LENDER: TWO LENDERS FILL + REDEEM
// ============================================================

#[test]
#[feature("deprecated-starknet-consts")]
fn test_multi_lender_two_fills_and_redeem() {
    let setup = deploy_full_setup();
    let stela = setup.stela;
    let stela_address = setup.stela_address;

    let debt_amount: u256 = 10000;
    let collateral_amount: u256 = 5000;
    let interest_amount: u256 = 1000;

    setup_borrower_with_collateral(@setup, BORROWER(), collateral_amount);
    setup_lender_with_debt(@setup, LENDER(), 6000);
    setup_lender_with_debt(@setup, LENDER_2(), 4000);

    start_cheat_block_timestamp_global(1000);
    start_cheat_caller_address(stela_address, BORROWER());
    let params = create_multi_lender_params_from_setup(
        @setup, debt_amount, collateral_amount, interest_amount, 86400, 2000,
    );
    let inscription_id = stela.create_inscription(params);
    stop_cheat_caller_address(stela_address);

    // Lender 1 fills 60%
    start_cheat_caller_address(stela_address, LENDER());
    stela.sign_inscription(inscription_id, 6000);
    stop_cheat_caller_address(stela_address);

    let lender1_shares = get_shares(stela_address, LENDER(), inscription_id);
    assert(lender1_shares > 0, 'lender1 has shares');

    let inscription = stela.get_inscription(inscription_id);
    assert(inscription.issued_debt_percentage == 6000, '60% issued');
    assert(inscription.lender == LENDER(), 'first lender stored');

    // Lender 2 fills 40%
    start_cheat_caller_address(stela_address, LENDER_2());
    stela.sign_inscription(inscription_id, 4000);
    stop_cheat_caller_address(stela_address);

    let lender2_shares = get_shares(stela_address, LENDER_2(), inscription_id);
    assert(lender2_shares > 0, 'lender2 has shares');

    // FIX VERIFICATION: lender field NOT overwritten by second fill
    let inscription = stela.get_inscription(inscription_id);
    assert(inscription.issued_debt_percentage == 10000, '100% issued');
    assert(inscription.lender == LENDER(), 'lender NOT overwritten');

    // Borrower repays
    setup_borrower_for_repayment(@setup, BORROWER(), debt_amount, interest_amount);

    stop_cheat_block_timestamp_global();
    start_cheat_block_timestamp_global(50000);

    start_cheat_caller_address(stela_address, BORROWER());
    stela.repay(inscription_id);
    stop_cheat_caller_address(stela_address);

    // Both lenders redeem
    start_cheat_caller_address(stela_address, LENDER());
    stela.redeem(inscription_id, lender1_shares);
    stop_cheat_caller_address(stela_address);

    start_cheat_caller_address(stela_address, LENDER_2());
    stela.redeem(inscription_id, lender2_shares);
    stop_cheat_caller_address(stela_address);

    // Verify proportional distribution
    let lender1_debt = setup.debt_token.balance_of(LENDER());
    let lender2_debt = setup.debt_token.balance_of(LENDER_2());
    assert(lender1_debt > 0, 'lender1 got debt');
    assert(lender2_debt > 0, 'lender2 got debt');
    assert(lender1_debt > lender2_debt, 'lender1 > lender2');

    stop_cheat_block_timestamp_global();
}
