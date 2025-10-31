// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.30;

import { Test, console2 } from "forge-std/Test.sol";
import { YearnVaultOracle } from "../src/YearnVaultOracle.sol";
import { IYearnVault } from "../src/interfaces/IYearnVault.sol";
import { IPriceOracle } from "../src/interfaces/IPriceOracle.sol";
import { Errors } from "../src/utils/Errors.sol";

contract MockYearnVault is IYearnVault {
    uint256 public pricePerShare;
    uint8 public decimals;
    address public underlyingAsset;

    constructor(uint256 _pricePerShare, uint8 _decimals) {
        pricePerShare = _pricePerShare;
        decimals = _decimals;
    }

    function setPricePerShare(uint256 _pricePerShare) external {
        pricePerShare = _pricePerShare;
    }

    function setUnderlyingAsset(address _asset) external {
        underlyingAsset = _asset;
    }

    function token() external view returns (address) {
        return underlyingAsset;
    }

    function symbol() external pure returns (string memory) {
        return "yTEST";
    }
}

// MockAssetOracle removed - no longer needed for direct pricing oracle

contract MockToken {
    uint8 public decimals;

    constructor(uint8 _decimals) {
        decimals = _decimals;
    }
}

contract MockBrokenDecimals {
    function decimals() external pure returns (uint8) {
        revert("Not implemented");
    }
    function pricePerShare() external pure returns (uint256) {
        return 1e18;
    }
    function symbol() external pure returns (string memory) {
        return "BROKEN";
    }
}

contract MockZeroDecimals is IYearnVault {
    function decimals() external pure returns (uint8) {
        return 0;
    }
    function pricePerShare() external pure returns (uint256) {
        return 1e18;
    }
    function symbol() external pure returns (string memory) {
        return "ZERO";
    }
}

contract MockExcessiveDecimals is IYearnVault {
    function decimals() external pure returns (uint8) {
        return 78; // Above max of 77
    }
    function pricePerShare() external pure returns (uint256) {
        return 1e18;
    }
    function symbol() external pure returns (string memory) {
        return "EXCESSIVE";
    }
}

contract MockERC4626Vault {
    uint256 public pricePerShare;
    uint8 public decimals;
    address public underlyingAsset;

    constructor(uint256 _pricePerShare, uint8 _decimals, address _asset) {
        pricePerShare = _pricePerShare;
        decimals = _decimals;
        underlyingAsset = _asset;
    }

    function asset() external view returns (address) {
        return underlyingAsset;
    }

    function symbol() external pure returns (string memory) {
        return "vTEST";
    }
}

contract MockVaultNoAssetMethod {
    uint256 public pricePerShare;
    uint8 public decimals;

    constructor(uint256 _pricePerShare, uint8 _decimals) {
        pricePerShare = _pricePerShare;
        decimals = _decimals;
    }

    function symbol() external pure returns (string memory) {
        return "nTEST";
    }
}

