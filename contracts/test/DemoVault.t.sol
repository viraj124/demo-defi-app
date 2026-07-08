// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DemoToken} from "../src/DemoToken.sol";
import {DemoVault} from "../src/DemoVault.sol";

contract DemoVaultTest is Test {
    DemoToken token;
    DemoVault vault;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        // Foundry tests start at timestamp 1; warp to a realistic time so
        // the faucet cooldown math (`timestamp >= last + 60`) behaves.
        vm.warp(1_700_000_000);

        token = new DemoToken();
        vault = new DemoVault(token);

        // Let the vault mint its own yield, streaming 1 DEMO/sec.
        token.setMinter(address(vault), true);
        vault.setYieldRate(1e18);

        // Give users tokens via the faucet.
        vm.prank(alice);
        token.faucet();
        vm.prank(bob);
        token.faucet();
    }

    function _deposit(address user, uint256 assets) internal returns (uint256 shares) {
        vm.startPrank(user);
        token.approve(address(vault), assets);
        shares = vault.deposit(assets, user);
        vm.stopPrank();
    }

    function test_FaucetMintsAndEnforcesCooldown() public {
        assertEq(token.balanceOf(alice), 100e18);
        vm.prank(alice);
        vm.expectRevert("Faucet: wait for cooldown");
        token.faucet();

        vm.warp(block.timestamp + 61);
        vm.prank(alice);
        token.faucet();
        assertEq(token.balanceOf(alice), 200e18);
    }

    function test_DepositMintsSharesAtInitialPrice() public {
        uint256 shares = _deposit(alice, 100e18);
        // First deposit: share price is 1, so 100 DEMO ≈ 100 sDEMO
        // (scaled by the 10^3 virtual-share offset, normalized by decimals()).
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.convertToAssets(shares), 100e18);
        assertEq(vault.totalAssets(), 100e18);
    }

    function test_SharePriceGrowsWithYield() public {
        uint256 shares = _deposit(alice, 100e18);

        vm.warp(block.timestamp + 100); // +100 DEMO of yield at 1/sec

        // Same shares are now worth ~200 DEMO — the vault auto-compounds.
        assertEq(vault.totalAssets(), 200e18);
        assertApproxEqAbs(vault.convertToAssets(shares), 200e18, 1e6);

        vm.prank(alice);
        uint256 assetsOut = vault.redeem(shares, alice, alice);
        assertApproxEqAbs(assetsOut, 200e18, 1e6);
        assertApproxEqAbs(token.balanceOf(alice), 200e18, 1e6);
    }

    function test_YieldSplitsProRataByShares() public {
        uint256 aliceShares = _deposit(alice, 100e18);
        vm.warp(block.timestamp + 100); // alice alone: vault 100 → 200

        // Bob buys in at the CURRENT share price (~2 DEMO/share), so he
        // gets roughly half the shares alice got for the same assets.
        uint256 bobShares = _deposit(bob, 100e18);
        assertApproxEqRel(bobShares, aliceShares / 2, 0.001e18);

        vm.warp(block.timestamp + 90); // +90 yield split 2:1 → alice 60, bob 30

        assertApproxEqRel(vault.convertToAssets(aliceShares), 260e18, 0.001e18);
        assertApproxEqRel(vault.convertToAssets(bobShares), 130e18, 0.001e18);
    }

    function test_NoYieldAccruesWhileVaultIsEmpty() public {
        vm.warp(block.timestamp + 1000); // long idle period, zero depositors
        assertEq(vault.pendingYield(), 0);

        _deposit(alice, 100e18);
        // First depositor must NOT capture a 1000-second yield backlog.
        assertEq(vault.totalAssets(), 100e18);
    }

    function test_WithdrawExactAssets() public {
        _deposit(alice, 100e18);
        vm.warp(block.timestamp + 100); // position now worth ~200

        vm.prank(alice);
        vault.withdraw(150e18, alice, alice); // pull an exact asset amount
        assertEq(token.balanceOf(alice), 150e18);
        // ~50 DEMO of value stays in the vault as remaining shares.
        assertApproxEqAbs(vault.convertToAssets(vault.balanceOf(alice)), 50e18, 1e6);
    }

    function test_PreviewMatchesActualRedeem() public {
        uint256 shares = _deposit(alice, 100e18);
        vm.warp(block.timestamp + 42);

        // previewRedeem is a free view call, but it must equal what a
        // real redeem returns — pending yield included.
        uint256 previewed = vault.previewRedeem(shares);
        vm.prank(alice);
        uint256 actual = vault.redeem(shares, alice, alice);
        assertEq(actual, previewed);
    }

    function test_OnlyOwnerCanSetYieldRate() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setYieldRate(5e18);
    }

    function test_OnlyMinterCanMint() public {
        vm.prank(alice);
        vm.expectRevert("Mint: not a minter");
        token.mint(alice, 1e18);
    }

    function testFuzz_DepositRedeemRoundTrip(uint96 amount) public {
        amount = uint96(bound(amount, 1, 100e18));
        uint256 shares = _deposit(alice, amount);
        vm.prank(alice);
        uint256 assetsOut = vault.redeem(shares, alice, alice);
        // Instant round-trip: never profitable, loses at most rounding dust.
        assertLe(assetsOut, amount);
        assertApproxEqAbs(assetsOut, amount, 2);
    }
}
