# Souless Protocol

Public on-chain protocol contracts and integration references for [Souless](https://souless.fun), an Arc-native launch market for humans and agents.

## Scope

This repository is a deliberately curated public protocol surface. It is **not** a mirror of the Souless production monorepo.

The initial public source set is intended to make deployed protocol behavior and third-party integrations easier to inspect. It includes selected:

- token primitives;
- launch registry and permanent LP-locking contracts;
- fee accounting and distribution contracts;
- Solidity interfaces used by integrators;
- sanitized Arc mainnet deployment references.

The following remain outside this repository:

- production web and API services;
- off-chain InfoFi scoring and anti-gaming logic;
- semantic scoring/model configuration;
- narrative classification and intelligence pipelines;
- databases, indexing infrastructure, deployment automation, secrets, and operator tooling.

Guarded-launch implementation contracts are not included in the initial source release while that surface undergoes additional hardening. Their deployed addresses may still be listed for independent on-chain verification.

## Network

| Network | Chain ID | Quote / gas asset |
| --- | ---: | --- |
| Arc Mainnet | `5042` | USDC |

Arc USDC ERC-20 predeploy:

`0x3600000000000000000000000000000000000000`

## Canonical resources

- Website: https://souless.fun
- Documentation: https://docs.souless.fun
- GitHub organization: https://github.com/Soulessdotfun

## Source-of-truth policy

Souless is developed in a private production monorepo. Files published here are exported intentionally from that source of truth after review. Internal application logic is not synchronized into this repository.

Deployment addresses in this repository are public verification references. Integrators should also verify deployed bytecode and current on-chain state before relying on an address.

## Security

See [SECURITY.md](SECURITY.md) once the initial protocol-source bootstrap lands.
