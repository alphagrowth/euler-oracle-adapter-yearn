# PR Implementation Plan - Security Audit Fixes

**Total Estimated Value**: $15,000
**Audit Report**: [SECURITY_AUDIT_REPORT.md](SECURITY_AUDIT_REPORT.md)
**Auditor**: SerenAI & Taariq Lewis
**Date**: October 31, 2025

---

## Completed

### ✅ PR #1: [HIGH-001] Remove Unused maxStaleness Parameter
**Branch**: `fix/high-001-remove-unused-maxStaleness`
**Status**: READY FOR REVIEW
**Value**: $1,600

**Changes**:
- Removed maxStaleness constants, validation, and parameter
- Updated all tests (unit + fork)
- Updated deployment scripts
- Added clear documentation that oracle relies on Yearn's freshness

**Files Modified**:
- `src/YearnVaultOracle.sol`
- `test/YearnVaultOracle.t.sol`
- `test/YearnVaultOracle.fork.t.sol`
- `script/deploy-yUSND-USND-Arbitrum.s.sol`

**Command to review**:
```bash
git checkout fix/high-001-remove-unused-maxStaleness
git diff master
```

---

## Ready to Implement

### PR #2: [MED-002] Fix Silent Decimal Fallback
**Branch**: `fix/med-002-fix-decimal-fallback`
**Status**: PARTIALLY STARTED
**Value**: $400
**Priority**: HIGH

**Implementation**:
```solidity
// In YearnVaultOracle.sol _getDecimals()
function _getDecimals(address token) private view returns (uint8 decimals) {
    // For USD special address, return 18 decimals
    if (token == address(0x0000000000000000000000000000000000000348)) {
        return 18;
    }

    // Try to call decimals() on the token
    try IYearnVault(token).decimals() returns (uint8 dec) {
        // Validate returned decimals are in reasonable range
        if (dec > 0 && dec <= 77) {
            return dec;
        }
        revert Errors.PriceOracle_DecimalsNotSupported(token);
    } catch {
        // Try standard ERC20 interface
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSignature("decimals()"));
        if (success && data.length == 32) {
            uint8 dec = abi.decode(data, (uint8));
            if (dec > 0 && dec <= 77) {
                return dec;
            }
        }
        // REVERT instead of defaulting to prevent 10^12 miscalculation
        revert Errors.PriceOracle_DecimalsNotSupported(token);
    }
}
```

**Tests Needed**:
```solidity
// test/YearnVaultOracle.t.sol
function test_Constructor_RevertDecimalsNotSupported() public {
    MockBrokenDecimals broken = new MockBrokenDecimals();
    vm.expectRevert(abi.encodeWithSelector(Errors.PriceOracle_DecimalsNotSupported.selector, address(broken)));
    new YearnVaultOracle(address(broken), address(asset), USD);
}

contract MockBrokenDecimals {
    function decimals() external pure returns (uint8) {
        revert("Not implemented");
    }
    function pricePerShare() external pure returns (uint256) { return 1e18; }
}
```

---

### PR #3: [MED-003] Add Vault/Asset Validation
**Branch**: `fix/med-003-vault-asset-validation`
**Status**: NOT STARTED
**Value**: $600
**Priority**: HIGH

**Implementation**:
```solidity
// Update IYearnVault.sol interface
interface IYearnVault {
    function pricePerShare() external view returns (uint256);
    function decimals() external view returns (uint8);
    function token() external view returns (address); // Add this
}

// In YearnVaultOracle.sol constructor (after line 47)
// NEW: Verify vault's underlying asset matches provided asset
try IYearnVault(_vault).token() returns (address vaultAsset) {
    if (vaultAsset != _asset) {
        revert Errors.PriceOracle_VaultAssetMismatch(vaultAsset, _asset);
    }
} catch {
    // If vault doesn't have token(), try asset()
    (bool success, bytes memory data) = _vault.staticcall(abi.encodeWithSignature("asset()"));
    if (success && data.length == 32) {
        address vaultAsset = abi.decode(data, (address));
        if (vaultAsset != _asset) {
            revert Errors.PriceOracle_VaultAssetMismatch(vaultAsset, _asset);
        }
    } else {
        // Cannot verify - revert to be safe
        revert Errors.PriceOracle_CannotVerifyAsset();
    }
}
```

