// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.30;

/// @title Errors
/// @author AlphaGrowth (https://www.alphagrowth.io/)
/// @notice Library containing custom errors for the YearnVaultOracle system
library Errors {
    /// @notice Thrown when configuration parameters are invalid
    error PriceOracle_InvalidConfiguration();

    /// @notice Thrown when a price feed returns an invalid answer (zero or negative)
    error PriceOracle_InvalidAnswer();

    /// @notice Thrown when a price feed is too stale
    /// @param currentStaleness The current age of the price data
    /// @param maxStaleness The maximum allowed staleness
    error PriceOracle_TooStale(uint256 currentStaleness, uint256 maxStaleness);

    /// @notice Thrown when a requested token pair is not supported
    /// @param base The base token address
    /// @param quote The quote token address
    error PriceOracle_NotSupported(address base, address quote);

    /// @notice Thrown when scale calculation would overflow
    error PriceOracle_Overflow();

    /// @notice Thrown when a price feed returns zero for unit price in an inverse conversion
    error PriceOracle_ZeroPrice();

    /// @notice Thrown when trying to get decimals from a token that doesn't support it
    /// @param token The token address that doesn't support decimals
    error PriceOracle_DecimalsNotSupported(address token);

    /// @notice Thrown when vault's underlying asset doesn't match the provided asset
    /// @param vaultAsset The asset returned by the vault
    /// @param providedAsset The asset address provided to constructor
    error PriceOracle_VaultAssetMismatch(address vaultAsset, address providedAsset);

    /// @notice Thrown when cannot verify vault's underlying asset
    error PriceOracle_CannotVerifyAsset();
}