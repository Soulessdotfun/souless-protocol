// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IFeeDispatcher} from "../interfaces/IFeeDispatcher.sol";
import {ICommunityRewardsDistributor} from "../interfaces/ICommunityRewardsDistributor.sol";
import {ILaunchPartnerPool} from "../interfaces/ILaunchPartnerPool.sol";

contract FeeDispatcher is AccessControl, ReentrancyGuard, IFeeDispatcher {
    using SafeERC20 for IERC20;

    bytes32 public constant FEE_CREDITOR_ROLE = keccak256("FEE_CREDITOR_ROLE");
    uint16 public constant MAX_REFERRAL_SHARE_BPS = 500;
    uint16 private constant BPS_DENOMINATOR = 10_000;

    IERC20 public immutable usdc;
    address public immutable protocolTreasury;
    ICommunityRewardsDistributor public immutable communityRewardsDistributor;
    ILaunchPartnerPool public immutable launchPartnerPool;
    mapping(address creator => uint256 amount) public creatorClaimable;
    mapping(address referrer => uint256 amount) public referralClaimable;
    uint256 public protocolClaimable;
    uint256 public totalLiabilities;

    struct Distribution {
        uint256 creatorAmount;
        uint256 communityAmount;
        uint256 launchPartnerAmount;
        uint256 referrerAmount;
        uint256 protocolAmount;
        bool referralActive;
    }

    error ZeroAddress();
    error InvalidAmount();
    error InvalidReferralTerms();
    error NothingToClaim();
    error Insolvent(uint256 assets, uint256 liabilities);

    event FeesCredited(
        bytes32 indexed launchId,
        uint256 totalAmount,
        uint256 creatorAmount,
        uint256 communityAmount,
        uint256 launchPartnerAmount,
        uint256 referrerAmount,
        uint256 protocolAmount,
        bool referralActive
    );
    event CreatorFeesClaimed(address indexed creator, uint256 amount);
    event ReferralFeesClaimed(address indexed referrer, uint256 amount);
    event ProtocolFeesClaimed(address indexed treasury, uint256 amount);

    constructor(
        address admin,
        address creditor,
        address usdc_,
        address protocolTreasury_,
        address communityRewardsDistributor_,
        address launchPartnerPool_
    ) {
        if (
            admin == address(0) ||
            creditor == address(0) ||
            usdc_ == address(0) ||
            protocolTreasury_ == address(0) ||
            communityRewardsDistributor_ == address(0) ||
            launchPartnerPool_ == address(0)
        ) revert ZeroAddress();
        usdc = IERC20(usdc_);
        protocolTreasury = protocolTreasury_;
        communityRewardsDistributor = ICommunityRewardsDistributor(communityRewardsDistributor_);
        launchPartnerPool = ILaunchPartnerPool(launchPartnerPool_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(FEE_CREDITOR_ROLE, creditor);
    }

    function creditUsdcFees(
        bytes32 launchId,
        address token,
        address creator,
        address referrer,
        uint16 referralShareBps,
        uint64 referralExpiresAt,
        uint256 amount
    ) external onlyRole(FEE_CREDITOR_ROLE) nonReentrant {
        if (launchId == bytes32(0) || token == address(0) || creator == address(0) || amount == 0) {
            revert InvalidAmount();
        }
        if (
            !_isValidReferralShare(referralShareBps) ||
            (referralShareBps == 0 && (referrer != address(0) || referralExpiresAt != 0)) ||
            (referralShareBps > 0 &&
                (referrer == address(0) || referrer == creator || referralExpiresAt == 0))
        ) revert InvalidReferralTerms();

        Distribution memory distribution = _distribution(
            token,
            referralShareBps,
            referralExpiresAt,
            amount
        );

        creatorClaimable[creator] += distribution.creatorAmount;
        if (distribution.referrerAmount > 0) {
            referralClaimable[referrer] += distribution.referrerAmount;
        }
        protocolClaimable += distribution.protocolAmount;
        totalLiabilities += amount - distribution.communityAmount -
            distribution.launchPartnerAmount;
        if (distribution.communityAmount > 0) {
            usdc.safeTransfer(address(communityRewardsDistributor), distribution.communityAmount);
            communityRewardsDistributor.creditEpochFees(token, distribution.communityAmount);
        }
        if (distribution.launchPartnerAmount > 0) {
            usdc.safeTransfer(address(launchPartnerPool), distribution.launchPartnerAmount);
            launchPartnerPool.creditCampaignFees(distribution.launchPartnerAmount);
        }
        _assertSolvent();

        _emitFeesCredited(launchId, amount, distribution);
    }

    function claimCreatorFees() external nonReentrant {
        uint256 amount = creatorClaimable[msg.sender];
        if (amount == 0) revert NothingToClaim();
        creatorClaimable[msg.sender] = 0;
        totalLiabilities -= amount;
        usdc.safeTransfer(msg.sender, amount);
        emit CreatorFeesClaimed(msg.sender, amount);
    }

    function claimReferralFees() external nonReentrant {
        uint256 amount = referralClaimable[msg.sender];
        if (amount == 0) revert NothingToClaim();
        referralClaimable[msg.sender] = 0;
        totalLiabilities -= amount;
        usdc.safeTransfer(msg.sender, amount);
        emit ReferralFeesClaimed(msg.sender, amount);
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

    function _distribution(
        address token,
        uint16 referralShareBps,
        uint64 referralExpiresAt,
        uint256 amount
    ) private view returns (Distribution memory distribution) {
        bool partnerCampaignActive = launchPartnerPool.campaignActive();
        distribution.referralActive = referralShareBps > 0 &&
            block.timestamp < referralExpiresAt;
        (uint16 creatorShareBps, uint16 communityShareBps) = communityRewardsDistributor
            .quoteShares(token);
        distribution.creatorAmount = (amount * creatorShareBps) / BPS_DENOMINATOR;
        distribution.communityAmount = (amount * communityShareBps) / BPS_DENOMINATOR;
        distribution.launchPartnerAmount = partnerCampaignActive
            ? (amount * MAX_REFERRAL_SHARE_BPS) / BPS_DENOMINATOR
            : 0;
        distribution.referrerAmount = distribution.referralActive
            ? (amount * referralShareBps) / BPS_DENOMINATOR
            : 0;
        distribution.protocolAmount = amount - distribution.creatorAmount -
            distribution.communityAmount - distribution.launchPartnerAmount -
            distribution.referrerAmount;
    }

    function _emitFeesCredited(
        bytes32 launchId,
        uint256 amount,
        Distribution memory distribution
    ) private {
        emit FeesCredited(
            launchId,
            amount,
            distribution.creatorAmount,
            distribution.communityAmount,
            distribution.launchPartnerAmount,
            distribution.referrerAmount,
            distribution.protocolAmount,
            distribution.referralActive
        );
    }

    function _isValidReferralShare(uint16 referralShareBps) private pure returns (bool) {
        return referralShareBps == 0 || referralShareBps == MAX_REFERRAL_SHARE_BPS;
    }
}