**Add to Errors.sol**:
```solidity
error PriceOracle_VaultAssetMismatch(address vaultAsset, address providedAsset);
error PriceOracle_CannotVerifyAsset();
```

**Tests Needed**:
```solidity
function test_Constructor_RevertVaultAssetMismatch() public {
    MockToken wrongAsset = new MockToken(18);
    vm.expectRevert(); // Should revert with VaultAssetMismatch
    new YearnVaultOracle(address(vault), address(wrongAsset), USD);
}
```

---

### PR #4: [MED-001] Add USD Peg Circuit Breaker
**Branch**: `fix/med-001-usd-peg-circuit-breaker`
**Status**: NOT STARTED
**Value**: $2,400
**Priority**: MEDIUM-HIGH

**Implementation**:
```solidity
// In YearnVaultOracle.sol
contract YearnVaultOracle is IPriceOracle {
    // ... existing variables

    IPriceOracle public immutable assetOracle; // Oracle for underlying asset
    uint256 public constant MIN_PEG = 0.95e18; // 5% depeg threshold
    uint256 public constant MAX_PEG = 1.05e18;

    constructor(
        address _vault,
        address _asset,
        address _usd,
        address _assetOracle // NEW parameter
    ) {
        // ... existing validation

        require(_assetOracle != address(0), "Invalid asset oracle");
        assetOracle = IPriceOracle(_assetOracle);

        // Validate asset oracle works
        uint256 assetPrice = assetOracle.getQuote(1e18, _asset, _usd);
        require(assetPrice > 0, "Asset oracle not working");

        // ... rest of constructor
    }

    function getQuote(uint256 inAmount, address base, address quote)
        external
        view
        returns (uint256)
    {
        // Check asset peg FIRST
        uint256 assetPrice = assetOracle.getQuote(1e18, asset, usd);
        if (assetPrice < MIN_PEG || assetPrice > MAX_PEG) {
            revert Errors.PriceOracle_AssetDeppegged(assetPrice);
        }

        // ... rest of function
    }
}
```

**Add to Errors.sol**:
```solidity
error PriceOracle_AssetDeppegged(uint256 currentPrice);
```

**Tests Needed**:
```solidity
function test_GetQuote_RevertWhenDeppegged() public {
    MockAssetOracle depeggedOracle = new MockAssetOracle();
    depeggedOracle.setPrice(0.80e18); // Depegged to $0.80

    oracle = new YearnVaultOracle(
        address(vault),
        address(asset),
        USD,
        address(depeggedOracle)
    );

    vm.expectRevert();
    oracle.getQuote(1e18, address(vault), USD);
}
```

**Note**: This requires updating deployment scripts to include asset oracle parameter.

---

### PR #5: [MED-004] Fix Malicious Symbol Handling
**Branch**: `fix/med-004-malicious-symbol-handling`
**Status**: NOT STARTED
**Value**: $400
**Priority**: MEDIUM

**Implementation**:
```solidity
// In YearnVaultOracle.sol
function _getSymbol(address token) private view returns (string memory symbol) {
    // Try to call symbol() on the token
    (bool success, bytes memory data) = token.staticcall(abi.encodeWithSignature("symbol()"));

    // Validate response - max 128 bytes
    if (success && data.length > 0 && data.length <= 128) {
        try this._safeDecodeString(data) returns (string memory sym) {
            // Additional validation: check decoded string length
            if (bytes(sym).length > 0 && bytes(sym).length <= 32) {
                return sym;
            }
        } catch {
            // Decode failed, return default
        }
    }

    // Return default if symbol() fails or is invalid
    return "VAULT";
}

// Add public helper for try/catch
function _safeDecodeString(bytes memory data) public pure returns (string memory) {
    return abi.decode(data, (string));
}
```

