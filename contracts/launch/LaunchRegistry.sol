// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ILaunchRegistry} from "../interfaces/ILaunchRegistry.sol";

contract LaunchRegistry is AccessControl, ILaunchRegistry {
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    mapping(bytes32 launchId => LaunchRecord record) private _launches;
    mapping(address token => bytes32 launchId) public launchForToken;
    mapping(address pool => bytes32 launchId) public launchForPool;

    error ZeroAddress();
    error InvalidLaunchIdentifier();
    error InvalidLaunchRecord();
    error LaunchAlreadyRegistered(bytes32 launchId);
    error TokenAlreadyRegistered(address token);
    error PoolAlreadyRegistered(address pool);

    event LaunchRegistered(
        bytes32 indexed launchId,
        address indexed issuer,
        address indexed token,
        address pool,
        address lpLocker,
        uint256 lpTokenId,
        bytes32 policyVersionHash,
        bytes32 metadataCommitment,
        bytes32 namespaceKey,
        address referrer,
        uint16 referralShareBps,
        uint64 referralExpiresAt,
        bool narrativeProtectionRequested
    );

    constructor(address admin, address registrar) {
        if (admin == address(0) || registrar == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRAR_ROLE, registrar);
    }

    function registerLaunch(
        bytes32 launchId,
        LaunchRecord calldata record
    ) external onlyRole(REGISTRAR_ROLE) {
        if (launchId == bytes32(0)) revert InvalidLaunchIdentifier();
        if (_launches[launchId].token != address(0)) revert LaunchAlreadyRegistered(launchId);
        if (
            record.issuer == address(0) ||
            record.governanceWallet == address(0) ||
            record.token == address(0) ||
            record.pool == address(0) ||
            record.lpLocker == address(0) ||
            record.lpTokenId == 0 ||
            record.launchedAt == 0 ||
            record.policyVersionHash == bytes32(0) ||
            record.metadataCommitment == bytes32(0) ||
            !_isValidReferralShare(record.referralShareBps) ||
            (record.referralShareBps == 0 &&
                (record.referrer != address(0) || record.referralExpiresAt != 0)) ||
            (record.referralShareBps > 0 &&
                (record.referrer == address(0) ||
                    record.referrer == record.issuer ||
                    record.referralExpiresAt <= record.launchedAt)) ||
            (record.narrativeProtectionRequested && record.namespaceKey == bytes32(0))
        ) revert InvalidLaunchRecord();
        if (launchForToken[record.token] != bytes32(0)) revert TokenAlreadyRegistered(record.token);
        if (launchForPool[record.pool] != bytes32(0)) revert PoolAlreadyRegistered(record.pool);

        _launches[launchId] = record;
        launchForToken[record.token] = launchId;
        launchForPool[record.pool] = launchId;

        emit LaunchRegistered(
            launchId,
            record.issuer,
            record.token,
            record.pool,
            record.lpLocker,
            record.lpTokenId,
            record.policyVersionHash,
            record.metadataCommitment,
            record.namespaceKey,
            record.referrer,
            record.referralShareBps,
            record.referralExpiresAt,
            record.narrativeProtectionRequested
        );
    }

    function getLaunch(bytes32 launchId) external view returns (LaunchRecord memory) {
        return _launches[launchId];
    }

    function _isValidReferralShare(uint16 referralShareBps) private pure returns (bool) {
        return
            referralShareBps == 0 || referralShareBps == 500;
    }
}
