// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ILaunchPartnerPool} from "../interfaces/ILaunchPartnerPool.sol";

contract LaunchPartnerPool is AccessControl, ReentrancyGuard, ILaunchPartnerPool {
    using SafeERC20 for IERC20;
    using MessageHashUtils for bytes32;

    bytes32 public constant FEE_CREDITOR_ROLE = keccak256("FEE_CREDITOR_ROLE");
    bytes32 public constant PARTNER_ADMIN_ROLE = keccak256("PARTNER_ADMIN_ROLE");
    uint8 public constant PARTNER_SLOT_COUNT = 25;
    bytes32 public constant CLAIM_AUTHORIZATION_TYPEHASH = keccak256(
        "SoulessLaunchPartnerClaim(uint256 chainId,address partnerPool,uint8 slotId,address wallet,uint64 expiresAt,uint64 claimNonce)"
    );

    struct PartnerSlot {
        address wallet;
        uint256 rewardDebt;
        uint256 settledClaimable;
        bool active;
    }

    IERC20 public immutable usdc;
    address public immutable protocolTreasury;
    address public immutable claimAuthorizer;
    uint64 public immutable campaignStartsAt;
    uint64 public immutable campaignEndsAt;
    uint8 public activeSlotCount;
    uint256 public accumulatedUsdcPerSlot;
    uint256 public protocolClaimable;
    uint256 public totalLiabilities;

    mapping(uint8 slotId => PartnerSlot slot) private _slots;
    mapping(address wallet => uint8 slotId) public slotForWallet;
    mapping(uint8 slotId => bool enabled) public slotClaimEnabled;
    mapping(uint8 slotId => uint64 nonce) public slotClaimNonce;

    error ZeroAddress();
    error InvalidCampaignWindow();
    error InvalidSlot();
    error SlotAlreadyClaimed(uint8 slotId);
    error WalletAlreadyRegistered(address wallet);
    error ClaimAuthorizationExpired();
    error InvalidClaimAuthorization();
    error SlotNotClaimed(uint8 slotId);
    error SlotStateUnchanged();
    error SlotClaimDisabled(uint8 slotId);
    error CampaignInactive();
    error InvalidAmount();
    error NothingToClaim();
    error Insolvent(uint256 assets, uint256 liabilities);

    event PartnerSlotClaimed(uint8 indexed slotId, address indexed wallet);
    event PartnerSlotClaimStateChanged(uint8 indexed slotId, bool enabled, uint64 claimNonce);
    event PartnerSlotActivationChanged(uint8 indexed slotId, address indexed wallet, bool active);
    event CampaignFeesCredited(
        uint256 totalAmount,
        uint256 amountPerActiveSlot,
        uint8 activeSlots,
        uint256 partnerAmount,
        uint256 protocolAmount
    );
    event PartnerFeesClaimed(uint8 indexed slotId, address indexed wallet, uint256 amount);
    event ProtocolRemainderDispatched(address indexed treasury, uint256 amount);

    constructor(
        address admin,
        address feeCreditor,
        address partnerAdmin,
        address usdc_,
        address protocolTreasury_,
        address claimAuthorizer_,
        uint64 campaignStartsAt_,
        uint64 campaignEndsAt_
    ) {
        if (
            admin == address(0) || feeCreditor == address(0) || partnerAdmin == address(0) ||
            usdc_ == address(0) || protocolTreasury_ == address(0) || claimAuthorizer_ == address(0)
        ) revert ZeroAddress();
        if (campaignStartsAt_ == 0 || campaignEndsAt_ <= campaignStartsAt_) {
            revert InvalidCampaignWindow();
        }
        usdc = IERC20(usdc_);
        protocolTreasury = protocolTreasury_;
        claimAuthorizer = claimAuthorizer_;
        campaignStartsAt = campaignStartsAt_;
        campaignEndsAt = campaignEndsAt_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(FEE_CREDITOR_ROLE, feeCreditor);
        _grantRole(PARTNER_ADMIN_ROLE, partnerAdmin);
        for (uint8 slotId = 1; slotId <= PARTNER_SLOT_COUNT; slotId++) {
            slotClaimEnabled[slotId] = true;
        }
    }

    function campaignActive() public view returns (bool) {
        return block.timestamp >= campaignStartsAt && block.timestamp < campaignEndsAt;
    }

    function claimSlot(
        uint8 slotId,
        uint64 expiresAt,
        bytes calldata authorization
    ) external {
        if (slotId == 0 || slotId > PARTNER_SLOT_COUNT) revert InvalidSlot();
        if (!slotClaimEnabled[slotId]) revert SlotClaimDisabled(slotId);
        if (_slots[slotId].wallet != address(0)) revert SlotAlreadyClaimed(slotId);
        if (slotForWallet[msg.sender] != 0) revert WalletAlreadyRegistered(msg.sender);
        if (block.timestamp > expiresAt) revert ClaimAuthorizationExpired();
        bytes32 digest = claimAuthorizationHash(slotId, msg.sender, expiresAt);
        if (ECDSA.recover(digest.toEthSignedMessageHash(), authorization) != claimAuthorizer) {
            revert InvalidClaimAuthorization();
        }
        _slots[slotId] = PartnerSlot({
            wallet: msg.sender,
            rewardDebt: accumulatedUsdcPerSlot,
            settledClaimable: 0,
            active: false
        });
        slotForWallet[msg.sender] = slotId;
        emit PartnerSlotClaimed(slotId, msg.sender);
    }

    function setSlotClaimEnabled(uint8 slotId, bool enabled)
        external
        onlyRole(PARTNER_ADMIN_ROLE)
    {
        if (slotId == 0 || slotId > PARTNER_SLOT_COUNT) revert InvalidSlot();
        if (slotClaimEnabled[slotId] == enabled) revert SlotStateUnchanged();
        slotClaimEnabled[slotId] = enabled;
        uint64 nextNonce = slotClaimNonce[slotId] + 1;
        slotClaimNonce[slotId] = nextNonce;
        emit PartnerSlotClaimStateChanged(slotId, enabled, nextNonce);
    }

    function setSlotActive(uint8 slotId, bool active) external onlyRole(PARTNER_ADMIN_ROLE) {
        PartnerSlot storage slot = _slot(slotId);
        if (slot.active == active) revert SlotStateUnchanged();
        _settle(slot);
        slot.active = active;
        if (active) {
            activeSlotCount += 1;
        } else {
            activeSlotCount -= 1;
        }
        emit PartnerSlotActivationChanged(slotId, slot.wallet, active);
    }

    function creditCampaignFees(uint256 amount)
        external
        onlyRole(FEE_CREDITOR_ROLE)
        nonReentrant
    {
        if (!campaignActive()) revert CampaignInactive();
        if (amount == 0) revert InvalidAmount();
        uint256 amountPerSlot = amount / PARTNER_SLOT_COUNT;
        uint256 partnerAmount = amountPerSlot * activeSlotCount;
        uint256 protocolAmount = amount - partnerAmount;
        accumulatedUsdcPerSlot += amountPerSlot;
        protocolClaimable += protocolAmount;
        totalLiabilities += amount;
        _assertSolvent();
        emit CampaignFeesCredited(
            amount,
            amountPerSlot,
            activeSlotCount,
            partnerAmount,
            protocolAmount
        );
    }

    function claimPartnerFees() external nonReentrant {
        uint8 slotId = slotForWallet[msg.sender];
        if (slotId == 0) revert NothingToClaim();
        PartnerSlot storage slot = _slots[slotId];
        _settle(slot);
        uint256 amount = slot.settledClaimable;
        if (amount == 0) revert NothingToClaim();
        slot.settledClaimable = 0;
        totalLiabilities -= amount;
        usdc.safeTransfer(msg.sender, amount);
        emit PartnerFeesClaimed(slotId, msg.sender, amount);
    }

    function dispatchProtocolRemainder() external nonReentrant {
        uint256 amount = protocolClaimable;
        if (amount == 0) revert NothingToClaim();
        protocolClaimable = 0;
        totalLiabilities -= amount;
        usdc.safeTransfer(protocolTreasury, amount);
        emit ProtocolRemainderDispatched(protocolTreasury, amount);
    }

    function claimable(uint8 slotId) external view returns (uint256) {
        PartnerSlot memory slot = _slots[slotId];
        if (slot.wallet == address(0)) return 0;
        uint256 unsettled = slot.active ? accumulatedUsdcPerSlot - slot.rewardDebt : 0;
        return slot.settledClaimable + unsettled;
    }

    function partnerSlot(uint8 slotId) external view returns (PartnerSlot memory) {
        if (slotId == 0 || slotId > PARTNER_SLOT_COUNT) revert InvalidSlot();
        return _slots[slotId];
    }

    function claimAuthorizationHash(
        uint8 slotId,
        address wallet,
        uint64 expiresAt
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                CLAIM_AUTHORIZATION_TYPEHASH,
                block.chainid,
                address(this),
                slotId,
                wallet,
                expiresAt,
                slotClaimNonce[slotId]
            )
        );
    }

    function _slot(uint8 slotId) private view returns (PartnerSlot storage slot) {
        if (slotId == 0 || slotId > PARTNER_SLOT_COUNT) revert InvalidSlot();
        slot = _slots[slotId];
        if (slot.wallet == address(0)) revert SlotNotClaimed(slotId);
    }

    function _settle(PartnerSlot storage slot) private {
        if (slot.active) {
            slot.settledClaimable += accumulatedUsdcPerSlot - slot.rewardDebt;
        }
        slot.rewardDebt = accumulatedUsdcPerSlot;
    }

    function _assertSolvent() private view {
        uint256 assets = usdc.balanceOf(address(this));
        if (assets < totalLiabilities) revert Insolvent(assets, totalLiabilities);
    }
}
