# Zentra Airdrop Contract

## Overview
This Solidity smart contract implements an airdrop mechanism integrated with Aave for yield generation on supported stablecoins. Users can deposit tokens, which are supplied to Aave to earn yield, while maintaining control over their principal. The contract is non-upgradable, ensuring decentralization and preventing owner interference with user funds.

## Key Features
- **Supported Tokens**: Accepts mainstream stablecoins such as USDC and USDT.
- **Deposit and Yield Generation**: Users deposit tokens, which are automatically supplied to Aave for liquidity provision and yield farming.
- **Withdrawal Mechanics**: Users can withdraw their principal after an 8-hour cooldown period.
- **Yield Extraction**: The operator can withdraw accumulated yield tokens to the owner, but cannot access user principals.
- **Access Control**: Owner manages token additions and operator settings; operator controls deposits and yield withdrawals.

## How It Works
1. Owner adds supported tokens (e.g., USDC, USDT) to the contract.
2. Users deposit tokens, which are transferred to Aave via the proxy.
3. Yield is generated through Aave's interest-bearing mechanism.
4. After 8 hours, users can withdraw their original deposit amount.
5. Operator periodically extracts yield for the owner.

## Security Notes
- Non-upgradable design prevents changes to core logic.
- Relies on verified Aave proxy addresses for safe interactions.
- Users should verify token addresses and Aave configurations before depositing.

## Usage
Deploy with the appropriate Aave proxy address for your chain (e.g., Base, Optimism, Arbitrum, or Ethereum Mainnet).