# DefiLlama verification notes

This repository exposes the public protocol surfaces used to independently reason about Souless TVL and fee reporting on Arc mainnet.

## TVL

Souless launch records are anchored by the canonical `LaunchRegistry`.

For direct launches, permanently locked Uniswap v3 positions are held by the published `PermanentLpLocker`.

The current guarded locker address is listed in the deployment manifest as an integration reference. Its implementation is not part of the initial public source release.

The Souless DefiLlama TVL methodology counts the Arc USDC side of eligible permanently locked Uniswap v3 positions. The launched-token side and uncollected fees are excluded. The TVL is marked double-counted because those positions are also represented in Uniswap v3 TVL on Arc.

## Fees

The fee adapter reads canonical on-chain events rather than reconstructing fee policy from mutable percentages:

- `LaunchFeeCredited` from `LaunchFeeVault`;
- `OpeningFeeDeposited` from the guarded opening-fee vault;
- `FeesCredited` from `FeeDispatcher`.

Where `FeesCredited` contains emitted allocation amounts, downstream accounting can use the emitted split rather than assuming the current policy applies historically.

See `deployments/arc-mainnet.json` for the public addresses used to verify these flows.