contract YearnVaultOracleTest is Test {
    YearnVaultOracle public oracle;
    MockYearnVault public vault;
    MockToken public asset;

    address constant MOCK_ASSET = address(0x1111);
    address constant USD = 0x0000000000000000000000000000000000000348;

    function setUp() public {
        // Deploy mock contracts
        vault = new MockYearnVault(1e18, 18); // 1:1 initial price, 18 decimals
        asset = new MockToken(18); // 18 decimals for asset

        // Set vault's underlying asset to match
        vault.setUnderlyingAsset(address(asset));

        // Deploy the oracle using the actual asset contract address
        oracle = new YearnVaultOracle(address(vault), address(asset), USD);
    }

    function test_Constructor() public view {
        assertEq(oracle.vault(), address(vault));
        assertEq(oracle.asset(), address(asset));
        assertEq(oracle.usd(), USD);
        assertEq(oracle.name(), "YearnVaultOracle yTEST/USD");
    }

    function test_Constructor_RevertZeroAddress() public {
        // Test zero vault
        vm.expectRevert(Errors.PriceOracle_InvalidConfiguration.selector);
        new YearnVaultOracle(address(0), address(asset), USD);

        // Test zero asset
        vm.expectRevert(Errors.PriceOracle_InvalidConfiguration.selector);
        new YearnVaultOracle(address(vault), address(0), USD);

        // Test zero USD
        vm.expectRevert(Errors.PriceOracle_InvalidConfiguration.selector);
        new YearnVaultOracle(address(vault), address(asset), address(0));
    }

    function test_Constructor_RevertBrokenDecimals() public {
        MockBrokenDecimals broken = new MockBrokenDecimals();
        vm.expectRevert(abi.encodeWithSelector(Errors.PriceOracle_DecimalsNotSupported.selector, address(broken)));
        new YearnVaultOracle(address(broken), address(asset), USD);
    }

    function test_Constructor_RevertZeroDecimals() public {
        MockZeroDecimals zeroDecimals = new MockZeroDecimals();
        vm.expectRevert(
            abi.encodeWithSelector(Errors.PriceOracle_DecimalsNotSupported.selector, address(zeroDecimals))
        );
        new YearnVaultOracle(address(zeroDecimals), address(asset), USD);
    }

    function test_Constructor_RevertExcessiveDecimals() public {
        MockExcessiveDecimals excessiveDecimals = new MockExcessiveDecimals();
        vm.expectRevert(
            abi.encodeWithSelector(Errors.PriceOracle_DecimalsNotSupported.selector, address(excessiveDecimals))
        );
        new YearnVaultOracle(address(excessiveDecimals), address(asset), USD);
    }

    function test_Constructor_RevertAssetBrokenDecimals() public {
        MockBrokenDecimals brokenAsset = new MockBrokenDecimals();
        vm.expectRevert(
            abi.encodeWithSelector(Errors.PriceOracle_DecimalsNotSupported.selector, address(brokenAsset))
        );
        new YearnVaultOracle(address(vault), address(brokenAsset), USD);
    }

    function test_Constructor_RevertVaultAssetMismatch() public {
        // Create a vault with correct asset set
        MockYearnVault vaultWithAsset = new MockYearnVault(1e18, 18);
        vaultWithAsset.setUnderlyingAsset(address(asset));

        // Create a different asset
        MockToken wrongAsset = new MockToken(18);

        // Should revert when provided asset doesn't match vault's asset
        vm.expectRevert(
            abi.encodeWithSelector(Errors.PriceOracle_VaultAssetMismatch.selector, address(asset), address(wrongAsset))
        );
        new YearnVaultOracle(address(vaultWithAsset), address(wrongAsset), USD);
    }

    function test_Constructor_ERC4626VaultSuccess() public {
        // Create ERC4626-style vault with matching asset
        MockERC4626Vault erc4626Vault = new MockERC4626Vault(1e18, 18, address(asset));

        // Should succeed when asset matches
        YearnVaultOracle newOracle = new YearnVaultOracle(address(erc4626Vault), address(asset), USD);
        assertEq(newOracle.vault(), address(erc4626Vault));
        assertEq(newOracle.asset(), address(asset));
    }

    function test_Constructor_ERC4626VaultMismatch() public {
        MockToken wrongAsset = new MockToken(18);
        MockERC4626Vault erc4626Vault = new MockERC4626Vault(1e18, 18, address(asset));

        // Should revert when asset doesn't match
        vm.expectRevert(
            abi.encodeWithSelector(Errors.PriceOracle_VaultAssetMismatch.selector, address(asset), address(wrongAsset))
        );
        new YearnVaultOracle(address(erc4626Vault), address(wrongAsset), USD);
    }

    function test_Constructor_RevertCannotVerifyAsset() public {
        // Create vault without token() or asset() methods
        MockVaultNoAssetMethod vaultNoAsset = new MockVaultNoAssetMethod(1e18, 18);

        // Should revert when cannot verify asset
        vm.expectRevert(Errors.PriceOracle_CannotVerifyAsset.selector);
        new YearnVaultOracle(address(vaultNoAsset), address(asset), USD);
    }

    function test_GetQuote_VaultToUSD() public {
        // Set pricePerShare to 1.5 (1 vault = 1.5 asset)
        // Since asset is 1:1 with USD, 1 vault = 1.5 USD
        vault.setPricePerShare(1.5e18);

        // 10 vault tokens should equal 15 USD (10 * 1.5)
        uint256 result = oracle.getQuote(10e18, address(vault), USD);
        assertEq(result, 15e18);
    }

    function test_GetQuote_USDToVault() public {
        // Set pricePerShare to 1.5 (1 vault = 1.5 asset)
        // Since asset is 1:1 with USD, 1 vault = 1.5 USD
        vault.setPricePerShare(1.5e18);

        // 15 USD should equal 10 vault tokens (15 / 1.5)
        uint256 result = oracle.getQuote(15e18, USD, address(vault));
        assertEq(result, 10e18);
    }

    function test_GetQuote_RevertUnsupportedPair() public {
        address randomToken = address(0x1234);

        vm.expectRevert(abi.encodeWithSelector(Errors.PriceOracle_NotSupported.selector, randomToken, USD));
        oracle.getQuote(1e18, randomToken, USD);

        vm.expectRevert(abi.encodeWithSelector(Errors.PriceOracle_NotSupported.selector, address(vault), randomToken));
        oracle.getQuote(1e18, address(vault), randomToken);
    }

    function test_GetQuote_RevertZeroPricePerShare() public {
        vault.setPricePerShare(0);

        vm.expectRevert(Errors.PriceOracle_InvalidAnswer.selector);
        oracle.getQuote(1e18, address(vault), USD);
    }

    function test_GetQuotes_NoSpread() public {
        vault.setPricePerShare(1.5e18);

        // Test vault to USD
        (uint256 bidOut, uint256 askOut) = oracle.getQuotes(10e18, address(vault), USD);
        assertEq(bidOut, 15e18); // 10 * 1.5
        assertEq(askOut, 15e18); // Same as bid (no spread)
        assertEq(bidOut, askOut); // Verify no spread

        // Test USD to vault
        (bidOut, askOut) = oracle.getQuotes(15e18, USD, address(vault));
        assertEq(bidOut, 10e18); // 15 / 1.5
        assertEq(askOut, 10e18); // Same as bid (no spread)
    }

    function test_GetQuotes_RevertZeroPricePerShare() public {
        vault.setPricePerShare(0);

        vm.expectRevert(Errors.PriceOracle_InvalidAnswer.selector);
        oracle.getQuotes(1e18, address(vault), USD);
    }

    function test_GetQuotes_ConsistentWithGetQuote() public {
        vault.setPricePerShare(1.234e18);

        uint256 amount = 50e18;

        // Get single quote
        uint256 singleQuote = oracle.getQuote(amount, address(vault), USD);

        // Get quotes (bid/ask)
        (uint256 bid, uint256 ask) = oracle.getQuotes(amount, address(vault), USD);

        // Should all be equal
        assertEq(bid, singleQuote);
        assertEq(ask, singleQuote);
    }

    function testFuzz_GetQuote_VaultToUSD(uint256 amount, uint256 pricePerShare) public {
        // Bound inputs to reasonable ranges
        amount = bound(amount, 1, 1e30);
        pricePerShare = bound(pricePerShare, 1e10, 1e27); // 0.00000001 to 1 billion

        vault.setPricePerShare(pricePerShare);

        uint256 result = oracle.getQuote(amount, address(vault), USD);

        // Calculate expected result (direct conversion, asset = USD)
        uint256 expected = (amount * pricePerShare) / 1e18;

        // Allow for small rounding differences
        assertApproxEqRel(result, expected, 1e10); // 0.000001% tolerance
    }

    function testFuzz_GetQuote_Bidirectional(uint256 amount) public {
        // Bound input to reasonable range
        amount = bound(amount, 1e18, 1e27);

        // Set some non-trivial price
        vault.setPricePerShare(1.234e18);

        // Convert vault to USD
        uint256 usdAmount = oracle.getQuote(amount, address(vault), USD);

        // Convert back to vault
        uint256 vaultAmount = oracle.getQuote(usdAmount, USD, address(vault));

        // Should get back approximately the same amount (allowing for rounding)
        assertApproxEqRel(vaultAmount, amount, 1e12); // 0.0001% tolerance
    }
}

