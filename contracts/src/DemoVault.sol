// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {DemoToken} from "./DemoToken.sol";

/// @title DemoVault - an ERC-4626 tokenized yield vault
/// @notice Deposit DEMO, receive sDEMO *shares*. Yield streams into the
///         vault over time, so each share is redeemable for more and
///         more DEMO — the share price only goes up. No claim step:
///         yield auto-compounds into the share price.
///
/// ERC-4626 is the standard interface for yield vaults (Yearn, Aave's
/// wrapped tokens, Lido wrappers, ...). The mental model:
///
///   share price = totalAssets() / totalSupply()
///
///   deposit:  you give `assets`, mint  shares = assets / sharePrice
///   redeem:   you burn `shares`, get   assets = shares * sharePrice
///
/// Yield here is simulated: the vault mints `yieldRatePerSecond` DEMO
/// to itself, lazily, whenever someone interacts. `totalAssets()` is
/// overridden to include the not-yet-minted pending yield, so view
/// functions (and the frontend) see the share price tick up live.
contract DemoVault is ERC4626, Ownable {
    /// @notice DEMO minted to the vault per second (while it has depositors).
    uint256 public yieldRatePerSecond;
    /// @notice Last time pending yield was actually minted.
    uint256 public lastAccrual;

    event YieldAccrued(uint256 amount);
    event YieldRateUpdated(uint256 newRate);

    constructor(DemoToken asset_)
        ERC4626(IERC20(address(asset_)))
        ERC20("Staked DEMO", "sDEMO")
        Ownable(msg.sender)
    {
        lastAccrual = block.timestamp;
    }

    // ─────────────────────────── Views ───────────────────────────

    /// @notice Yield earned since the last accrual but not minted yet.
    /// @dev No yield accrues while the vault is empty — otherwise the
    ///      first depositor would instantly capture a backlog.
    function pendingYield() public view returns (uint256) {
        if (totalSupply() == 0) return 0;
        return (block.timestamp - lastAccrual) * yieldRatePerSecond;
    }

    /// @dev The single override that makes the whole vault "earn":
    ///      report held assets PLUS pending yield. Every ERC-4626
    ///      conversion (deposit/redeem/preview*) flows through this.
    function totalAssets() public view override returns (uint256) {
        return super.totalAssets() + pendingYield();
    }

    // ─────────────────────────── Accrual ──────────────────────────

    /// @notice Mint the pending yield into the vault. Called lazily
    ///         before any deposit/withdraw so accounting stays exact.
    function accrueYield() public {
        uint256 pending = pendingYield();
        lastAccrual = block.timestamp;
        if (pending > 0) {
            DemoToken(asset()).mint(address(this), pending);
            emit YieldAccrued(pending);
        }
    }

    /// @dev Hook into the two ERC-4626 state-changing paths. Shares are
    ///      priced with totalAssets() (which already counts pending
    ///      yield), so materializing it here keeps preview == actual.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal
        override
    {
        accrueYield();
        super._deposit(caller, receiver, assets, shares);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        accrueYield();
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    // ─────────────────────── Admin actions ───────────────────────

    /// @notice Set how much DEMO the vault yields per second.
    function setYieldRate(uint256 _rate) external onlyOwner {
        accrueYield(); // settle at the old rate first
        yieldRatePerSecond = _rate;
        emit YieldRateUpdated(_rate);
    }

    /// @dev Virtual-share offset: makes first-depositor share-price
    ///      inflation attacks unprofitable (OZ v5 built-in defense).
    function _decimalsOffset() internal pure override returns (uint8) {
        return 3;
    }
}
