// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ICommunityRewardsDistributor {
    function quoteShares(address token) external view returns (uint16 creatorShareBps, uint16 communityShareBps);
    function isValidGenesisPolicy(
        uint16 communityShareBps,
        uint16 stakingShareOfCommunityBps
    ) external view returns (bool);
    function initializeGenesisPolicy(
        address token,
        uint16 communityShareBps,
        uint16 stakingShareOfCommunityBps
    ) external;
    function creditEpochFees(address token, uint256 amount) external;
}
