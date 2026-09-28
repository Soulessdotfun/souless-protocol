// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IMultiPositionLpLocker {
    struct LaunchTerms {
        address pool;
        address launchToken;
        address usdc;
        address creator;
        address referrer;
        uint16 referralShareBps;
        uint64 referralExpiresAt;
    }

    function registerPositions(
        bytes32 launchId,
        LaunchTerms calldata terms,
        uint256[] calldata tokenIds
    ) external;

    function positionIds(bytes32 launchId) external view returns (uint256[] memory);
}
