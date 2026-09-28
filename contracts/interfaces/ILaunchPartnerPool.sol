// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ILaunchPartnerPool {
    function campaignActive() external view returns (bool);
    function creditCampaignFees(uint256 amount) external;
}
