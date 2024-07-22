// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.20;

/**
 * @title IClToken
 * @notice Defines the basic interface for ClToken
 * @author Cluster
 */
interface IClToken {
    /*** Structs ***/

    /**
     * @notice Struct for borrow balance information
     * @param principal Total balance (with accrued interest), after applying the most recent balance-changing action
     * @param interestIndex Global borrowIndex as of the most recent balance-changing action
     */
    struct BorrowSnapshot {
        uint principal;
        uint interestIndex;
    }

    /*** Errors ***/

    error NotAdmin();
    error OnlyOnceInitialization();
    error ZeroExchangeRate();
    error NotComptroller();
    error BorrowRateTooHigh();
    error RedeemTokensOrUnderlyingsMustBeZero();
    error LiquidateSeizeTooMuch();

    error TransferNotAllowed();

    error MintFreshnessCheck();

    error RedeemFreshnessCheck();
    error RedeemTransferOutNotPossible();

    error BorrowFreshnessCheck();
    error BorrowCashNotAvailable();

    error RepayBorrowFreshnessCheck();

    error LiquidateFreshnessCheck();
    error LiquidateCollateralFreshnessCheck();
    error LiquidateLiquidatorIsBorrower();
    error LiquidateCloseAmountIsZero();
    error LiquidateCloseAmountIsUintMax();

    error LiquidateSeizeLiquidatorIsBorrower();

    error AcceptAdminPendingAdminCheck();

    error SetComptrollerOwnerCheck();
    error SetPendingAdminOwnerCheck();

    error SetReserveFactorAdminCheck();
    error SetReserveFactorFreshCheck();
    error SetReserveFactorBoundsCheck();

    error AddReservesFactorFreshCheck(uint256 actualAddAmount);

    error ReduceReservesAdminCheck();
    error ReduceReservesFreshCheck();
    error ReduceReservesCashNotAvailable();
    error ReduceReservesCashValidation();

    error SetInterestRateModelOwnerCheck();
    error SetInterestRateModelFreshCheck();
    error InvalidInterestRateModel();

    /*** Market Events ***/

    /**
     * @notice Event emitted when interest is accrued
     */
    event AccrueInterest(
        uint cashPrior,
        uint interestAccumulated,
        uint borrowIndex,
        uint totalBorrows
    );

    /**
     * @notice Event emitted when tokens are minted
     */
    event Mint(address minter, uint mintAmount, uint mintTokens);

    /**
     * @notice Event emitted when tokens are redeemed
     */
    event Redeem(address redeemer, uint redeemAmount, uint redeemTokens);

    /**
     * @notice Event emitted when underlying is borrowed
     */
    event Borrow(address borrower, uint borrowAmount, uint accountBorrows, uint totalBorrows);

    /**
     * @notice Event emitted when a borrow is repaid
     */
    event RepayBorrow(
        address payer,
        address borrower,
        uint repayAmount,
        uint accountBorrows,
        uint totalBorrows
    );

    /**
     * @notice Event emitted when a borrow is liquidated
     */
    event LiquidateBorrow(
        address liquidator,
        address borrower,
        uint repayAmount,
        address clTokenCollateral,
        uint seizeTokens
    );

    /*** Admin Events ***/

    /**
     * @notice Event emitted when pendingAdmin is updated
     */
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    /**
     * @notice Event emitted when pendingAdmin is accepted, which means admin is updated
     */
    event NewAdmin(address oldAdmin, address newAdmin);

    /**
     * @notice Event emitted when comptroller is updated
     */
    event NewComptroller(address oldComptroller, address newComptroller);

    /**
     * @notice Event emitted when interestRateModel is updated
     */
    event NewMarketInterestRateModel(address oldInterestRateModel, address newInterestRateModel);

    /**
     * @notice Event emitted when the reserve factor is updated
     */
    event NewReserveFactor(uint oldReserveFactorMantissa, uint newReserveFactorMantissa);

    /**
     * @notice Event emitted when the reserves are added
     */
    event ReservesAdded(address benefactor, uint addAmount, uint newTotalReserves);

    /**
     * @notice Event emitted when the reserves are reduced
     */
    event ReservesReduced(address admin, uint reduceAmount, uint newTotalReserves);

    /**
     * @notice EIP20 Transfer event
     */
    event Transfer(address indexed from, address indexed to, uint amount);

    /**
     * @notice EIP20 Approval event
     */
    event Approval(address indexed owner, address indexed spender, uint amount);

    /*** View Functions ***/

    function isClToken() external view returns (bool);
    function comptroller() external view returns (address);
    function accrualBlockNumber() external view returns (uint);
    function borrowIndex() external view returns (uint);
    function reserveFactorMantissa() external view returns (uint);
    function totalBorrows() external view returns (uint);
    function totalSupply() external view returns (uint);

    /*** User Interface ***/

    function transfer(address dst, uint amount) external returns (bool);
    function transferFrom(address src, address dst, uint amount) external returns (bool);
    function approve(address spender, uint amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function balanceOfUnderlying(address owner) external returns (uint);
    function getAccountSnapshot(address account) external view returns (uint, uint, uint);
    function borrowRatePerBlock() external view returns (uint);
    function supplyRatePerBlock() external view returns (uint);
    function totalBorrowsCurrent() external returns (uint);
    function borrowBalanceCurrent(address account) external returns (uint);
    function borrowBalanceStored(address account) external view returns (uint);
    function exchangeRateCurrent() external returns (uint);
    function exchangeRateStored() external view returns (uint);
    function getCash() external view returns (uint);
    function accrueInterest() external;
    function seize(address liquidator, address borrower, uint seizeTokens) external;

    /*** Admin Functions ***/

    function setPendingAdmin(address payable _newPendingAdmin) external;
    function acceptAdmin() external;
    function setComptroller(address _newComptroller) external;
    function setReserveFactor(uint _newReserveFactorMantissa) external;
    function reduceReserves(uint _reduceAmount) external;
    function setInterestRateModel(address _newInterestRateModel) external;
}
