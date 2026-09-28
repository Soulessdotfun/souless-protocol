// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ILaunchFeeVault {
    function creditLaunchFee(
        bytes32 launchId,
        address payer,
        address protectionHolderRecipient,
        uint256 totalAmount,
        uint256 protectionHolderAmount,
        bytes32 feePolicyVersionHash
    ) external;
}
