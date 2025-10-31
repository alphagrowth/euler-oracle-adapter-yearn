// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.30;

import { IPriceOracle } from "./interfaces/IPriceOracle.sol";
import { IYearnVault } from "./interfaces/IYearnVault.sol";
import { ScaleUtils, Scale } from "./utils/ScaleUtils.sol";
import { Errors } from "./utils/Errors.sol";

/// @title YearnVaultOracle
/// @author AlphaGrowth (https://alphagrowth.io)
/// @notice Direct price oracle adapter for Yearn vault tokens with fixed-rate underlying assets
/// @dev Uses vault's pricePerShare directly without additional translation for assets pegged to USD
/// @dev WARNING: This oracle relies on Yearn vault's pricePerShare() for freshness. There is no staleness
///      check implemented. The oracle assumes Yearn vaults update their pricePerShare regularly.
contract YearnVaultOracle is IPriceOracle {
    /// @inheritdoc IPriceOracle
    string public name;

    /// @notice The address of the Yearn vault token
    address public immutable vault;
    /// @notice The address of the underlying asset token
    address public immutable asset;
    /// @notice The address representing USD in the system
    address public immutable usd;
    /// @notice The Yearn vault contract interface
    IYearnVault public immutable yearnVault;
    /// @notice The scale for decimal conversions
    Scale public immutable scale;

    /// @notice Deploy a YearnVaultOracle
    /// @param _vault The address of the Yearn vault token
    /// @param _asset The underlying asset of the vault (should be pegged to USD)
    /// @param _usd The address representing USD
    constructor(address _vault, address _asset, address _usd) {
        // Validate configuration
        if (_vault == address(0) || _asset == address(0) || _usd == address(0)) {
            revert Errors.PriceOracle_InvalidConfiguration();
        }

        // Verify vault's underlying asset matches provided asset
        // This prevents misconfiguration where wrong asset is specified
        try IYearnVault(_vault).token() returns (address vaultAsset) {
            if (vaultAsset != _asset) {
                revert Errors.PriceOracle_VaultAssetMismatch(vaultAsset, _asset);
            }
        } catch {
            // If vault doesn't have token(), try asset() method (ERC4626 style)
            (bool success, bytes memory data) = _vault.staticcall(abi.encodeWithSignature("asset()"));
            if (success && data.length == 32) {
                address vaultAsset = abi.decode(data, (address));
                if (vaultAsset != _asset) {
                    revert Errors.PriceOracle_VaultAssetMismatch(vaultAsset, _asset);
                }
            } else {
                // Cannot verify vault's asset - safer to revert than proceed with potentially wrong configuration
                revert Errors.PriceOracle_CannotVerifyAsset();
            }
        }

        // Set immutable state
        vault = _vault;
        asset = _asset;
        usd = _usd;
        yearnVault = IYearnVault(_vault);

        // Get decimals for all tokens
        uint8 vaultDecimals = _getDecimals(_vault);
        uint8 assetDecimals = _getDecimals(_asset);
        uint8 usdDecimals = _getDecimals(_usd);

        // pricePerShare returns the amount of asset tokens per vault token
        // Since asset (USND) is 1:1 with USD, pricePerShare directly gives us the USD value
        // The scale should convert between vault decimals and USD decimals, with pricePerShare in asset decimals
        scale = ScaleUtils.calcScale(vaultDecimals, usdDecimals, assetDecimals);

        // Set the oracle name
        string memory vaultSymbol = _getSymbol(_vault);
        name = string(abi.encodePacked("YearnVaultOracle ", vaultSymbol, "/USD"));
    }

    /// @inheritdoc IPriceOracle
    /// @notice Get the price quote for converting between vault and USD
    /// @dev Supports both vault/USD and USD/vault conversions. Assumes underlying asset is 1:1 with USD
    function getQuote(uint256 inAmount, address base, address quote) external view returns (uint256) {
        return _getQuoteInternal(inAmount, base, quote);
    }

    /// @inheritdoc IPriceOracle
    /// @notice Get bid and ask prices for a given amount
    /// @dev For Yearn vaults, bid and ask prices are the same (no spread)
    function getQuotes(
        uint256 inAmount,
        address base,
        address quote
    )
        external
        view
        returns (uint256 bidOutAmount, uint256 askOutAmount)
    {
        // For Yearn vaults, there's no spread - bid and ask are the same
        // Use internal function to avoid external call overhead (~2,100 gas savings)
        uint256 outAmount = _getQuoteInternal(inAmount, base, quote);
        return (outAmount, outAmount);
    }

    /// @notice Internal function to calculate price quote
    /// @param inAmount The amount of base tokens to convert
    /// @param base The base token address
    /// @param quote The quote token address
    /// @return The converted amount in quote tokens
    function _getQuoteInternal(uint256 inAmount, address base, address quote) private view returns (uint256) {
        // Determine direction
        bool inverse = ScaleUtils.getDirectionOrRevert(base, vault, quote, usd);

        // Get the price per share from the Yearn vault
        uint256 pricePerShare = yearnVault.pricePerShare();
        if (pricePerShare == 0) revert Errors.PriceOracle_InvalidAnswer();

        // Direct calculation without asset oracle translation
        // Since the underlying asset is pegged 1:1 to USD, we can directly use pricePerShare
        return ScaleUtils.calcOutAmount(inAmount, pricePerShare, scale, inverse);
    }

    /// @notice Helper to get token decimals
    /// @param token The token address
    /// @return decimals The token decimals
    function _getDecimals(address token) private view returns (uint8 decimals) {
        // For USD special address, return 18 decimals
        if (token == address(0x0000000000000000000000000000000000000348)) {
            return 18;
        }

        // Try to call decimals() on the token
        try IYearnVault(token).decimals() returns (uint8 dec) {
            // Validate decimals are in reasonable range (0 is invalid, 77 is max for 10**decimals to fit in uint256)
            if (dec == 0 || dec > 77) {
                revert Errors.PriceOracle_DecimalsNotSupported(token);
            }
            return dec;
        } catch {
            // If decimals() doesn't exist or fails, try standard ERC20 interface
            (bool success, bytes memory data) = token.staticcall(abi.encodeWithSignature("decimals()"));
            if (success && data.length == 32) {
                uint8 dec = abi.decode(data, (uint8));
                // Validate decimals are in reasonable range
                if (dec > 0 && dec <= 77) {
                    return dec;
                }
            }
            // REVERT instead of defaulting to prevent catastrophic miscalculation
            // A 6-decimal token (like USDC) defaulted to 18 would be valued 10^12 times higher
            revert Errors.PriceOracle_DecimalsNotSupported(token);
        }
    }

    /// @notice Helper to get token symbol
    /// @param token The token address
    /// @return symbol The token symbol
    function _getSymbol(address token) private view returns (string memory symbol) {
        // Try to call symbol() on the token
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSignature("symbol()"));

        // Validate response - max 128 bytes to prevent DOS from huge responses
        if (success && data.length > 0 && data.length <= 128) {
            try this._safeDecodeString(data) returns (string memory sym) {
                // Additional validation: check decoded string length (max 32 chars)
                // This prevents malicious contracts from returning extremely long strings
                if (bytes(sym).length > 0 && bytes(sym).length <= 32) {
                    return sym;
                }
            } catch {
                // Decode failed, fall through to default
            }
        }

        // Return default if symbol() fails or is invalid
        return "VAULT";
    }

    /// @notice Helper to safely decode string from bytes
    /// @dev Public function to allow try/catch usage in _getSymbol
    /// @param data The bytes data to decode
    /// @return The decoded string
    function _safeDecodeString(bytes memory data) public pure returns (string memory) {
        return abi.decode(data, (string));
    }
}
