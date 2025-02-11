# DN404 Liquidity Generator

A next-generation dual-nature token implementation combining NFT and ERC20 functionality with automated liquidity management and cross-token interactions.

## Overview

This project extends the DN404 standard (NFT + ERC20 dual-nature token) with advanced DeFi mechanics:

- 🔄 Automated bonding curve for initial token distribution
- 🌊 Self-deploying liquidity pools
- 💫 Cross-token liquidity generation for $CULT
- 🔒 Non-extractable contract-owned liquidity
- 💰 Smart transfer tax system

## Core Mechanics

### Bonding Curve Presale
- Dynamic pricing mechanism
- Automatic LP deployment trigger at threshold
- Fair distribution model

### Liquidity Management
- Auto-deployment of primary token LP
- Cross-token LP generation with $CULT
- Contract-owned, non-extractable liquidity
- Fee collection system for contract owner

### Technical Architecture
- Built on DN404 standard
- Foundry development framework
- Comprehensive testing suite

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

[Security details and audit information will go here]

## License

[License information]