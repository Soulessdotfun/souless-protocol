// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LaunchToken} from "./LaunchToken.sol";

contract TokenFactory is AccessControl {
    bytes32 public constant TOKEN_DEPLOYER_ROLE = keccak256("TOKEN_DEPLOYER_ROLE");

    address public immutable tokenImplementation;
    mapping(bytes32 launchId => address token) public tokenForLaunch;

    error ZeroAddress();
    error InvalidLaunchIdentifier();
    error InvalidTokenNameLength();
    error InvalidTokenSymbol();
    error InvalidFixedSupply();
    error LaunchTokenAlreadyDeployed(bytes32 launchId, address token);
    error TokenSupplyPostconditionFailed(address token);

    event LaunchTokenDeployed(
        bytes32 indexed launchId,
        address indexed token,
        address indexed market,
        uint256 fixedSupply
    );

    constructor(address admin, address tokenDeployer, address implementation) {
        if (
            admin == address(0) ||
            tokenDeployer == address(0) ||
            implementation == address(0)
        ) revert ZeroAddress();
        if (implementation.code.length == 0) revert ZeroAddress();

        tokenImplementation = implementation;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(TOKEN_DEPLOYER_ROLE, tokenDeployer);
    }

    function deployToken(
        bytes32 launchId,
        string calldata name,
        string calldata symbol,
        uint256 fixedSupply,
        address market
    ) external onlyRole(TOKEN_DEPLOYER_ROLE) returns (address token) {
        if (launchId == bytes32(0)) revert InvalidLaunchIdentifier();
        if (market == address(0)) revert ZeroAddress();
        if (fixedSupply == 0) revert InvalidFixedSupply();
        _validateMetadata(name, symbol);

        address existing = tokenForLaunch[launchId];
        if (existing != address(0)) revert LaunchTokenAlreadyDeployed(launchId, existing);

        token = Clones.cloneDeterministic(tokenImplementation, _salt(launchId));
        LaunchToken(token).initialize(name, symbol, fixedSupply, market);

        if (IERC20(token).totalSupply() != fixedSupply || IERC20(token).balanceOf(market) != fixedSupply) {
            revert TokenSupplyPostconditionFailed(token);
        }

        tokenForLaunch[launchId] = token;
        emit LaunchTokenDeployed(launchId, token, market, fixedSupply);
    }

    function predictTokenAddress(bytes32 launchId) external view returns (address) {
        if (launchId == bytes32(0)) revert InvalidLaunchIdentifier();
        return Clones.predictDeterministicAddress(tokenImplementation, _salt(launchId), address(this));
    }

    function _salt(bytes32 launchId) private view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, launchId));
    }

    function _validateMetadata(string calldata name, string calldata symbol) private pure {
        bytes memory nameBytes = bytes(name);
        bytes memory symbolBytes = bytes(symbol);
        if (nameBytes.length == 0 || nameBytes.length > 32) revert InvalidTokenNameLength();
        if (symbolBytes.length < 2 || symbolBytes.length > 10) revert InvalidTokenSymbol();

        for (uint256 index = 0; index < symbolBytes.length; index++) {
            bytes1 character = symbolBytes[index];
            bool uppercaseLetter = character >= 0x41 && character <= 0x5A;
            bool number = character >= 0x30 && character <= 0x39;
            if (!uppercaseLetter && !number) revert InvalidTokenSymbol();
        }
    }
}
