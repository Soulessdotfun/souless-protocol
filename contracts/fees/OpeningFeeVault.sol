// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract OpeningFeeVault is AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    IERC20 public immutable usdc;
    mapping(bytes32 launchId => uint256 amount) public feesForLaunch;
    uint256 public totalFeesReceived;

    error ZeroAddress();
    error InvalidLaunchIdentifier();
    error InvalidAmount();

    event OpeningFeeDeposited(bytes32 indexed launchId, address indexed guard, uint256 amount);
    event OpeningFeesWithdrawn(address indexed recipient, uint256 amount);

    constructor(address safe, address usdc_) {
        if (safe == address(0) || usdc_ == address(0)) revert ZeroAddress();
        usdc = IERC20(usdc_);
        _grantRole(DEFAULT_ADMIN_ROLE, safe);
        _grantRole(TREASURY_ROLE, safe);
    }

    function depositOpeningFee(bytes32 launchId, uint256 amount) external {
        if (launchId == bytes32(0)) revert InvalidLaunchIdentifier();
        if (amount == 0) revert InvalidAmount();
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        feesForLaunch[launchId] += amount;
        totalFeesReceived += amount;
        emit OpeningFeeDeposited(launchId, msg.sender, amount);
    }

    function withdraw(address recipient, uint256 amount) external onlyRole(TREASURY_ROLE) {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();
        usdc.safeTransfer(recipient, amount);
        emit OpeningFeesWithdrawn(recipient, amount);
    }
}
