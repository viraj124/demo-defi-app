// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/// @title DemoToken - a simple ERC-20 with a public faucet
/// @notice The faucet lets anyone mint 100 DEMO once per minute,
///         so demo users can get tokens without a real distribution.
contract DemoToken is ERC20, Ownable {
    uint256 public constant FAUCET_AMOUNT = 100e18;
    uint256 public constant FAUCET_COOLDOWN = 1 minutes;

    mapping(address => uint256) public lastFaucetClaim;
    /// @notice Addresses allowed to mint (the yield vault).
    mapping(address => bool) public isMinter;

    event FaucetClaimed(address indexed user, uint256 amount);
    event MinterSet(address indexed minter, bool allowed);

    constructor() ERC20("Demo Token", "DEMO") Ownable(msg.sender) {
        _mint(msg.sender, 1_000_000e18);
    }

    /// @notice Grant or revoke mint rights (used to let the vault mint yield).
    function setMinter(address minter, bool allowed) external onlyOwner {
        isMinter[minter] = allowed;
        emit MinterSet(minter, allowed);
    }

    /// @notice Mint tokens - only approved minters (the vault's yield stream).
    function mint(address to, uint256 amount) external {
        require(isMinter[msg.sender], "Mint: not a minter");
        _mint(to, amount);
    }

    /// @notice Mint yourself 100 DEMO. Rate-limited to once per minute.
    function faucet() external {
        require(
            block.timestamp >= lastFaucetClaim[msg.sender] + FAUCET_COOLDOWN,
            "Faucet: wait for cooldown"
        );
        lastFaucetClaim[msg.sender] = block.timestamp;
        _mint(msg.sender, FAUCET_AMOUNT);
        emit FaucetClaimed(msg.sender, FAUCET_AMOUNT);
    }
}
