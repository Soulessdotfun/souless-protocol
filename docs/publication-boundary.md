# Public / private publication boundary

This repository is an intentionally curated export from the private Souless production monorepo.

## Published here

The initial public surface contains components whose source is useful for protocol verification and third-party integrations:

- token primitives;
- the canonical launch registry;
- the permanent single-position LP locker;
- fee accounting, fee vault, partner-pool, reserve, and timelock contracts;
- the Solidity interfaces required by those contracts;
- selected integration-facing interfaces;
- sanitized Arc mainnet deployment references.

Published Solidity files are copied without behavioral rewrites from the canonical private source snapshot recorded in `deployments/arc-mainnet.json`.

## Not published here

This repository intentionally excludes application and operational internals, including:

- web and API implementations;
- off-chain InfoFi scoring and reward-ranking logic;
- semantic model prompts, thresholds, and anti-gaming logic;
- narrative classification and intelligence pipelines;
- database schemas and migrations;
- indexer internals;
- deployment automation, Safe transaction plans, secrets, and operator runbooks.

The guarded-launch implementation is also outside the initial public source set while that surface undergoes additional hardening. Integration-facing addresses and interfaces may still be published for independent on-chain verification.

## Source of truth

The private production monorepo remains the canonical development source. Public updates should be exported by explicit allowlist rather than by mirroring or filtering the private repository history.
