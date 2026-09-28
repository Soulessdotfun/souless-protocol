// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IFeeDispatcher {
    function creditUsdcFees(
        bytes32 launchId,
        address token,
        address creator,
        address referrer,
        uint16 referralShareBps,
        uint64 referralExpiresAt,
        uint256 amount
    ) external;
}
