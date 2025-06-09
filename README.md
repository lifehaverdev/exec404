# DN404 Liquidity Generator

A next-generation dual-nature token implementation combining NFT and ERC20 functionality with automated liquidity management, cross-token interactions, and innovative tokenomics.

## Overview

This project extends the DN404 standard (NFT + ERC20 dual-nature token) with advanced DeFi mechanics:

- 🔄 Automated bonding curve for initial token distribution
- 🌊 Self-deploying liquidity pools (V2 & V3)
- 💫 Cross-token liquidity generation for $CULT
- 🔒 Non-extractable contract-owned liquidity
- 💰 Smart transfer tax system
- 🎯 Tiered whitelist system

## Core Mechanics

### Bonding Curve Presale (Days 1-12)
- Dynamic pricing mechanism starting at 0.025 ETH per 10M tokens
- Cubic price growth formula for fair distribution
- Daily tiered whitelist system
- Automatic LP deployment trigger after 12 days

### Tokenomics
- Maximum supply: 4.44B tokens
- 4% tax on LP buys/sells:
- 4% tax on bonding curve sells
  - 3% to owner of miladystation #598
  - 1% reflected back to LP fund
- Tax proceeds auto-convert to $CULT V3 liquidity

### Liquidity Management
- Automated V2 liquidity deployment post-presale
- Contract-owned, non-extractable V3 concentrated liquidity for $CULT pairing
- Contract-owned, non-extractable V2 liquidity
- Smart rebalancing system for optimal liquidity depth
- Fee collection system for owner of miladystation #598

### NFT Features
- 1 NFT per 1M tokens
- Default skip-NFT setting for gas optimization
- Manual NFT minting via balanceMint function

## Development

```shell
# Install dependencies
forge install

# Build
forge build

# Test
forge test

# Deploy
forge script script/Deploy.s.sol:DeployScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

## Security

- All smart contract functions are internally tested
- Bonding curve calculations use fixed-point math library
- Reentrancy protection on critical functions
- Automated liquidity deployment safeguards
- [Audit information pending]

## Live Deployment & V1 Issues

The V1 contract is deployed on mainnet at `0x185485bF2e26e0Da48149aee0A8032c8c2060Db2`.

This initial version had two known issues that have been addressed in the latest source code:

1.  **Incorrect Whitelist Duration:** The presale whitelist tiers were configured to rotate every 12 hours instead of the intended 12 days.
2.  **Stuck Wankel Tax System:** A logical flaw in the tax processing system would cause it to become "clogged" when its ETH balance was between 0.01 and 0.02 ETH. This prevented the system from converting collected tax tokens into CULT liquidity as designed.

## License

VPL