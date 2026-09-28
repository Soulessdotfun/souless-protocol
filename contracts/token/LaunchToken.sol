// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";

contract LaunchToken is Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable {
    error ZeroMarket();
    error InvalidFixedSupply();

    constructor() {
        _disableInitializers();
    }

    function initialize(
        string calldata name_,
        string calldata symbol_,
        uint256 fixedSupply,
        address market
    ) external initializer {
        if (market == address(0)) revert ZeroMarket();
        if (fixedSupply == 0) revert InvalidFixedSupply();

        __ERC20_init(name_, symbol_);
        __ERC20Burnable_init();
        _mint(market, fixedSupply);
    }
}