**Tests Needed**:
```solidity
contract MaliciousVault {
    function symbol() external pure returns (bytes memory) {
        // Return huge data
        bytes memory huge = new bytes(1_000_000);
        return huge;
    }
    function decimals() external pure returns (uint8) { return 18; }
    function pricePerShare() external pure returns (uint256) { return 1e18; }
}

function test_Constructor_MaliciousSymbol() public {
    MaliciousVault malicious = new MaliciousVault();

    // Should not revert, should use default "VAULT" symbol
    YearnVaultOracle oracle = new YearnVaultOracle(
        address(malicious),
        address(asset),
        USD
    );

    assertEq(oracle.name(), "YearnVaultOracle VAULT/USD");
}
```

---

### PR #6: [MED-005] Add Emergency Pause Mechanism
**Branch**: `fix/med-005-emergency-pause`
**Status**: NOT STARTED
**Value**: $800
**Priority**: MEDIUM

**Implementation**:
```solidity
// In YearnVaultOracle.sol
contract YearnVaultOracle is IPriceOracle {
    // ... existing variables

    bool public paused;
    address public immutable governance;
    string public pauseReason;

    event Paused(string reason);
    event Unpaused();

    modifier whenNotPaused() {
        require(!paused, "Oracle paused");
        _;
    }

    constructor(
        address _vault,
        address _asset,
        address _usd,
        address _governance // NEW parameter
    ) {
        // ... existing validation

        require(_governance != address(0), "Invalid governance");
        governance = _governance;

        // ... rest of constructor
    }

    function pause(string calldata reason) external {
        require(msg.sender == governance, "Only governance");
        paused = true;
        pauseReason = reason;
        emit Paused(reason);
    }

    function unpause() external {
        require(msg.sender == governance, "Only governance");
        paused = false;
        pauseReason = "";
        emit Unpaused();
    }

    function getQuote(uint256 inAmount, address base, address quote)
        external
        view
        whenNotPaused  // Add modifier
        returns (uint256)
    {
        // ... existing function
    }

    function getQuotes(uint256 inAmount, address base, address quote)
        external
        view
        whenNotPaused  // Add modifier
        returns (uint256 bidOutAmount, uint256 askOutAmount)
    {
        // ... existing function
    }
}
```

**Tests Needed**:
```solidity
function test_Pause_OnlyGovernance() public {
    vm.prank(address(0x123)); // Not governance
    vm.expectRevert("Only governance");
    oracle.pause("Testing");
}

function test_Pause_BlocksGetQuote() public {
    address gov = address(this); // Test contract is governance
    oracle.pause("Emergency");

    vm.expectRevert("Oracle paused");
    oracle.getQuote(1e18, address(vault), USD);
}

function test_Unpause_Restores() public {
    oracle.pause("Testing");
    oracle.unpause();

    // Should work again
    uint256 price = oracle.getQuote(1e18, address(vault), USD);
    assertGt(price, 0);
}
```

**Note**: This requires updating deployment scripts and tests to include governance parameter.

---

### PR #7: Comprehensive Security Test Suite
**Branch**: `feat/comprehensive-security-tests`
**Status**: NOT STARTED
**Value**: $5,000
**Priority**: HIGH

**New Test Files Needed**:

#### 1. `test/security/MaliciousContractTests.t.sol`
```solidity
// Tests for malicious vault/token contracts
- test_MaliciousSymbol_HugeData()
- test_MaliciousSymbol_InvalidUTF8()
- test_MaliciousDecimals_Revert()
- test_MaliciousDecimals_OutOfRange()
- test_MaliciousPricePerShare_MaxUint()
- test_MaliciousPricePerShare_Zero()
```

#### 2. `test/security/DepegScenarios.t.sol`
```solidity
// Tests for USD peg breaking scenarios
- test_MinorDepeg_5Percent()
- test_MajorDepeg_50Percent()
- test_Repeg_PriceRecovery()
- test_FlashDepeg_Sandwich()
```

#### 3. `test/security/ExtremeValueTests.t.sol`
```solidity
// Tests for extreme values
- test_MaxUint256Amount()
- test_MaxUint256PricePerShare()
- test_MinimumAmount_1Wei()
- test_AllDecimalCombinations_Fuzz()
- test_OverflowProtection()
```

#### 4. `test/invariants/YearnVaultOracleInvariants.t.sol`
```solidity
// Foundry invariant tests
- invariant_BidirectionalConsistency()
- invariant_PriceNeverZero()
- invariant_LinearScaling()
- invariant_NoOverflow()
- invariant_PriceAlwaysPositive()
```

