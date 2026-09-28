# Souless Protocol

Public on-chain protocol contracts and integration references for [Souless](https://souless.fun), an Arc-native launch market for humans and agents.

## What this repository is

This is a deliberately curated public protocol surface. It is **not** a mirror of the Souless production monorepo.

The initial release contains selected token, launch-registry, permanent-liquidity-locking, and fee-accounting contracts plus the interfaces and deployment references needed by external integrators.

It intentionally excludes the production application, API, off-chain InfoFi scoring and anti-gaming logic, narrative intelligence, databases, indexing infrastructure, deployment automation, secrets, and operator tooling.

Guarded-launch implementation contracts are not included in the initial source release while that surface undergoes additional hardening. Integration-facing addresses and interfaces remain available for independent on-chain verification.

See [docs/publication-boundary.md](docs/publication-boundary.md) for the exact boundary.

## Network

| Network | Chain ID | Quote / gas asset |
| --- | ---: | --- |
| Arc Mainnet | `5042` | USDC |

Arc USDC ERC-20 predeploy:

`0x3600000000000000000000000000000000000000`

Canonical deployment references are in [deployments/arc-mainnet.json](deployments/arc-mainnet.json).

## Published source

The first public source set includes:

- `contracts/token/LaunchToken.sol`
- `contracts/token/TokenFactory.sol`
- `contracts/launch/LaunchRegistry.sol`
- `contracts/launch/PermanentLpLocker.sol`
- fee vault, dispatch, partner-pool, reserve, and timelock contracts under `contracts/fees/`
- required integration interfaces under `contracts/interfaces/`

## Build

Requires Node.js 22+.

```bash
npm install
npm run compile
npm run typecheck
```

Solidity is compiled with `0.8.28`, optimizer enabled, and 10,000 optimizer runs to match the production contract toolchain.

## Integration verification

For the public surfaces used by the Souless DefiLlama adapters, see [docs/defillama-verification.md](docs/defillama-verification.md).

## Canonical resources

- Website: https://souless.fun
- Documentation: https://docs.souless.fun
- GitHub organization: https://github.com/Soulessdotfun

## Security

Please read [SECURITY.md](SECURITY.md) before reporting a potentially exploitable issue.
