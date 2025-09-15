# YearnVaultOracle Deployment Scripts

This directory contains deployment and verification scripts for the YearnVaultOracle contract.

## Prerequisites

1. Set up your environment variables in `.env`:
```bash
# Required for deployment
RPC_URL_ARBITRUM=https://arb-mainnet.g.alchemy.com/v2/YOUR_KEY
ETHERSCAN_API_KEY=your_arbiscan_api_key
ACCOUNT_NAME=your_account_name
```

Note: The deployment script uses hardcoded addresses for Arbitrum:
- Vault (yUSND): `0x252b965400862d94BDa35FeCF7Ee0f204a53Cc36`
- Asset (USND): `0x4ecf61a6c2FaB8A047CEB3B3B263B401763e9D49`
- USD: `0x0000000000000000000000000000000000000348`
- Max Staleness: 24 hours

2. Load environment variables:
```bash
source .env
```

## Deployment

### Deploy yUSND/USD Oracle on Arbitrum

Deploy the oracle for yUSND on Arbitrum:

```bash
forge script script/deploy-yUSND-USND-Arbitrum.s.sol \
    --rpc-url $RPC_URL_ARBITRUM \
    --account $ACCOUNT_NAME \
    --broadcast \
    --verify
```

## Verification

### Verify Deployed yUSND Oracle

After deployment, verify the yUSND oracle is working correctly:

```bash
ORACLE_ADDRESS=0xYourDeployedOracleAddress \
forge script script/verify-yUSND-USND-Arbitrum.s.sol \
    --rpc-url $RPC_URL_ARBITRUM
```

### Test Pricing

Test specific pricing scenarios:

```bash
forge script script/verify-yUSND-USND-Arbitrum.s.sol:VerifyYUSNDOracle \
    --sig "verifyPricing(address,uint256)" \
    $ORACLE_ADDRESS \
    1000000000000000000 \
    --rpc-url $RPC_URL_ARBITRUM
```

## Simulation

### Simulate Deployment

Test deployment without broadcasting:

```bash
forge script script/deploy-yUSND-USND-Arbitrum.s.sol \
    --rpc-url $RPC_URL_ARBITRUM \
    --account $ACCOUNT_NAME
```

### Fork Testing

Test deployment on a local fork:

```bash
# Start anvil fork
anvil --fork-url $RPC_URL_ARBITRUM

# In another terminal, deploy to fork
forge script script/deploy-yUSND-USND-Arbitrum.s.sol \
    --rpc-url http://localhost:8545 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    --broadcast
```

## Gas Estimation

Get gas estimates for deployment:

```bash
forge script script/deploy-yUSND-USND-Arbitrum.s.sol \
    --rpc-url $RPC_URL_ARBITRUM \
    --account $ACCOUNT_NAME \
    --estimate-gas
```

## Addresses (Arbitrum)

- **yUSND Vault**: 0x252b965400862d94BDa35FeCF7Ee0f204a53Cc36
- **USND Token**: 0x4ecf61a6c2FaB8A047CEB3B3B263B401763e9D49
- **USD (Euler)**: 0x0000000000000000000000000000000000000348

## Notes

- This deployment uses `YearnVaultOracle` since USND is pegged 1:1 with USD
- The oracle directly uses `pricePerShare()` without needing an external asset price oracle
- Default max staleness is 24 hours
- The oracle supports both vault→USD and USD→vault conversions
- Bid and ask prices are identical (no spread) for Yearn vaults