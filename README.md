# 🚀 Equivest - Startup Equity Vesting Smart Contract

A Clarity smart contract for managing startup equity vesting with milestone-based token unlocking on the Stacks blockchain.

## 📋 Overview

Equivest enables startups to create sophisticated equity vesting schedules where tokens are unlocked based on specific milestones rather than just time-based vesting. This provides more flexibility and alignment between equity distribution and company achievements.

## ✨ Features

- 🎯 **Milestone-Based Vesting**: Tokens unlock when specific milestones are completed
- ⏰ **Cliff Periods**: Set cliff periods before any tokens can be claimed
- 👑 **Owner Controls**: Contract owner can manage vesting schedules and milestones
- 🔒 **Revocation**: Ability to revoke vesting schedules if needed
- 📊 **Progress Tracking**: Real-time tracking of vesting progress and claimable amounts

## 🛠 Core Functions

### Owner Functions

#### `mint-tokens`
```clarity
(mint-tokens (amount uint))
```
Mint new equity tokens to the contract owner.

#### `create-vesting-schedule`
```clarity
(create-vesting-schedule (recipient principal) (total-amount uint) (cliff-blocks uint))
```
Create a new vesting schedule for a recipient with a cliff period.

#### `add-milestone`
```clarity
(add-milestone (recipient principal) (amount uint) (description (string-ascii 100)) (blocks-from-now uint))
```
Add a milestone that unlocks tokens when completed.

#### `complete-milestone`
```clarity
(complete-milestone (milestone-id uint))
```
Mark a milestone as completed and unlock the associated tokens.

#### `revoke-vesting`
```clarity
(revoke-vesting (recipient principal))
```
Revoke a vesting schedule, preventing further token claims.

### User Functions

#### `claim-vested-tokens`
```clarity
(claim-vested-tokens)
```
Claim tokens that have been vested through completed milestones.

## 📖 Read-Only Functions

- `get-vesting-schedule`: Get vesting details for a recipient
- `get-milestone`: Get milestone information by ID
- `get-token-balance`: Get token balance for an account
- `get-claimable-amount`: Get amount of tokens ready to claim
- `get-vesting-progress`: Get comprehensive vesting progress
- `is-milestone-eligible`: Check if a milestone can be completed

## 🚀 Usage Example

1. **Deploy Contract**: Deploy the Equivest contract to Stacks blockchain

2. **Mint Tokens**:
```clarity
(contract-call? .equivest mint-tokens u1000000)
```

3. **Create Vesting Schedule**:
```clarity
(contract-call? .equivest create-vesting-schedule 'SP1ABC...XYZ u100000 u1000)
```

4. **Add Milestones**:
```clarity
(contract-call? .equivest add-milestone 'SP1ABC...XYZ u25000 "Complete MVP" u500)
(contract-call? .equivest add-milestone 'SP1ABC...XYZ u25000 "First Customer" u1000)
```

5. **Complete Milestones**:
```clarity
(contract-call? .equivest complete-milestone u1)
```

6. **Claim Tokens** (as recipient):
```clarity
(contract-call? .equivest claim-vested-tokens)
```

## 🔧 Development

### Prerequisites
- Clarinet CLI installed
- Stacks wallet for testing

### Testing
```bash
clarinet test
```

### Deployment
```bash
clarinet deploy
```

## 📊 Contract Architecture

- **Fungible Token**: Custom equity token implementation
- **Vesting Schedules**: Maps recipient to vesting details
- **Milestones**: Individual achievement-based unlock conditions
- **Access Control**: Owner-only administrative functions

## 🛡 Security Features

- Owner-only administrative functions
- Input validation on all parameters
- Cliff period enforcement
- Vesting schedule validation
- Milestone completion verification

## 📝 Error Codes

- `u100`: Unauthorized access
- `u101`: Invalid amount
- `u102`: Insufficient balance
- `u103`: Vesting schedule not found
- `u104`: Milestone not found
- `u105`: Milestone already completed
- `u106`: Invalid recipient
- `u107`: Vesting schedule already exists

## 🤝 Contributing

Feel free to submit issues and enhancement requests!

## 📄 License

This project is open source and available under the MIT License.

