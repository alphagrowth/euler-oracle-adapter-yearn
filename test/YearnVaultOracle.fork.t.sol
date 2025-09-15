// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.30;

import { Test, console2 } from "forge-std/Test.sol";
import { YearnVaultOracle } from "../src/YearnVaultOracle.sol";
import { IYearnVault } from "../src/interfaces/IYearnVault.sol";
import { IPriceOracle } from "../src/interfaces/IPriceOracle.sol";

contract YearnVaultOracleForkTest is Test {
    // Arbitrum mainnet addresses
    address constant YUSND = 0x252b965400862d94BDa35FeCF7Ee0f204a53Cc36;
    address constant USND = 0x4ecf61a6c2FaB8A047CEB3B3B263B401763e9D49;
    address constant USND_ORACLE = 0x3d0B9bb26F8837416040D39E932259FF2D4B4dD6;
    address constant USD = 0x0000000000000000000000000000000000000348;

    YearnVaultOracle public oracle;
    IYearnVault public yusndVault;
    IPriceOracle public usndOracle;

    uint256 arbitrumFork;

    function setUp() public {
        // Fork Arbitrum mainnet
        string memory rpcUrl = vm.envString("RPC_URL_ARBITRUM");
        arbitrumFork = vm.createFork(rpcUrl);
        vm.selectFork(arbitrumFork);

        // Set up interfaces
        yusndVault = IYearnVault(YUSND);
        usndOracle = IPriceOracle(USND_ORACLE);

        // Deploy the oracle (direct pricing, no USND oracle needed)
        oracle = new YearnVaultOracle(YUSND, USND, USD, 24 hours);

        console2.log("Oracle deployed at:", address(oracle));
        console2.log("Oracle name:", oracle.name());
    }

    function test_Fork_OracleDeployment() public view {
        assertEq(oracle.vault(), YUSND);
        assertEq(oracle.asset(), USND);
        assertEq(oracle.usd(), USD);
        assertEq(oracle.maxStaleness(), 24 hours);
    }

    function test_Fork_GetYUSNDPricePerShare() public view {
        uint256 pricePerShare = yusndVault.pricePerShare();
        console2.log("yUSND pricePerShare:", pricePerShare);
        assertGt(pricePerShare, 0);
        // Price per share should be >= 1e18 for Yearn vaults
        assertGe(pricePerShare, 1e18);
    }

    function test_Fork_GetUSNDToUSDPrice() public view {
        // Test USND oracle is working
        uint256 usndPrice = usndOracle.getQuote(1e18, USND, USD);
        console2.log("1 USND = USD:", usndPrice);
        assertGt(usndPrice, 0);
        // USND should be approximately $1 (within 10% range)
        assertGe(usndPrice, 0.9e18);
        assertLe(usndPrice, 1.1e18);
    }

    function test_Fork_GetQuote_YUSNDToUSD() public view {
        // Get price for 1 yUSND
        uint256 price = oracle.getQuote(1e18, YUSND, USD);
        console2.log("1 yUSND = USD:", price);

        // Verify price is reasonable
        assertGt(price, 0);

        // Since USND is 1:1 with USD, yUSND price should equal pricePerShare
        uint256 pricePerShare = yusndVault.pricePerShare();

        // Direct calculation check (no asset oracle needed)
        uint256 expectedUsd = (1e18 * pricePerShare) / 1e18;
        assertEq(price, expectedUsd);

        // yUSND should be worth approximately the same as USND (1:1 with USD) multiplied by pricePerShare
        // Verify it's at least 1 USD (assuming pricePerShare >= 1)
        assertGe(price, 1e18);
    }

    function test_Fork_GetQuote_USDToYUSND() public view {
        // Get how many yUSND tokens $100 can buy
        uint256 amount = oracle.getQuote(100e18, USD, YUSND);
        console2.log("$100 = yUSND:", amount);

        assertGt(amount, 0);

        // Verify bidirectional conversion
        uint256 usdBack = oracle.getQuote(amount, YUSND, USD);
        // Should get back approximately $100 (allowing for rounding)
        assertApproxEqRel(usdBack, 100e18, 1e15); // 0.1% tolerance
    }

    function test_Fork_GetQuotes_BidAskSpread() public view {
        // Test that bid and ask are the same (no spread)
        (uint256 bid1, uint256 ask1) = oracle.getQuotes(1e18, YUSND, USD);
        console2.log("1 yUSND bid = $", bid1);
        console2.log("1 yUSND ask = $", ask1);
        assertEq(bid1, ask1, "Bid and ask should be equal");

        (uint256 bid10, uint256 ask10) = oracle.getQuotes(10e18, YUSND, USD);
        console2.log("10 yUSND bid = $", bid10);
        console2.log("10 yUSND ask = $", ask10);
        assertEq(bid10, ask10, "Bid and ask should be equal");

        // Prices should scale linearly
        assertApproxEqRel(bid10, bid1 * 10, 1e12);
    }

    function test_Fork_LargeAmounts() public view {
        // Test with large amounts (1M yUSND)
        uint256 largeAmount = 1_000_000e18;
        uint256 price = oracle.getQuote(largeAmount, YUSND, USD);
        console2.log("1M yUSND = USD:", price);

        assertGt(price, 0);

        // Verify it scales correctly
        uint256 singlePrice = oracle.getQuote(1e18, YUSND, USD);
        assertApproxEqRel(price, singlePrice * 1_000_000, 1e12);
    }

    function test_Fork_SmallAmounts() public view {
        // Test with small amounts (0.001 yUSND)
        uint256 smallAmount = 1e15; // 0.001 tokens
        uint256 price = oracle.getQuote(smallAmount, YUSND, USD);
        console2.log("0.001 yUSND = USD:", price);

        assertGt(price, 0);
    }

    function test_Fork_CompareWithDirectCalculation() public view {
        uint256 testAmount = 50e18; // 50 yUSND

        // Get oracle price
        uint256 oraclePrice = oracle.getQuote(testAmount, YUSND, USD);

        // Calculate expected price manually
        // Since USND is 1:1 with USD, the price should be testAmount * pricePerShare / 1e18
        uint256 pricePerShare = yusndVault.pricePerShare();
        uint256 expectedPrice = (testAmount * pricePerShare) / 1e18;

        console2.log("Oracle price:", oraclePrice);
        console2.log("Expected price (testAmount * pricePerShare / 1e18):", expectedPrice);
        console2.log("Price per share:", pricePerShare);

        // Should match exactly since we're using direct calculation (no external oracle)
        assertEq(oraclePrice, expectedPrice);
    }

    function test_Fork_GasUsage() public view {
        uint256 gasBefore = gasleft();
        oracle.getQuote(1e18, YUSND, USD);
        uint256 gasUsed = gasBefore - gasleft();
        console2.log("Gas used for getQuote:", gasUsed);

        // Test getQuotes gas usage
        gasBefore = gasleft();
        oracle.getQuotes(1e18, YUSND, USD);
        gasUsed = gasBefore - gasleft();
        console2.log("Gas used for getQuotes:", gasUsed);

        // Test with larger amount
        gasBefore = gasleft();
        oracle.getQuotes(1000e18, YUSND, USD);
        gasUsed = gasBefore - gasleft();
        console2.log("Gas used for getQuotes (1000 tokens):", gasUsed);
    }

    function test_Fork_IntegrationWithEulerPriceOracle() public view {
        // Verify that the USND oracle implements IPriceOracle correctly
        string memory oracleName = usndOracle.name();
        console2.log("USND Oracle name:", oracleName);

        // Test both directions on USND oracle
        uint256 usndToUsd = usndOracle.getQuote(1e18, USND, USD);
        uint256 usdToUsnd = usndOracle.getQuote(1e18, USD, USND);

        console2.log("1 USND = USD:", usndToUsd);
        console2.log("1 USD = USND:", usdToUsnd);

        // They should be reciprocal (approximately)
        uint256 product = (usndToUsd * usdToUsnd) / 1e18;
        assertApproxEqRel(product, 1e18, 1e15); // 0.1% tolerance
    }
}
