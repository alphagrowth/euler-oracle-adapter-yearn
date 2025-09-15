// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.30;

import { Script, console2 } from "forge-std/Script.sol";
import { YearnVaultOracle } from "../src/YearnVaultOracle.sol";
import { IYearnVault } from "../src/interfaces/IYearnVault.sol";
import { IPriceOracle } from "../src/interfaces/IPriceOracle.sol";

/// @title VerifyYUSNDOracle
/// @author AlphaGrowth (https://www.alphagrowth.io/)
/// @notice Verification script for deployed yUSND/USD direct oracle on Arbitrum
/// @dev Verifies YearnVaultOracle deployment with direct pricing (no asset translation)
contract VerifyYUSNDOracle is Script {
    // Expected configuration for yUSND on Arbitrum
    address constant EXPECTED_VAULT = 0x252b965400862d94BDa35FeCF7Ee0f204a53Cc36; // yUSND
    address constant EXPECTED_ASSET = 0x4ecf61a6c2FaB8A047CEB3B3B263B401763e9D49; // USND (pegged 1:1 to USD)
    address constant EXPECTED_USD = 0x0000000000000000000000000000000000000348; // USD

    function run() external view {
        // Get oracle address from environment variable
        address oracleAddress = vm.envAddress("ORACLE_ADDRESS");

        console2.log("========================================");
        console2.log("Verifying yUSND/USD Direct Oracle");
        console2.log("========================================");
        console2.log("Oracle Address:", oracleAddress);
        console2.log("");

        YearnVaultOracle oracle = YearnVaultOracle(oracleAddress);

        // Verify configuration
        console2.log("Configuration:");
        console2.log("  Oracle Name:", oracle.name());
        console2.log("  Vault:", oracle.vault());
        console2.log("  Asset:", oracle.asset());
        console2.log("  USD:", oracle.usd());
        console2.log("  Max Staleness:", oracle.maxStaleness());
        console2.log("");
        console2.log("Oracle Type: Direct Pricing");
        console2.log("  - No asset oracle translation required");
        console2.log("  - USND is pegged 1:1 with USD");
        console2.log("  - Gas-optimized implementation");

        // Verify addresses match expected values
        require(oracle.vault() == EXPECTED_VAULT, "Unexpected vault address");
        require(oracle.asset() == EXPECTED_ASSET, "Unexpected asset address");
        require(oracle.usd() == EXPECTED_USD, "Unexpected USD address");
        console2.log("");
        console2.log("[PASS] All addresses match expected configuration");

        // Test price conversions
        console2.log("");
        console2.log("========================================");
        console2.log("Price Tests");
        console2.log("========================================");

        // Test 1 vault token to USD
        try oracle.getQuote(1e18, oracle.vault(), oracle.usd()) returns (uint256 price) {
            console2.log("1 yUSND = USD:", price);
        } catch Error(string memory reason) {
            console2.log("[ERROR] vault->USD price:", reason);
        }

        // Test 100 USD to vault tokens
        try oracle.getQuote(100e18, oracle.usd(), oracle.vault()) returns (uint256 amount) {
            console2.log("100 USD = yUSND:", amount);
        } catch Error(string memory reason) {
            console2.log("[ERROR] USD->vault price:", reason);
        }

        // Test bid/ask quotes
        try oracle.getQuotes(1e18, oracle.vault(), oracle.usd()) returns (uint256 bid, uint256 ask) {
            console2.log("Bid/Ask spread check:");
            console2.log("  Bid:", bid);
            console2.log("  Ask:", ask);
            if (bid != ask) {
                console2.log("  [WARNING] Bid/ask spread detected!");
            } else {
                console2.log("  [PASS] No spread (bid = ask)");
            }
        } catch Error(string memory reason) {
            console2.log("[ERROR] bid/ask quotes:", reason);
        }

        // Get vault pricePerShare
        console2.log("");
        console2.log("========================================");
        console2.log("Vault Information");
        console2.log("========================================");

        IYearnVault vault = IYearnVault(oracle.vault());
        try vault.pricePerShare() returns (uint256 pricePerShare) {
            console2.log("Vault pricePerShare:", pricePerShare);
            console2.log("  This means 1 yUSND =", pricePerShare / 1e18, "USND");
        } catch {
            console2.log("[ERROR] Could not get vault pricePerShare");
        }

        console2.log("");
        console2.log("Direct Pricing Formula:");
        console2.log("  yUSND price in USD = pricePerShare * 1 (since USND = USD)");
        console2.log("  No external oracle calls needed!");

        console2.log("");
        console2.log("========================================");
        console2.log("Verification Complete!");
        console2.log("========================================");
    }

    function verifyPricing(address oracleAddress, uint256 testAmount) external view {
        YearnVaultOracle oracle = YearnVaultOracle(oracleAddress);
        IYearnVault vault = IYearnVault(oracle.vault());

        console2.log("========================================");
        console2.log("Pricing Verification");
        console2.log("========================================");
        console2.log("Test Amount:", testAmount / 1e18, "yUSND");
        console2.log("");

        // Get vault pricePerShare
        uint256 pricePerShare = vault.pricePerShare();
        console2.log("Vault pricePerShare:", pricePerShare);
        _logDecimal("  Human readable:", pricePerShare);
        console2.log("");

        // Get oracle price
        uint256 oraclePrice = oracle.getQuote(testAmount, oracle.vault(), oracle.usd());
        console2.log("Oracle price for", testAmount / 1e18, "yUSND:");
        console2.log("  Raw:", oraclePrice, "wei");
        _logDecimal("  Human readable:", oraclePrice);
        console2.log("");

        // Calculate expected price based on pricePerShare
        uint256 expectedPrice = (testAmount * pricePerShare) / 1e18;
        console2.log("Expected price (testAmount * pricePerShare / 1e18):");
        console2.log("  Raw:", expectedPrice, "wei");
        _logDecimal("  Human readable:", expectedPrice);
        console2.log("");

        // Verify oracle matches pricePerShare
        console2.log("Price Verification (yUSND -> USD):");
        if (oraclePrice == expectedPrice) {
            console2.log("  [PASS] Oracle price matches vault pricePerShare exactly");
        } else {
            uint256 diff = oraclePrice > expectedPrice ? oraclePrice - expectedPrice : expectedPrice - oraclePrice;
            uint256 bps = (diff * 1e18) / expectedPrice;
            console2.log("  Oracle price:", oraclePrice);
            console2.log("  Expected price:", expectedPrice);
            console2.log("  Difference:", bps / 1e14, "basis points");

            if (bps < 1e14) {
                console2.log("  [PASS] Acceptable rounding difference (< 0.01%)");
            } else {
                console2.log("  [ERROR] Oracle price does not match vault pricePerShare");
            }
        }

        // Test reverse direction: USD -> yUSND
        console2.log("");
        console2.log("========================================");
        console2.log("Reverse Direction Test (USD -> yUSND)");
        console2.log("========================================");

        uint256 usdTestAmount = 1e18;
        console2.log("Test Amount:", usdTestAmount / 1e18, "USD");
        console2.log("");

        uint256 yUSNDAmount = oracle.getQuote(usdTestAmount, oracle.usd(), oracle.vault());
        console2.log("Oracle price for", usdTestAmount / 1e18, "USD:");
        console2.log("  Raw:", yUSNDAmount, "wei");
        _logDecimal("  Human readable:", yUSNDAmount);
        console2.log("");

        // Expected: usdAmount / pricePerShare (in 18 decimals)
        uint256 expectedYUSND = (usdTestAmount * 1e18) / pricePerShare;
        console2.log("Expected amount (usdAmount * 1e18 / pricePerShare):");
        console2.log("  Raw:", expectedYUSND, "wei");
        _logDecimal("  Human readable:", expectedYUSND);
        console2.log("");

        console2.log("Price Verification (USD -> yUSND):");
        if (yUSNDAmount == expectedYUSND) {
            console2.log("  [PASS] Oracle price matches expected calculation exactly");
        } else {
            uint256 diff2 = yUSNDAmount > expectedYUSND ? yUSNDAmount - expectedYUSND : expectedYUSND - yUSNDAmount;
            uint256 bps2 = (diff2 * 1e18) / expectedYUSND;
            console2.log("  Oracle amount:", yUSNDAmount);
            console2.log("  Expected amount:", expectedYUSND);
            console2.log("  Difference:", bps2 / 1e14, "basis points");

            if (bps2 < 1e14) {
                console2.log("  [PASS] Acceptable rounding difference (< 0.01%)");
            } else {
                console2.log("  [ERROR] Oracle amount does not match expected calculation");
            }
        }

        console2.log("");
        console2.log("========================================");
        console2.log("Pricing Verification Complete!");
        console2.log("========================================");
    }

    /// @notice Helper to log a value in human-readable decimal format
    /// @param label The label to display
    /// @param value The value in wei (18 decimals)
    function _logDecimal(string memory label, uint256 value) private pure {
        uint256 integer = value / 1e18;
        uint256 decimals = value % 1e18;

        // Convert integer part to string
        string memory integerStr = vm.toString(integer);

        // Convert decimals to string with proper padding
        bytes memory decimalStr = new bytes(18);
        for (uint256 i = 18; i > 0; i--) {
            decimalStr[i - 1] = bytes1(uint8(48 + (decimals % 10)));
            decimals /= 10;
        }

        // Combine into single string
        string memory result = string(abi.encodePacked(integerStr, ".", string(decimalStr)));
        console2.log(label, result);
    }
}
