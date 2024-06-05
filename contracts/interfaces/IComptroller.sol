// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.20;

interface IComptroller {
    /*** Events ***/

    /// @notice Emitted when an admin supports a market
    event MarketListed(address clToken);

    /// @notice Emitted when an account enters a market
    event MarketEntered(address clToken, address account);

    /// @notice Emitted when an account exits a market
    event MarketExited(address clToken, address account);

    /// @notice Emitted when close factor is updated by admin
    event NewCloseFactor(uint oldCloseFactorMantissa, uint newCloseFactorMantissa);

    /// @notice Emitted when a collateral factor is updated by admin
    event NewCollateralFactor(
        address clToken,
        uint oldCollateralFactorMantissa,
        uint newCollateralFactorMantissa
    );

    /// @notice Emitted when liquidation incentive is updated by admin
    event NewLiquidationIncentive(
        uint oldLiquidationIncentiveMantissa,
        uint newLiquidationIncentiveMantissa
    );

    /// @notice Emitted when price oracle is updated
    event NewPriceOracle(address oldPriceOracle, address newPriceOracle);

    /// @notice Emitted when pause guardian is updated
    event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);

    /// @notice Emitted when an action is paused globally
    event ActionPaused(string action, bool pauseState);

    /// @notice Emitted when an action is paused on a market
    event ActionPaused(address indexed clToken, string action, bool pauseState);

    /// @notice Emitted when a new borrow-side CLR speed is calculated for a market
    event ClrBorrowSpeedUpdated(address indexed clToken, uint newSpeed);

    /// @notice Emitted when a new supply-side CLR speed is calculated for a market
    event ClrSupplySpeedUpdated(address indexed clToken, uint newSpeed);

    /// @notice Emitted when a new CLR speed is set for a contributor
    event ContributorClrSpeedUpdated(address indexed contributor, uint newSpeed);

    /// @notice Emitted when CLR is distributed to a supplier
    event DistributedSupplierClr(
        address indexed clToken,
        address indexed supplier,
        uint clrDelta,
        uint clrSupplyIndex
    );

    /// @notice Emitted when CLR is distributed to a borrower
    event DistributedBorrowerClr(
        address indexed clToken,
        address indexed borrower,
        uint clrDelta,
        uint clrBorrowIndex
    );

    /// @notice Emitted when borrow cap for a clToken is updated
    event NewBorrowCap(address indexed clToken, uint newBorrowCap);

    /// @notice Emitted when borrow cap guardian is updated
    event NewBorrowCapGuardian(address oldBorrowCapGuardian, address newBorrowCapGuardian);

    /// @notice Emitted when CLR is granted by admin
    event ClrGranted(address recipient, uint amount);

    /*** Errors ***/

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
    error SetCollFactorWithoutPrice();
    error InvalidCollateralFactor();

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