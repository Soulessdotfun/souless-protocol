// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ILaunchRegistry {
    struct LaunchRecord {
        address issuer;
        address governanceWallet;
        address token;
        address pool;
        address lpLocker;
        uint256 lpTokenId;
        uint64 launchedAt;
        bytes32 policyVersionHash;
        bytes32 metadataCommitment;
        bytes32 namespaceKey;
        address referrer;
        uint16 referralShareBps;
        uint64 referralExpiresAt;
        bool narrativeProtectionRequested;
        bool creatorGovernanceCommitted;
        bool communityModeEnabled;
    }

    function registerLaunch(bytes32 launchId, LaunchRecord calldata record) external;
    function getLaunch(bytes32 launchId) external view returns (LaunchRecord memory);
}