**Total Test Count**: 30+ new tests

---

### PR #8: Gas Optimizations
**Branch**: `optimize/gas-improvements`
**Status**: NOT STARTED
**Value**: $400
**Priority**: LOW

**Optimizations**:

1. **Fix external call in getQuotes()** (line 100):
```solidity
// Current (inefficient):
uint256 outAmount = this.getQuote(inAmount, base, quote);

// Optimized:
function getQuote(uint256 inAmount, address base, address quote)
    external
    view
    returns (uint256)
{
    return _getQuoteInternal(inAmount, base, quote);
}

function getQuotes(uint256 inAmount, address base, address quote)
    external
    view
    returns (uint256 bidOutAmount, uint256 askOutAmount)
{
    uint256 outAmount = _getQuoteInternal(inAmount, base, quote);
    return (outAmount, outAmount);
}

function _getQuoteInternal(uint256 inAmount, address base, address quote)
    private
    view
    returns (uint256)
{
    // Original getQuote logic here
}
```

**Gas Savings**: ~2,100 gas per getQuotes() call

---

## Additional Recommendations (Not in $15k Scope)

### Formal Verification
**Value**: $2,000-3,000
**Tools**: Certora, Halmos

- Verify decimal scaling mathematics
- Verify bidirectional conversion consistency
- Verify no overflow conditions

### Deployment Infrastructure
**Value**: $1,000-1,600

- Multi-network deployment scripts
- Automated verification
- Gas estimation tools
- Deployment checklist

### Documentation
**Value**: $800-1,200

- Integration guide for protocols
- Risk disclosure document
- Emergency response playbook
- Monitoring setup guide

---

## PR Merge Order

1. ✅ PR #1 (HIGH-001) - Remove maxStaleness [DONE]
2. PR #2 (MED-002) - Fix decimal fallback [HIGH PRIORITY]
3. PR #3 (MED-003) - Vault/asset validation [HIGH PRIORITY]
4. PR #7 - Security test suite [Can do in parallel]
5. PR #4 (MED-001) - USD peg circuit breaker [Requires design discussion]
6. PR #5 (MED-004) - Symbol handling
7. PR #6 (MED-005) - Emergency pause [Requires design discussion]
8. PR #8 - Gas optimizations

---

## Testing Checklist

Before merging each PR:
- [ ] `forge build` passes
- [ ] `forge test` passes (all tests)
- [ ] `forge test --gas-report` shows reasonable gas
- [ ] `forge fmt --check` passes
- [ ] Manual review of changed files
- [ ] Fork test against Arbitrum passes (if applicable)

---

## Notes for Implementation

1. **Foundry Config Issue**: There's a "Unknown evm version: paris" error in your environment. This needs to be fixed before running tests. Likely a submodule or version mismatch.

2. **Breaking Changes**: PRs #4, #6 change constructor signature. Need migration plan for existing deployments.

3. **Asset Oracle Dependency**: PR #4 requires an external asset oracle. Need to decide:
   - Use existing Chainlink/Band/etc
   - Create separate oracle for USND
   - Make it optional with feature flag

4. **Governance Address**: PR #6 requires governance address. Need to decide:
   - Use multisig
   - Use timelock
   - Use DAO

5. **Test Coverage Target**: Aim for >95% line coverage after PR #7.

---

## Total Value Breakdown

| PR | Description | Value |
|----|-------------|-------|
| 1 | Remove maxStaleness | $1,600 ✅ |
| 2 | Fix decimal fallback | $400 |
| 3 | Vault/asset validation | $600 |
| 4 | USD peg circuit breaker | $2,400 |
| 5 | Symbol handling | $400 |
| 6 | Emergency pause | $800 |
| 7 | Security test suite | $5,000 |
| 8 | Gas optimizations | $400 |
| | **TOTAL** | **$11,600** |

**To reach $15,000**: Add items from "Additional Recommendations" or increase test coverage scope.

---

## Contact

For questions or clarifications:
- Audit Report: [SECURITY_AUDIT_REPORT.md](SECURITY_AUDIT_REPORT.md)
- Branch: `fix/high-001-remove-unused-maxStaleness` (ready for review)
