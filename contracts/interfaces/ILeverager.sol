// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILeverager {
    struct UserData {
        address user;
        uint256 tokenAmount;
        IERC20 borrowedToken;
        uint256 borrowedAmount;
        IERC20 tokenToLoop;
    }

    error InvalidMarket();
    error MarketIsNotListed();
    error AlreadyAllowedMarket();
    error NotAllowedMarket();
    error NotBalancerVault();

    event ProtocolFeeUpdated(uint256 _newFee);
}
