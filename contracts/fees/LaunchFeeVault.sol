// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ILaunchFeeVault} from "../interfaces/ILaunchFeeVault.sol";

contract LaunchFeeVault is AccessControl, ReentrancyGuard, ILaunchFeeVault {
    using SafeERC20 for IERC20;

    bytes32 public constant FEE_CREDITOR_ROLE = keccak256("FEE_CREDITOR_ROLE");

    IERC20 public immutable usdc;
    address public immutable protocolTreasury;
    mapping(address holder => uint256 amount) public protectionHolderClaimable;
    uint256 public protocolClaimable;
    uint256 public totalLiabilities;

    error ZeroAddress();
    error InvalidFeeCredit();
    error NothingToClaim();
    error Insolvent(uint256 assets, uint256 liabilities);

    event LaunchFeeCredited(
        bytes32 indexed launchId,
        address indexed payer,
        address indexed protectionHolderRecipient,
        uint256 totalAmount,
        uint256 protectionHolderAmount,
        uint256 protocolAmount,
        bytes32 feePolicyVersionHash
    );
    event ProtectionHolderFeesClaimed(address indexed holder, uint256 amount);
    event ProtocolFeesClaimed(address indexed treasury, uint256 amount);

    constructor(address admin, address creditor, address usdc_, address protocolTreasury_) {
        if (
            admin == address(0) ||
            creditor == address(0) ||
            usdc_ == address(0) ||
            protocolTreasury_ == address(0)
        ) revert ZeroAddress();
        usdc = IERC20(usdc_);
        protocolTreasury = protocolTreasury_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(FEE_CREDITOR_ROLE, creditor);
    }

    function creditLaunchFee(
        bytes32 launchId,
        address payer,
        address protectionHolderRecipient,
        uint256 totalAmount,
        uint256 protectionHolderAmount,
        bytes32 feePolicyVersionHash
    ) external onlyRole(FEE_CREDITOR_ROLE) {
        if (
            launchId == bytes32(0) ||
            payer == address(0) ||
            totalAmount == 0 ||
            protectionHolderAmount > totalAmount ||
            feePolicyVersionHash == bytes32(0) ||
            (protectionHolderAmount == 0 && protectionHolderRecipient != address(0)) ||
            (protectionHolderAmount > 0 && protectionHolderRecipient == address(0))
        ) revert InvalidFeeCredit();
        uint256 protocolAmount = totalAmount - protectionHolderAmount;
        if (protectionHolderAmount > 0) {
            protectionHolderClaimable[protectionHolderRecipient] += protectionHolderAmount;
        }
        protocolClaimable += protocolAmount;
        totalLiabilities += totalAmount;
        _assertSolvent();
        emit LaunchFeeCredited(
            launchId,
            payer,
            protectionHolderRecipient,
            totalAmount,
            protectionHolderAmount,
            protocolAmount,
            feePolicyVersionHash
        );
    }

    function claimProtectionHolderFees() external nonReentrant {
        uint256 amount = protectionHolderClaimable[msg.sender];
        if (amount == 0) revert NothingToClaim();
        protectionHolderClaimable[msg.sender] = 0;
        totalLiabilities -= amount;
        usdc.safeTransfer(msg.sender, amount);
        emit ProtectionHolderFeesClaimed(msg.sender, amount);
    }

    function dispatchProtocolFees() external nonReentrant {
        uint256 amount = protocolClaimable;
        if (amount == 0) revert NothingToClaim();
        protocolClaimable = 0;
        totalLiabilities -= amount;
        usdc.safeTransfer(protocolTreasury, amount);
        emit ProtocolFeesClaimed(protocolTreasury, amount);
    }

    function _assertSolvent() private view {
        uint256 assets = usdc.balanceOf(address(this));
        if (assets < totalLiabilities) revert Insolvent(assets, totalLiabilities);
    }
}
