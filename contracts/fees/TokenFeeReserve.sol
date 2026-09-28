// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITokenFeeReserve} from "../interfaces/ITokenFeeReserve.sol";

contract TokenFeeReserve is ITokenFeeReserve {
    using SafeERC20 for IERC20;

    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    address public bootstrapAuthority;
    address public burnExecutor;

    error ZeroAddress();
    error InvalidAmount();
    error Unauthorized();
    error BurnExecutorAlreadyConfigured();

    event BurnExecutorConfigured(address indexed executor);
    event ReserveTokensBurned(address indexed token, uint256 amount);

    constructor(address bootstrapAuthority_) {
        if (bootstrapAuthority_ == address(0)) revert ZeroAddress();
        bootstrapAuthority = bootstrapAuthority_;
    }

    function configureBurnExecutor(address executor) external {
        if (msg.sender != bootstrapAuthority) revert Unauthorized();
        if (executor == address(0)) revert ZeroAddress();
        if (burnExecutor != address(0)) revert BurnExecutorAlreadyConfigured();
        burnExecutor = executor;
        bootstrapAuthority = address(0);
        emit BurnExecutorConfigured(executor);
    }

    function burn(address token, uint256 amount) external {
        if (msg.sender != burnExecutor) revert Unauthorized();
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();
        IERC20(token).safeTransfer(BURN_ADDRESS, amount);
        emit ReserveTokensBurned(token, amount);
    }
}
