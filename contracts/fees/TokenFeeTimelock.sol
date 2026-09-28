// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPermanentLpLocker} from "../interfaces/IPermanentLpLocker.sol";
import {ITokenFeeReserve} from "../interfaces/ITokenFeeReserve.sol";

contract TokenFeeTimelock is ReentrancyGuard {
    uint64 public constant DELAY = 72 hours;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    enum ActionKind {
        COLLECT_TOKEN_FEES,
        BURN_RESERVE_TOKENS
    }

    struct Action {
        ActionKind kind;
        bytes32 launchId;
        address token;
        address destination;
        uint256 amount;
        uint64 executableAt;
        bool executed;
        bool canceled;
    }

    address public immutable proposer;
    IPermanentLpLocker public immutable lpLocker;
    ITokenFeeReserve public immutable tokenFeeReserve;
    mapping(bytes32 actionId => Action action) private _actions;

    error ZeroAddress();
    error InvalidAction();
    error InvalidDestination(address destination);
    error Unauthorized();
    error ActionAlreadyScheduled(bytes32 actionId);
    error ActionNotScheduled(bytes32 actionId);
    error ActionNotReady(uint64 executableAt);
    error ActionUnavailable(bytes32 actionId);

    event ActionScheduled(
        bytes32 indexed actionId,
        ActionKind indexed kind,
        bytes32 indexed launchId,
        address token,
        uint256 amount,
        address destination,
        address proposer,
        uint64 executableAt
    );
    event ActionCanceled(bytes32 indexed actionId, address indexed proposer);
    event ActionExecuted(
        bytes32 indexed actionId,
        ActionKind indexed kind,
        bytes32 indexed launchId,
        address token,
        uint256 amount,
        address destination,
        address executor
    );

    constructor(address proposer_, address lpLocker_, address tokenFeeReserve_) {
        if (proposer_ == address(0) || lpLocker_ == address(0) || tokenFeeReserve_ == address(0)) {
            revert ZeroAddress();
        }
        proposer = proposer_;
        lpLocker = IPermanentLpLocker(lpLocker_);
        tokenFeeReserve = ITokenFeeReserve(tokenFeeReserve_);
    }

    function scheduleTokenFeeCollection(
        bytes32 launchId,
        address destination,
        bytes32 salt
    ) external returns (bytes32 actionId) {
        _requireProposer();
        if (destination != address(tokenFeeReserve) && destination != BURN_ADDRESS) {
            revert InvalidDestination(destination);
        }
        IPermanentLpLocker.PositionTerms memory terms = lpLocker.positionTerms(launchId);
        if (terms.tokenId == 0 || terms.launchToken == address(0)) revert InvalidAction();
        actionId = collectionActionId(launchId, terms.launchToken, destination, salt);
        _schedule(
            actionId,
            Action({
                kind: ActionKind.COLLECT_TOKEN_FEES,
                launchId: launchId,
                token: terms.launchToken,
                destination: destination,
                amount: 0,
                executableAt: 0,
                executed: false,
                canceled: false
            })
        );
    }

    function scheduleReserveBurn(
        address token,
        uint256 amount,
        bytes32 salt
    ) external returns (bytes32 actionId) {
        _requireProposer();
        if (token == address(0) || amount == 0) revert InvalidAction();
        actionId = reserveBurnActionId(token, amount, salt);
        _schedule(
            actionId,
            Action({
                kind: ActionKind.BURN_RESERVE_TOKENS,
                launchId: bytes32(0),
                token: token,
                destination: BURN_ADDRESS,
                amount: amount,
                executableAt: 0,
                executed: false,
                canceled: false
            })
        );
    }

    function cancel(bytes32 actionId) external {
        _requireProposer();
        Action storage action = _actions[actionId];
        if (action.executableAt == 0) revert ActionNotScheduled(actionId);
        if (action.executed || action.canceled) revert ActionUnavailable(actionId);
        action.canceled = true;
        emit ActionCanceled(actionId, msg.sender);
    }

    function execute(bytes32 actionId) external nonReentrant returns (uint256 amount) {
        Action storage action = _actions[actionId];
        if (action.executableAt == 0) revert ActionNotScheduled(actionId);
        if (action.executed || action.canceled) revert ActionUnavailable(actionId);
        if (block.timestamp < action.executableAt) revert ActionNotReady(action.executableAt);
        action.executed = true;
        if (action.kind == ActionKind.COLLECT_TOKEN_FEES) {
            amount = lpLocker.collectTokenFees(action.launchId, action.destination);
        } else {
            amount = action.amount;
            tokenFeeReserve.burn(action.token, amount);
        }
        emit ActionExecuted(
            actionId,
            action.kind,
            action.launchId,
            action.token,
            amount,
            action.destination,
            msg.sender
        );
    }

    function getAction(bytes32 actionId) external view returns (Action memory) {
        return _actions[actionId];
    }

    function collectionActionId(
        bytes32 launchId,
        address token,
        address destination,
        bytes32 salt
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encode(ActionKind.COLLECT_TOKEN_FEES, launchId, token, destination, uint256(0), salt)
        );
    }

    function reserveBurnActionId(
        address token,
        uint256 amount,
        bytes32 salt
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ActionKind.BURN_RESERVE_TOKENS,
                bytes32(0),
                token,
                BURN_ADDRESS,
                amount,
                salt
            )
        );
    }

    function _schedule(bytes32 actionId, Action memory action_) private {
        if (_actions[actionId].executableAt != 0) revert ActionAlreadyScheduled(actionId);
        uint64 executableAt = uint64(block.timestamp + DELAY);
        action_.executableAt = executableAt;
        _actions[actionId] = action_;
        emit ActionScheduled(
            actionId,
            action_.kind,
            action_.launchId,
            action_.token,
            action_.amount,
            action_.destination,
            msg.sender,
            executableAt
        );
    }

    function _requireProposer() private view {
        if (msg.sender != proposer) revert Unauthorized();
    }
}
