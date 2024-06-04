// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.20;

interface IComptroller {
    error ExitMarketGetAccountSnapshotFailed();
    error MintIsPaused();
    error BorrowIsPaused();
    error ZeroRedeemTokens();
    error SenderMustBeClToken();
    error BorrowCapReached();
    error SeizeIsPaused();
    error TransferIsPaused();
    error NotAdmin();
    error MarketAlreadyAdded();
    error NotAdminOrBorrowCapGuardian();
    error ArrayLengthMismatch();
    error MarketIsNotListed();
    error MarketIsAlreadyListed();
    error NotAdminOrPauseGuardian();
    error NotUnitrollerAdmin();
    error ChangeNotAuthorized();
    error InsufficientClrForGrant();
    error RepayShouldBeLessThanTotalBorrow();

    function isComptroller() external view returns (bool);

    /*** Assets You Are In ***/

    function enterMarkets(address[] calldata clTokens) external returns (uint[] memory);

    function exitMarket(address clToken) external returns (uint);

    /*** Policy Hooks ***/

    function mintAllowed(
        address clToken,
        address minter,
        uint mintAmount
    ) external returns (uint);

    function mintVerify(
        address clToken,
        address minter,
        uint mintAmount,
        uint mintTokens
    ) external;

    function redeemAllowed(
        address clToken,
        address redeemer,
        uint redeemTokens
    ) external returns (uint);

    function redeemVerify(
        address clToken,
        address redeemer,
        uint redeemAmount,
        uint redeemTokens
    ) external;

    function borrowAllowed(
        address clToken,
        address borrower,
        uint borrowAmount
    ) external returns (uint);

    function borrowVerify(address clToken, address borrower, uint borrowAmount) external;

    function repayBorrowAllowed(
        address clToken,
        address payer,
        address borrower,
        uint repayAmount
    ) external returns (uint);

    function repayBorrowVerify(
        address clToken,
        address payer,
        address borrower,
        uint repayAmount,
        uint borrowerIndex
    ) external;

    function liquidateBorrowAllowed(
        address clTokenBorrowed,
        address clTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount
    ) external returns (uint);

    function liquidateBorrowVerify(
        address clTokenBorrowed,
        address clTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount,
        uint seizeTokens
    ) external;

    function seizeAllowed(
        address clTokenCollateral,
        address clTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external returns (uint);

    function seizeVerify(
        address clTokenCollateral,
        address clTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external;

    function transferAllowed(
        address clToken,
        address src,
        address dst,
        uint transferTokens
    ) external returns (uint);

    function transferVerify(
        address clToken,
        address src,
        address dst,
        uint transferTokens
    ) external;

    /*** Liquidity/Liquidation Calculations ***/

    function liquidateCalculateSeizeTokens(
        address clTokenBorrowed,
        address clTokenCollateral,
        uint repayAmount
    ) external view returns (uint);
}
