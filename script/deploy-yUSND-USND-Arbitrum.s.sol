// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.30;

import { Script, console2 } from "forge-std/Script.sol";
import { YearnVaultOracle } from "../src/YearnVaultOracle.sol";

/// @title DeployYUSNDOracleDirect
/// @author AlphaGrowth (https://www.alphagrowth.io/)
/// @notice Deployment script for yUSND/USD direct oracle on Arbitrum
/// @dev Uses YearnVaultOracle for direct pricing (no asset translation needed since USND is 1:1 with USD)
contract DeployYUSNDOracleDirect is Script {
    // Configuration for yUSND on Arbitrum
    address constant VAULT = 0x252b965400862d94BDa35FeCF7Ee0f204a53Cc36; // yUSND
    address constant ASSET = 0x4ecf61a6c2FaB8A047CEB3B3B263B401763e9D49; // USND (pegged 1:1 to USD)
    address constant USD = 0x0000000000000000000000000000000000000348; // USD
    uint256 constant MAX_STALENESS = 24 hours;

    function run() external {
        console2.log("========================================");
        console2.log("Deploying yUSND/USD Direct Oracle on Arbitrum");
        console2.log("========================================");
        console2.log("Configuration:");
        console2.log("  Vault (yUSND):", VAULT);
        console2.log("  Asset (USND):", ASSET);
        console2.log("  USD:", USD);
        console2.log("  Max Staleness:", MAX_STALENESS);
        console2.log("");
        console2.log("Note: Using direct oracle since USND is pegged 1:1 with USD");
        console2.log("This saves gas by eliminating the need for asset price translation");

        vm.startBroadcast();

        YearnVaultOracle oracle = new YearnVaultOracle(VAULT, ASSET, USD, MAX_STALENESS);

        vm.stopBroadcast();

        console2.log("");
        console2.log("========================================");
        console2.log("Deployment Successful!");
        console2.log("========================================");
        console2.log("Oracle Address:", address(oracle));
        console2.log("Oracle Name:", oracle.name());
        console2.log("");
        console2.log("The oracle directly converts yUSND to USD using pricePerShare");
        console2.log("No external asset oracle calls are needed");
    }
}
