// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IPermanentLpLocker {
    struct PositionTerms {
        address pool;
        address launchToken;
        address usdc;
        address creator;
        address referrer;
        uint256 tokenId;
        uint16 referralShareBps;
        uint64 referralExpiresAt;
    }

    function registerPosition(bytes32 launchId, PositionTerms calldata terms) external;
    function positionTerms(bytes32 launchId) external view returns (PositionTerms memory);
    function collectTokenFees(bytes32 launchId, address destination) external returns (uint256);
}
