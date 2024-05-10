# Truflation smart contracts

## Setup environment

### Development environment

Install foundry to build and run tests

### Local ENVs

1. Create .env file from .env.example
2. Set rpc urls, etherscan api key, and private key envs.

## Build

`forge build`

## Test

`forge test`

## Coverage

`forge coverage`

## Deploy Truf Vesting contract on ethereum

```bash
source .env

forge script script/ethereum/01_deploy_vesting.sol:DeployVesting --rpc-url $MAINNET_RPC_URL --chain mainnet --private-key $PRIVATE_KEY  --broadcast --verify -- --admin-address $ADMIN_ADDRESS --truf-token $TRUF_TOKEN
```
