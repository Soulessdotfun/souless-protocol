// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IFeeDispatcher} from "../interfaces/IFeeDispatcher.sol";
import {IPermanentLpLocker} from "../interfaces/IPermanentLpLocker.sol";
import {INonfungiblePositionManagerLike} from "../interfaces/IUniswapV3Dependencies.sol";

contract PermanentLpLocker is AccessControl, IERC721Receiver, IPermanentLpLocker {
    using SafeERC20 for IERC20;

    bytes32 public constant POSITION_REGISTRAR_ROLE = keccak256("POSITION_REGISTRAR_ROLE");
    uint256 public constant MINIMUM_USDC_COLLECTION = 1e6;

    INonfungiblePositionManagerLike public immutable positionManager;
    IFeeDispatcher public immutable feeDispatcher;
    address public immutable tokenFeeReserve;
    address public tokenFeeController;
    mapping(bytes32 launchId => uint256 tokenId) public positionForLaunch;
    mapping(uint256 tokenId => bytes32 launchId) public launchForPosition;
    mapping(bytes32 launchId => PositionTerms terms) private _positionTerms;

    error ZeroAddress();
    error InvalidLaunchIdentifier();
    error InvalidPosition();
    error PositionNotCustodied(uint256 tokenId);
    error LaunchPositionAlreadyRegistered(bytes32 launchId);
    error PositionAlreadyRegistered(uint256 tokenId);
    error UnsupportedNft(address nft);
    error CollectionBelowMinimum(uint256 collected);
    error LaunchTokenCollectionProhibited(uint256 collected);
    error CollectionAccountingMismatch(uint256 reported, uint256 received);
    error TokenFeeControllerAlreadyConfigured();
    error UnauthorizedTokenFeeController();
    error InvalidTokenFeeDestination(address destination);
    error UsdcCollectionProhibited(uint256 collected);
    error NoTokenFeesCollected();

    event PositionPermanentlyLocked(bytes32 indexed launchId, address indexed pool, uint256 indexed tokenId);
    event UsdcFeesCollected(bytes32 indexed launchId, uint256 indexed tokenId, uint256 amount);
    event TokenFeeControllerConfigured(address indexed controller);
    event TokenFeesCollected(
        bytes32 indexed launchId,
        uint256 indexed tokenId,
        address indexed token,
        address destination,
        uint256 amount
    );

    constructor(
        address admin,
        address registrar,
        address positionManager_,
        address feeDispatcher_,
        address tokenFeeReserve_
    ) {
        if (
            admin == address(0) ||
            registrar == address(0) ||
            positionManager_ == address(0) ||
            feeDispatcher_ == address(0) ||
            tokenFeeReserve_ == address(0)
        ) {
            revert ZeroAddress();
        }
        positionManager = INonfungiblePositionManagerLike(positionManager_);
        feeDispatcher = IFeeDispatcher(feeDispatcher_);
        tokenFeeReserve = tokenFeeReserve_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(POSITION_REGISTRAR_ROLE, registrar);
    }

    function registerPosition(
        bytes32 launchId,
        PositionTerms calldata terms
    ) external onlyRole(POSITION_REGISTRAR_ROLE) {
        if (launchId == bytes32(0)) revert InvalidLaunchIdentifier();
        if (
            terms.pool == address(0) ||
            terms.launchToken == address(0) ||
            terms.usdc == address(0) ||
            terms.creator == address(0) ||
            terms.tokenId == 0 ||
            terms.launchToken == terms.usdc ||
            !_isValidReferralShare(terms.referralShareBps) ||
            (terms.referralShareBps == 0 &&
                (terms.referrer != address(0) || terms.referralExpiresAt != 0)) ||
            (terms.referralShareBps > 0 &&
                (terms.referrer == address(0) ||
                    terms.referrer == terms.creator ||
                    terms.referralExpiresAt <= block.timestamp))
        ) revert InvalidPosition();
        if (positionForLaunch[launchId] != 0) revert LaunchPositionAlreadyRegistered(launchId);
        if (launchForPosition[terms.tokenId] != bytes32(0)) {
            revert PositionAlreadyRegistered(terms.tokenId);
        }
        if (positionManager.ownerOf(terms.tokenId) != address(this)) {
            revert PositionNotCustodied(terms.tokenId);
        }

        positionForLaunch[launchId] = terms.tokenId;
        launchForPosition[terms.tokenId] = launchId;
        _positionTerms[launchId] = terms;
        emit PositionPermanentlyLocked(launchId, terms.pool, terms.tokenId);
    }

    function positionTerms(bytes32 launchId) external view returns (PositionTerms memory) {
        return _positionTerms[launchId];
    }

    function configureTokenFeeController(address controller) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (controller == address(0)) revert ZeroAddress();
        if (tokenFeeController != address(0)) revert TokenFeeControllerAlreadyConfigured();
        tokenFeeController = controller;
        emit TokenFeeControllerConfigured(controller);
    }

    function collectAndDispatchUsdc(bytes32 launchId) external returns (uint256 usdcCollected) {
        PositionTerms storage terms = _positionTerms[launchId];
        if (terms.tokenId == 0) revert InvalidPosition();
        bool usdcIsToken0 = terms.usdc < terms.launchToken;
        uint256 balanceBefore = IERC20(terms.usdc).balanceOf(address(this));
        (uint256 amount0, uint256 amount1) = positionManager.collect(
            INonfungiblePositionManagerLike.CollectParams({
                tokenId: terms.tokenId,
                recipient: address(this),
                amount0Max: usdcIsToken0 ? type(uint128).max : 0,
                amount1Max: usdcIsToken0 ? 0 : type(uint128).max
            })
        );
        uint256 launchTokenCollected = usdcIsToken0 ? amount1 : amount0;
        if (launchTokenCollected != 0) revert LaunchTokenCollectionProhibited(launchTokenCollected);
        usdcCollected = usdcIsToken0 ? amount0 : amount1;
        if (usdcCollected < MINIMUM_USDC_COLLECTION) {
            revert CollectionBelowMinimum(usdcCollected);
        }
        uint256 received = IERC20(terms.usdc).balanceOf(address(this)) - balanceBefore;
        if (received != usdcCollected) revert CollectionAccountingMismatch(usdcCollected, received);

        IERC20(terms.usdc).safeTransfer(address(feeDispatcher), usdcCollected);
        feeDispatcher.creditUsdcFees(
            launchId,
            terms.launchToken,
            terms.creator,
            terms.referrer,
            terms.referralShareBps,
            terms.referralExpiresAt,
            usdcCollected
        );
        emit UsdcFeesCollected(launchId, terms.tokenId, usdcCollected);
    }

    function collectTokenFees(
        bytes32 launchId,
        address destination
    ) external returns (uint256 tokenFeesCollected) {
        if (msg.sender != tokenFeeController) revert UnauthorizedTokenFeeController();
        if (destination != tokenFeeReserve && destination != address(0x000000000000000000000000000000000000dEaD)) {
            revert InvalidTokenFeeDestination(destination);
        }
        PositionTerms storage terms = _positionTerms[launchId];
        if (terms.tokenId == 0) revert InvalidPosition();
        bool usdcIsToken0 = terms.usdc < terms.launchToken;
        uint256 balanceBefore = IERC20(terms.launchToken).balanceOf(destination);
        (uint256 amount0, uint256 amount1) = positionManager.collect(
            INonfungiblePositionManagerLike.CollectParams({
                tokenId: terms.tokenId,
                recipient: destination,
                amount0Max: usdcIsToken0 ? 0 : type(uint128).max,
                amount1Max: usdcIsToken0 ? type(uint128).max : 0
            })
        );
        uint256 usdcCollected = usdcIsToken0 ? amount0 : amount1;
        if (usdcCollected != 0) revert UsdcCollectionProhibited(usdcCollected);
        tokenFeesCollected = usdcIsToken0 ? amount1 : amount0;
        if (tokenFeesCollected == 0) revert NoTokenFeesCollected();
        uint256 received = IERC20(terms.launchToken).balanceOf(destination) - balanceBefore;
        if (received != tokenFeesCollected) {
            revert CollectionAccountingMismatch(tokenFeesCollected, received);
        }
        emit TokenFeesCollected(
            launchId,
            terms.tokenId,
            terms.launchToken,
            destination,
            tokenFeesCollected
        );
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external view returns (bytes4) {
        if (msg.sender != address(positionManager)) revert UnsupportedNft(msg.sender);
        return IERC721Receiver.onERC721Received.selector;
    }

    function _isValidReferralShare(uint16 referralShareBps) private pure returns (bool) {
        return
            referralShareBps == 0 || referralShareBps == 500;
    }
}
