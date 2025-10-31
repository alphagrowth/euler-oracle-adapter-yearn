// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.30;

/// @title IYearnVault
/// @author AlphaGrowth (https://www.alphagrowth.io/)
/// @notice Interface for Yearn vault contracts
interface IYearnVault {
    /// @notice Returns the amount of underlying tokens that 1 share represents
    /// @return The price per share in underlying token units (scaled by vault decimals)
    function pricePerShare() external view returns (uint256);

    /// @notice Returns the number of decimals the vault token uses
    /// @return The number of decimals (typically 18 for most Yearn vaults)
    function decimals() external view returns (uint8);

    /// @notice Returns the underlying token address (for Yearn V2 vaults)
    /// @return The address of the underlying token
    function token() external view returns (address);
}
