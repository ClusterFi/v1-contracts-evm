// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.20;

abstract contract ComptrollerInterface {
    error ExitMarketGetAccountSnapshotFailed();
    error MintIsPaused();
    error BorrowIsPaused();
    error ZeroRedeemTokens();
    error SenderMustBeClToken();
    error BorrowCapReached();
    
    /// @notice Indicator that this is a Comptroller contract (for inspection)
    bool public constant isComptroller = true;

    /*** Assets You Are In ***/

    function enterMarkets(address[] calldata clTokens) external virtual returns (uint[] memory);

    function exitMarket(address clToken) external virtual returns (uint);

    /*** Policy Hooks ***/

    function mintAllowed(address clToken, address minter, uint mintAmount) external virtual returns (uint);

    function mintVerify(address clToken, address minter, uint mintAmount, uint mintTokens) external virtual;

    function redeemAllowed(address clToken, address redeemer, uint redeemTokens) external virtual returns (uint);

    function redeemVerify(address clToken, address redeemer, uint redeemAmount, uint redeemTokens) external virtual;

    function borrowAllowed(address clToken, address borrower, uint borrowAmount) external virtual returns (uint);

    function borrowVerify(address clToken, address borrower, uint borrowAmount) external virtual;

    function repayBorrowAllowed(
        address clToken,
        address payer,
        address borrower,
        uint repayAmount
    ) external virtual returns (uint);

    function repayBorrowVerify(
        address clToken,
        address payer,
        address borrower,
        uint repayAmount,
        uint borrowerIndex
    ) external virtual;

    function liquidateBorrowAllowed(
        address clTokenBorrowed,
        address clTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount
    ) external virtual returns (uint);

    function liquidateBorrowVerify(
        address clTokenBorrowed,
        address clTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount,
        uint seizeTokens
    ) external virtual;

    function seizeAllowed(
        address clTokenCollateral,
        address clTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external virtual returns (uint);

    function seizeVerify(
        address clTokenCollateral,
        address clTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external virtual;

    function transferAllowed(
        address clToken,
        address src,
        address dst,
        uint transferTokens
    ) external virtual returns (uint);

    function transferVerify(address clToken, address src, address dst, uint transferTokens) external virtual;

    /*** Liquidity/Liquidation Calculations ***/

    function liquidateCalculateSeizeTokens(
        address clTokenBorrowed,
        address clTokenCollateral,
        uint repayAmount
    ) external view virtual returns (uint, uint);
}
