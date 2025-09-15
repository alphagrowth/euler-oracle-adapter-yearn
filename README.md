# Yearn Vault Oracle Adapter

An oracle adapter for Yearn vaults with USD-pegged underlying assets. Reads the vault's pricePerShare and returns it as USD.

## What it does

`YearnVaultOracle` reads `pricePerShare()` from Yearn vaults where the underlying asset is pegged 1:1 to USD (like USND) and returns that value as the USD price.

- Reads `pricePerShare()` from the vault
- Returns it as USD price (no conversion needed since underlying is 1:1 with USD)
- Supports both vault→USD and USD→vault queries
- Handles tokens with different decimal places
- Implements Euler's IPriceOracle interface

## Repository Structure

```
├── src/
│   ├── YearnVaultOracle.sol              # Oracle for USD-pegged assets
│   ├── interfaces/
│   │   ├── IYearnVault.sol               # Yearn vault interface
│   │   └── IPriceOracle.sol              # Euler's oracle interface
│   └── utils/
│       ├── ScaleUtils.sol                # Decimal scaling utilities (Euler Labs)
│       └── Errors.sol                    # Custom error definitions
├── test/
│   ├── YearnVaultOracle.t.sol            # Unit tests
│   ├── YearnVaultOracle.fork.t.sol       # Integration tests
│   └── utils/                            # Utility tests
├── script/
│   └── [deployment scripts]               # Network-specific deployments
└── foundry.toml                          # Foundry configuration
```

## How It Works

### Price Calculation Flow

```
Yearn Vault Token (e.g., yUSND)
        ↓
    [pricePerShare]
        ↓
Underlying Asset (e.g., USND, assumed 1:1 with USD)
        ↓
      USD Price
```

### Decimal Scaling

The oracle uses ScaleUtils to handle tokens with different decimals:

- Vault tokens can have any number of decimals (6, 8, 18)
- Underlying assets can have different decimals than the vault
- USD is represented with 18 decimals (Euler standard)
- All conversions maintain precision through proper scaling

## Installation

```bash
# Clone the repository
git clone <repository-url>
cd yUSND-price-feed

# Install dependencies
forge install

# Build contracts
forge build
```

## Testing

```bash
# Run all tests
forge test

# Run with gas reporting
forge test --gas-report

# Run specific test suites
forge test --match-contract YearnVaultOracleTest
forge test --match-contract ScaleUtilsTest

# Fork testing (requires RPC URL)
forge test --fork-url <RPC_URL> --match-contract Fork
```

## Usage

### Deploying a New Oracle

Use when the underlying asset is pegged 1:1 to USD (like USND).

**Requirements**:
- Vault address (must implement `pricePerShare()` and `decimals()`)
- Underlying asset address (must be pegged to USD)
- Network's USD address (e.g., `0x0000000000000000000000000000000000000348` on Arbitrum)

**Deploy**:
```solidity
YearnVaultOracle oracle = new YearnVaultOracle(
    vault,        // Yearn vault address
    asset,        // Underlying asset address (USD-pegged)
    usd,          // USD token address
    maxStaleness  // Max age for price data (e.g., 24 hours)
);
```

### Integration

```solidity
// Get vault value in USD
uint256 usdValue = oracle.getQuote(vaultAmount, vault, usd);

// Get USD value in vault tokens
uint256 vaultAmount = oracle.getQuote(usdAmount, usd, vault);

// Get bid/ask (identical for Yearn vaults)
(uint256 bid, uint256 ask) = oracle.getQuotes(amount, vault, usd);
```

## Deployments

See the `script/` directory for network-specific deployment scripts and documentation:

- **Arbitrum**: yUSND/USD oracle deployment

Each deployment includes:
- Deployment script with hardcoded addresses
- Verification script to validate deployment
- Documentation with example commands

## Security Considerations

1. **Price Validation**: All prices are validated to be non-zero
2. **Staleness Protection**: Configurable maximum age for oracle data
3. **Overflow Protection**: Uses Solidity 0.8.30 with built-in checks
4. **Decimal Handling**: Proper scaling prevents precision loss
5. **Immutable Configuration**: Oracle parameters cannot be changed after deployment

## Development

```bash
# Format code
forge fmt

# Check formatting
forge fmt --check

# Coverage report
forge coverage

# Gas snapshots
forge snapshot
```

## Contributing

When adding support for a new Yearn vault:

1. Create deployment script in `script/` following the naming convention:
   `deploy-[VAULT]-[ASSET]-[NETWORK].s.sol`

2. Create verification script:
   `verify-[VAULT]-[ASSET]-[NETWORK].s.sol`

3. Add documentation:
   `README-[VAULT]-[ASSET]-[NETWORK].md`

4. Test thoroughly on fork before mainnet deployment

## Dependencies

- [Foundry](https://github.com/foundry-rs/foundry) - Development framework
- [Solady](https://github.com/Vectorized/solady) - Optimized Solidity libraries
- [forge-std](https://github.com/foundry-rs/forge-std) - Foundry standard library

## License

GPL-2.0-or-later

## Author

**AlphaGrowth**
Website: [https://alphagrowth.io](https://alphagrowth.io)

## Disclaimer

⚠️ **This code has not been audited. Use at your own risk.**

## Support

For questions or issues, please open an issue on GitHub.