contract YearnVaultOracleDecimalsTest is Test {
    YearnVaultOracle public oracle;

    address constant MOCK_ASSET = address(0x1111);
    address constant USD = 0x0000000000000000000000000000000000000348;

    function test_DifferentDecimals_6DecimalVault() public {
        // Create vault with 6 decimals (like USDC)
        MockYearnVault vault6 = new MockYearnVault(1e6, 6); // 1:1 price, 6 decimals
        MockToken asset6 = new MockToken(6);

        // Set vault's underlying asset
        vault6.setUnderlyingAsset(address(asset6));

        oracle = new YearnVaultOracle(address(vault6), address(asset6), USD);

        // Set price per share
        vault6.setPricePerShare(1.5e6); // 1.5 in 6 decimals

        // 10 vault tokens (10e6) should equal 15 USD (15e18)
        // Since asset is 1:1 with USD
        uint256 result = oracle.getQuote(10e6, address(vault6), USD);
        assertEq(result, 15e18);
    }

    function test_DifferentDecimals_8DecimalVault() public {
        // Create vault with 8 decimals (like WBTC)
        MockYearnVault vault8 = new MockYearnVault(1e8, 8);
        MockToken asset8 = new MockToken(8);

        // Set vault's underlying asset
        vault8.setUnderlyingAsset(address(asset8));

        oracle = new YearnVaultOracle(address(vault8), address(asset8), USD);

        // Set price per share
        vault8.setPricePerShare(2e8); // 2.0 in 8 decimals

        // 1 vault token (1e8) should equal 2 USD
        // Since asset is 1:1 with USD
        uint256 result = oracle.getQuote(1e8, address(vault8), USD);
        assertEq(result, 2e18);
    }
}
