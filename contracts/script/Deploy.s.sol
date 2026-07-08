// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {DemoToken} from "../src/DemoToken.sol";
import {DemoVault} from "../src/DemoVault.sol";

/// @notice Deploys DemoToken + the ERC-4626 DemoVault, grants the vault
///         mint rights for its yield stream, and sets 1 DEMO/sec yield.
contract Deploy is Script {
    function run() external {
        vm.startBroadcast();

        DemoToken token = new DemoToken();
        DemoVault vault = new DemoVault(token);

        token.setMinter(address(vault), true);
        vault.setYieldRate(1e18); // vault yields 1 DEMO per second

        vm.stopBroadcast();

        console.log("DemoToken:  %s", address(token));
        console.log("DemoVault:  %s", address(vault));
    }
}
