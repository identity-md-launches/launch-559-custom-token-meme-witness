# Meme Witness Protection (ALIBI)

ALIBI is a fee-free ERC-20. Its constructor creates the entire supply once and
credits the immediate deployer. The implementation is
[`src/ALIBI.sol`](src/ALIBI.sol), using the unmodified OpenZeppelin Contracts
v5.1.0 ERC-20 implementation vendored in this repository.

## Token and deployment parameters

| Parameter | Value |
| --- | --- |
| Contract artifact | `src/ALIBI.sol:ALIBI` |
| Name | `Meme Witness Protection` |
| Symbol | `ALIBI` |
| Decimals | `18` |
| Human-readable supply | `1,000,000,000` ALIBI |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`; encoded arguments `0x`) |
| Constructor native currency value | `0` |
| Initial recipient | Constructor `msg.sender` |
| Transfer fee | `0` |
| Compiler | Solidity `0.8.26` |
| EVM target | `cancun` |
| Optimization | Enabled, 200 runs |
| Bytecode metadata hash | `none` |

The deployment chain must support the configured EVM target. There are no
chain-specific addresses, initializer calls, external library links, application
contracts, constructor configuration, or post-deployment configuration.

For a direct deployment, the deploying account receives all tokens. For a
factory deployment, **the factory receives all tokens**, not the transaction
originator or requester. The constructor uses neither `tx.origin` nor a hardcoded
recipient. CREATE and CREATE2 have identical supply behavior.

The network launch process can identify the artifact above, use an empty
`constructorArgs` array, and set `totalSupply` to the exact smallest-unit value
above. The separate launch manifest and pool economics are managed by the launch
operator; this token does not choose allocations, pool price, or a chain. The
factory can transfer its allocation to a distributor or pool just like any other
holder. No exemptions are necessary because every transfer is fee-free.

## Behavior and assumptions

- `transfer` and `transferFrom` deliver the exact requested number of smallest
  units and return `true` on success. Invalid calls revert with OpenZeppelin's
  ERC-6093 custom errors; failures preserve balances and allowances.
- Zero-value transfers between valid addresses succeed and emit `Transfer`.
  Self-transfers preserve the balance. Transfers to the zero address revert,
  including zero-value transfers.
- `approve` replaces the spender's allowance and emits `Approval`. Zero approvals
  revoke it. A zero spender is rejected. Finite allowances decrease when spent;
  `type(uint256).max` represents unlimited allowance and does not decrease.
  As in OpenZeppelin v5, spending an allowance does not emit another `Approval`.
- The only mint is in the constructor, emitting `Transfer(address(0), deployer,
  supply)`. There is no external mint or burn function and no rebasing. The
  supply remains fixed for the lifetime of the deployed contract.
- There is no owner, administrator, pause, blacklist, seizure, upgrade, transfer
  limit, tax, or privileged allowance bypass. The deployer controls only its
  balance and allowances, with the same rules as every other holder.
- Transfers make no external calls or receiver callbacks. The token has no
  payable entry point, recovery mechanism, oracle, keeper, or runtime dependency
  on another deployed contract. Token transfers to contracts that cannot return
  them, including the token itself, may leave those tokens inaccessible.

## Build and checks

With Foundry and its Solidity 0.8.26 compiler installed:

```sh
forge build
forge test
forge fmt --check
```

All Solidity dependencies and their licenses are ordinary files under `lib/`.
No package installation, git submodule, RPC, environment configuration, FFI, or
filesystem permission is needed by the tests. `DEPENDENCIES.json` records the
release archive URLs, archive hashes, and SHA-256 hashes of the vendored files.
Only the required OpenZeppelin source files are included; forge-std v1.9.4 is a
test dependency. The compiler is provisioned by the execution environment, not
stored in this repository.

`test/ALIBI.t.sol` exercises metadata and issuance, factory deployment, events,
exact transfers, allowances, invalid inputs, authorization failures, and fixed
supply. Fuzz tests cover transfer and allowance boundaries. The stateful test in
`test/ALIBI.invariant.t.sol` compares arbitrary sequences of transfers, approvals,
and delegated transfers with an independent balance/allowance model, checking
conservation and the fixed supply after each sequence. The configuration runs
512 cases per fuzz test and 128 invariant sequences of depth 64.

The supplied protected test is an external, environment-driven launch harness.
It is not copied into the local test suite. Local factory/distributor and pool
custody transfer checks demonstrate exact token movements; actual Uniswap v4
seeding and swaps remain checks of that independent launch harness with its
resolved manifest and infrastructure.

## Operational responsibilities

The deployment operator must review the artifact and launch parameters, choose
the intended deploying account or factory, and arrange custody and distribution
of its initial supply. Creation code is available locally without a transaction:

```sh
forge inspect src/ALIBI.sol:ALIBI bytecode
```

Pass that creation code without appended constructor arguments to the authorized
deployment process. No wallet key, broadcast, deployment address, or funding is
part of this project. After deployment, the operator should verify the source
and compiler settings on the target chain, then check metadata, `totalSupply`,
the mint event, and the initial holder before executing distributions.

Holders are responsible for recipient addresses and spender approvals. Prefer
the amount needed; an unlimited allowance gives the spender access to future
balances as well. Replacing an existing allowance has the standard ERC-20
transaction-ordering race; revoke it and confirm the revocation before granting
a replacement when coordinating with an untrusted spender. There is no admin
key that can restore lost tokens or undo approvals on a holder's behalf.

An independent adversarial review is an operational release responsibility.
The work here includes source review and Foundry unit, fuzz, and invariant
checks; it does not claim a production security audit. Slither and Mythril were
not run. Pool launch configuration, actual deployment, explorer verification,
and funded operations belong to the network's deployment process.
