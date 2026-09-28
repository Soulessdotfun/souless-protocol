// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ITokenFeeReserve {
    function burn(address token, uint256 amount) external;
}
