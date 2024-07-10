// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IFlashLoanRecipient } from "./balancer/IFlashLoanRecipient.sol";

interface ILeverage is IFlashLoanRecipient {
    struct UserData {
        address user;
        address borrowedToken;
        uint256 borrowedAmount;
    }

    error InvalidMarket();
    error MarketIsNotListed();
    error AlreadyAllowedMarket();
    error NotAllowedMarket();
    error NotBalancerVault();
    error TooMuchBorrow();
    error InvalidLoanData();

    event AddMarket(address indexed _clToken, address indexed _underlying);

    event RemoveMarket(address indexed _clToken, address indexed _underlying);
}
