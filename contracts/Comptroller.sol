// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.20;

import "./tokens/ClToken.sol";
import "./tokens/Cluster.sol";
import "./base/PriceOracle.sol";
import "./base/ComptrollerInterface.sol";
import "./ErrorReporter.sol";
import "./ComptrollerStorage.sol";
import "./Unitroller.sol";

/**
 * @title Cluster's Comptroller Contract
 * @author Cluster
 */
contract Comptroller is ComptrollerV7Storage, ComptrollerInterface, ComptrollerErrorReporter, ExponentialNoError {
    /// @notice Emitted when an admin supports a market
    event MarketListed(ClToken clToken);

    /// @notice Emitted when an account enters a market
    event MarketEntered(ClToken clToken, address account);

    /// @notice Emitted when an account exits a market
    event MarketExited(ClToken clToken, address account);

    /// @notice Emitted when close factor is changed by admin
    event NewCloseFactor(uint oldCloseFactorMantissa, uint newCloseFactorMantissa);

    /// @notice Emitted when a collateral factor is changed by admin
    event NewCollateralFactor(ClToken clToken, uint oldCollateralFactorMantissa, uint newCollateralFactorMantissa);

    /// @notice Emitted when liquidation incentive is changed by admin
    event NewLiquidationIncentive(uint oldLiquidationIncentiveMantissa, uint newLiquidationIncentiveMantissa);

    /// @notice Emitted when price oracle is changed
    event NewPriceOracle(PriceOracle oldPriceOracle, PriceOracle newPriceOracle);

    /// @notice Emitted when pause guardian is changed
    event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);

    /// @notice Emitted when an action is paused globally
    event ActionPaused(string action, bool pauseState);

    /// @notice Emitted when an action is paused on a market
    event ActionPaused(ClToken clToken, string action, bool pauseState);

    /// @notice Emitted when a new borrow-side CLR speed is calculated for a market
    event ClrBorrowSpeedUpdated(ClToken indexed clToken, uint newSpeed);

    /// @notice Emitted when a new supply-side CLR speed is calculated for a market
    event ClrSupplySpeedUpdated(ClToken indexed clToken, uint newSpeed);

    /// @notice Emitted when a new CLR speed is set for a contributor
    event ContributorClrSpeedUpdated(address indexed contributor, uint newSpeed);

    /// @notice Emitted when CLR is distributed to a supplier
    event DistributedSupplierClr(ClToken indexed clToken, address indexed supplier, uint clrDelta, uint clrSupplyIndex);

    /// @notice Emitted when CLR is distributed to a borrower
    event DistributedBorrowerClr(ClToken indexed clToken, address indexed borrower, uint clrDelta, uint clrBorrowIndex);

    /// @notice Emitted when borrow cap for a clToken is changed
    event NewBorrowCap(ClToken indexed clToken, uint newBorrowCap);

    /// @notice Emitted when borrow cap guardian is changed
    event NewBorrowCapGuardian(address oldBorrowCapGuardian, address newBorrowCapGuardian);

    /// @notice Emitted when CLR is granted by admin
    event ClrGranted(address recipient, uint amount);

    /// @notice Emitted when CLR accrued for a user has been manually adjusted.
    event ClrAccruedAdjusted(address indexed user, uint oldClrAccrued, uint newClrAccrued);

    /// @notice Emitted when CLR receivable for a user has been updated.
    event ClrReceivableUpdated(address indexed user, uint oldClrReceivable, uint newClrReceivable);

    /// @notice The initial CLR index for a market
    uint224 public constant clrInitialIndex = 1e36;

    // closeFactorMantissa must be strictly greater than this value
    uint internal constant closeFactorMinMantissa = 0.05e18; // 0.05

    // closeFactorMantissa must not exceed this value
    uint internal constant closeFactorMaxMantissa = 0.9e18; // 0.9

    // No collateralFactorMantissa may exceed this value
    uint internal constant collateralFactorMaxMantissa = 0.9e18; // 0.9

    constructor() {
        admin = msg.sender;
    }

    /*** Assets You Are In ***/

    /**
     * @notice Returns the assets an account has entered
     * @param account The address of the account to pull assets for
     * @return A dynamic list with the assets the account has entered
     */
    function getAssetsIn(address account) external view returns (ClToken[] memory) {
        ClToken[] memory assetsIn = accountAssets[account];

        return assetsIn;
    }

    /**
     * @notice Returns whether the given account is entered in the given asset
     * @param account The address of the account to check
     * @param clToken The clToken to check
     * @return True if the account is in the asset, otherwise false.
     */
    function checkMembership(address account, ClToken clToken) external view returns (bool) {
        return markets[address(clToken)].accountMembership[account];
    }

    /**
     * @notice Add assets to be included in account liquidity calculation
     * @param clTokens The list of addresses of the clToken markets to be enabled
     * @return Success indicator for whether each corresponding market was entered
     */
    function enterMarkets(address[] memory clTokens) public override returns (uint[] memory) {
        uint len = clTokens.length;

        uint[] memory results = new uint[](len);
        for (uint i = 0; i < len; i++) {
            ClToken clToken = ClToken(clTokens[i]);

            results[i] = uint(addToMarketInternal(clToken, msg.sender));
        }

        return results;
    }

    /**
     * @notice Add the market to the borrower's "assets in" for liquidity calculations
     * @param clToken The market to enter
     * @param borrower The address of the account to modify
     * @return Success indicator for whether the market was entered
     */
    function addToMarketInternal(ClToken clToken, address borrower) internal returns (Error) {
        Market storage marketToJoin = markets[address(clToken)];

        if (!marketToJoin.isListed) {
            // market is not listed, cannot join
            return Error.MARKET_NOT_LISTED;
        }

        if (marketToJoin.accountMembership[borrower] == true) {
            // already joined
            return Error.NO_ERROR;
        }

        // survived the gauntlet, add to list
        // NOTE: we store these somewhat redundantly as a significant optimization
        //  this avoids having to iterate through the list for the most common use cases
        //  that is, only when we need to perform liquidity checks
        //  and not whenever we want to check if an account is in a particular market
        marketToJoin.accountMembership[borrower] = true;
        accountAssets[borrower].push(clToken);

        emit MarketEntered(clToken, borrower);

        return Error.NO_ERROR;
    }

    /**
     * @notice Removes asset from sender's account liquidity calculation
     * @dev Sender must not have an outstanding borrow balance in the asset,
     *  or be providing necessary collateral for an outstanding borrow.
     * @param clTokenAddress The address of the asset to be removed
     * @return Whether or not the account successfully exited the market
     */
    function exitMarket(address clTokenAddress) external override returns (uint) {
        ClToken clToken = ClToken(clTokenAddress);
        /* Get sender tokensHeld and amountOwed underlying from the clToken */
        (uint oErr, uint tokensHeld, uint amountOwed, ) = clToken.getAccountSnapshot(msg.sender);
        require(oErr == 0, "exitMarket: getAccountSnapshot failed"); // semi-opaque error code

        /* Fail if the sender has a borrow balance */
        if (amountOwed != 0) {
            return fail(Error.NONZERO_BORROW_BALANCE, FailureInfo.EXIT_MARKET_BALANCE_OWED);
        }

        /* Fail if the sender is not permitted to redeem all of their tokens */
        uint allowed = redeemAllowedInternal(clTokenAddress, msg.sender, tokensHeld);
        if (allowed != 0) {
            return failOpaque(Error.REJECTION, FailureInfo.EXIT_MARKET_REJECTION, allowed);
        }

        Market storage marketToExit = markets[address(clToken)];

        /* Return true if the sender is not already ‘in’ the market */
        if (!marketToExit.accountMembership[msg.sender]) {
            return uint(Error.NO_ERROR);
        }

        /* Set clToken account membership to false */
        delete marketToExit.accountMembership[msg.sender];

        /* Delete clToken from the account’s list of assets */
        // load into memory for faster iteration
        ClToken[] memory userAssetList = accountAssets[msg.sender];
        uint len = userAssetList.length;
        uint assetIndex = len;
        for (uint i = 0; i < len; i++) {
            if (userAssetList[i] == clToken) {
                assetIndex = i;
                break;
            }
        }

        // We *must* have found the asset in the list or our redundant data structure is broken
        assert(assetIndex < len);

        // copy last item in list to location of item to be removed, reduce length by 1
        ClToken[] storage storedList = accountAssets[msg.sender];
        storedList[assetIndex] = storedList[storedList.length - 1];
        storedList.pop();

        emit MarketExited(clToken, msg.sender);

        return uint(Error.NO_ERROR);
    }

    /*** Policy Hooks ***/

    /**
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param clToken The market to verify the mint against
     * @param minter The account which would get the minted tokens
     * @param mintAmount The amount of underlying being supplied to the market in exchange for tokens
     * @return 0 if the mint is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function mintAllowed(address clToken, address minter, uint mintAmount) external override returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!mintGuardianPaused[clToken], "mint is paused");

        // Shh - currently unused
        minter;
        mintAmount;

        if (!markets[clToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        // Keep the flywheel moving
        updateClrSupplyIndex(clToken);
        distributeSupplierClr(clToken, minter);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates mint and reverts on rejection. May emit logs.
     * @param clToken Asset being minted
     * @param minter The address minting the tokens
     * @param actualMintAmount The amount of the underlying asset being minted
     * @param mintTokens The number of tokens being minted
     */
    function mintVerify(address clToken, address minter, uint actualMintAmount, uint mintTokens) external override {
        // Shh - currently unused
        clToken;
        minter;
        actualMintAmount;
        mintTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the account should be allowed to redeem tokens in the given market
     * @param clToken The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param redeemTokens The number of clTokens to exchange for the underlying asset in the market
     * @return 0 if the redeem is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function redeemAllowed(address clToken, address redeemer, uint redeemTokens) external override returns (uint) {
        uint allowed = redeemAllowedInternal(clToken, redeemer, redeemTokens);
        if (allowed != uint(Error.NO_ERROR)) {
            return allowed;
        }

        // Keep the flywheel moving
        updateClrSupplyIndex(clToken);
        distributeSupplierClr(clToken, redeemer);

        return uint(Error.NO_ERROR);
    }

    function redeemAllowedInternal(address clToken, address redeemer, uint redeemTokens) internal view returns (uint) {
        if (!markets[clToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        /* If the redeemer is not 'in' the market, then we can bypass the liquidity check */
        if (!markets[clToken].accountMembership[redeemer]) {
            return uint(Error.NO_ERROR);
        }

        /* Otherwise, perform a hypothetical liquidity check to guard against shortfall */
        (Error err, , uint shortfall) = getHypotheticalAccountLiquidityInternal(
            redeemer,
            ClToken(clToken),
            redeemTokens,
            0
        );
        if (err != Error.NO_ERROR) {
            return uint(err);
        }
        if (shortfall > 0) {
            return uint(Error.INSUFFICIENT_LIQUIDITY);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates redeem and reverts on rejection. May emit logs.
     * @param clToken Asset being redeemed
     * @param redeemer The address redeeming the tokens
     * @param redeemAmount The amount of the underlying asset being redeemed
     * @param redeemTokens The number of tokens being redeemed
     */
    function redeemVerify(address clToken, address redeemer, uint redeemAmount, uint redeemTokens) external override {
        // Shh - currently unused
        clToken;
        redeemer;

        // Require tokens is zero or amount is also zero
        if (redeemTokens == 0 && redeemAmount > 0) {
            revert("redeemTokens zero");
        }
    }

    /**
     * @notice Checks if the account should be allowed to borrow the underlying asset of the given market
     * @param clToken The market to verify the borrow against
     * @param borrower The account which would borrow the asset
     * @param borrowAmount The amount of underlying the account would borrow
     * @return 0 if the borrow is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function borrowAllowed(address clToken, address borrower, uint borrowAmount) external override returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!borrowGuardianPaused[clToken], "borrow is paused");

        if (!markets[clToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        if (!markets[clToken].accountMembership[borrower]) {
            // only clTokens may call borrowAllowed if borrower not in market
            require(msg.sender == clToken, "sender must be clToken");

            // attempt to add borrower to the market
            Error _err = addToMarketInternal(ClToken(msg.sender), borrower);
            if (_err != Error.NO_ERROR) {
                return uint(_err);
            }

            // it should be impossible to break the important invariant
            assert(markets[clToken].accountMembership[borrower]);
        }

        if (oracle.getUnderlyingPrice(ClToken(clToken)) == 0) {
            return uint(Error.PRICE_ERROR);
        }

        uint borrowCap = borrowCaps[clToken];
        // Borrow cap of 0 corresponds to unlimited borrowing
        if (borrowCap != 0) {
            uint totalBorrows = ClToken(clToken).totalBorrows();
            uint nextTotalBorrows = add_(totalBorrows, borrowAmount);
            require(nextTotalBorrows < borrowCap, "market borrow cap reached");
        }

        (Error _err, , uint shortfall) = getHypotheticalAccountLiquidityInternal(
            borrower,
            ClToken(clToken),
            0,
            borrowAmount
        );

        if (_err != Error.NO_ERROR) {
            return uint(_err);
        }
        if (shortfall > 0) {
            return uint(Error.INSUFFICIENT_LIQUIDITY);
        }

        // Keep the flywheel moving
        Exp memory borrowIndex = Exp({ mantissa: ClToken(clToken).borrowIndex() });
        updateClrBorrowIndex(clToken, borrowIndex);
        distributeBorrowerClr(clToken, borrower, borrowIndex);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates borrow and reverts on rejection. May emit logs.
     * @param clToken Asset whose underlying is being borrowed
     * @param borrower The address borrowing the underlying
     * @param borrowAmount The amount of the underlying asset requested to borrow
     */
    function borrowVerify(address clToken, address borrower, uint borrowAmount) external override {
        // Shh - currently unused
        clToken;
        borrower;
        borrowAmount;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the account should be allowed to repay a borrow in the given market
     * @param clToken The market to verify the repay against
     * @param payer The account which would repay the asset
     * @param borrower The account which would borrowed the asset
     * @param repayAmount The amount of the underlying asset the account would repay
     * @return 0 if the repay is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function repayBorrowAllowed(
        address clToken,
        address payer,
        address borrower,
        uint repayAmount
    ) external override returns (uint) {
        // Shh - currently unused
        payer;
        borrower;
        repayAmount;

        if (!markets[clToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        // Keep the flywheel moving
        Exp memory borrowIndex = Exp({ mantissa: ClToken(clToken).borrowIndex() });
        updateClrBorrowIndex(clToken, borrowIndex);
        distributeBorrowerClr(clToken, borrower, borrowIndex);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates repayBorrow and reverts on rejection. May emit logs.
     * @param clToken Asset being repaid
     * @param payer The address repaying the borrow
     * @param borrower The address of the borrower
     * @param actualRepayAmount The amount of underlying being repaid
     */
    function repayBorrowVerify(
        address clToken,
        address payer,
        address borrower,
        uint actualRepayAmount,
        uint borrowerIndex
    ) external override {
        // Shh - currently unused
        clToken;
        payer;
        borrower;
        actualRepayAmount;
        borrowerIndex;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the liquidation should be allowed to occur
     * @param clTokenBorrowed Asset which was borrowed by the borrower
     * @param clTokenCollateral Asset which was used as collateral and will be seized
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param repayAmount The amount of underlying being repaid
     */
    function liquidateBorrowAllowed(
        address clTokenBorrowed,
        address clTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount
    ) external override returns (uint) {
        // Shh - currently unused
        liquidator;

        if (!markets[clTokenBorrowed].isListed || !markets[clTokenCollateral].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        uint borrowBalance = ClToken(clTokenBorrowed).borrowBalanceStored(borrower);

        /* allow accounts to be liquidated if the market is deprecated */
        if (isDeprecated(ClToken(clTokenBorrowed))) {
            require(borrowBalance >= repayAmount, "Can not repay more than the total borrow");
        } else {
            /* The borrower must have shortfall in order to be liquidatable */
            (Error err, , uint shortfall) = getAccountLiquidityInternal(borrower);
            if (err != Error.NO_ERROR) {
                return uint(err);
            }

            if (shortfall == 0) {
                return uint(Error.INSUFFICIENT_SHORTFALL);
            }

            /* The liquidator may not repay more than what is allowed by the closeFactor */
            uint maxClose = mul_ScalarTruncate(Exp({ mantissa: closeFactorMantissa }), borrowBalance);
            if (repayAmount > maxClose) {
                return uint(Error.TOO_MUCH_REPAY);
            }
        }
        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates liquidateBorrow and reverts on rejection. May emit logs.
     * @param clTokenBorrowed Asset which was borrowed by the borrower
     * @param clTokenCollateral Asset which was used as collateral and will be seized
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param actualRepayAmount The amount of underlying being repaid
     */
    function liquidateBorrowVerify(
        address clTokenBorrowed,
        address clTokenCollateral,
        address liquidator,
        address borrower,
        uint actualRepayAmount,
        uint seizeTokens
    ) external override {
        // Shh - currently unused
        clTokenBorrowed;
        clTokenCollateral;
        liquidator;
        borrower;
        actualRepayAmount;
        seizeTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the seizing of assets should be allowed to occur
     * @param clTokenCollateral Asset which was used as collateral and will be seized
     * @param clTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    function seizeAllowed(
        address clTokenCollateral,
        address clTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external override returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!seizeGuardianPaused, "seize is paused");

        // Shh - currently unused
        seizeTokens;

        if (!markets[clTokenCollateral].isListed || !markets[clTokenBorrowed].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        if (ClToken(clTokenCollateral).comptroller() != ClToken(clTokenBorrowed).comptroller()) {
            return uint(Error.COMPTROLLER_MISMATCH);
        }

        // Keep the flywheel moving
        updateClrSupplyIndex(clTokenCollateral);
        distributeSupplierClr(clTokenCollateral, borrower);
        distributeSupplierClr(clTokenCollateral, liquidator);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates seize and reverts on rejection. May emit logs.
     * @param clTokenCollateral Asset which was used as collateral and will be seized
     * @param clTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    function seizeVerify(
        address clTokenCollateral,
        address clTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external override {
        // Shh - currently unused
        clTokenCollateral;
        clTokenBorrowed;
        liquidator;
        borrower;
        seizeTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the account should be allowed to transfer tokens in the given market
     * @param clToken The market to verify the transfer against
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of clTokens to transfer
     * @return 0 if the transfer is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function transferAllowed(
        address clToken,
        address src,
        address dst,
        uint transferTokens
    ) external override returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!transferGuardianPaused, "transfer is paused");

        // Currently the only consideration is whether or not
        //  the src is allowed to redeem this many tokens
        uint allowed = redeemAllowedInternal(clToken, src, transferTokens);
        if (allowed != uint(Error.NO_ERROR)) {
            return allowed;
        }

        // Keep the flywheel moving
        updateClrSupplyIndex(clToken);
        distributeSupplierClr(clToken, src);
        distributeSupplierClr(clToken, dst);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates transfer and reverts on rejection. May emit logs.
     * @param clToken Asset being transferred
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of clTokens to transfer
     */
    function transferVerify(address clToken, address src, address dst, uint transferTokens) external override {
        // Shh - currently unused
        clToken;
        src;
        dst;
        transferTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /*** Liquidity/Liquidation Calculations ***/

    /**
     * @dev Local vars for avoiding stack-depth limits in calculating account liquidity.
     *  Note that `clTokenBalance` is the number of clTokens the account owns in the market,
     *  whereas `borrowBalance` is the amount of underlying that the account has borrowed.
     */
    struct AccountLiquidityLocalVars {
        uint sumCollateral;
        uint sumBorrowPlusEffects;
        uint clTokenBalance;
        uint borrowBalance;
        uint exchangeRateMantissa;
        uint oraclePriceMantissa;
        Exp collateralFactor;
        Exp exchangeRate;
        Exp oraclePrice;
        Exp tokensToDenom;
    }

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return (possible error code (semi-opaque),
                account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidity(address account) public view returns (uint, uint, uint) {
        (Error err, uint liquidity, uint shortfall) = getHypotheticalAccountLiquidityInternal(
            account,
            ClToken(address(0)),
            0,
            0
        );

        return (uint(err), liquidity, shortfall);
    }

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return (possible error code,
                account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidityInternal(address account) internal view returns (Error, uint, uint) {
        return getHypotheticalAccountLiquidityInternal(account, ClToken(address(0)), 0, 0);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param clTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @return (possible error code (semi-opaque),
                hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidity(
        address account,
        address clTokenModify,
        uint redeemTokens,
        uint borrowAmount
    ) public view returns (uint, uint, uint) {
        (Error err, uint liquidity, uint shortfall) = getHypotheticalAccountLiquidityInternal(
            account,
            ClToken(clTokenModify),
            redeemTokens,
            borrowAmount
        );
        return (uint(err), liquidity, shortfall);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param clTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @dev Note that we calculate the exchangeRateStored for each collateral clToken using stored data,
     *  without calculating accumulated interest.
     * @return (possible error code,
                hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidityInternal(
        address account,
        ClToken clTokenModify,
        uint redeemTokens,
        uint borrowAmount
    ) internal view returns (Error, uint, uint) {
        AccountLiquidityLocalVars memory vars; // Holds all our calculation results
        uint oErr;

        // For each asset the account is in
        ClToken[] memory assets = accountAssets[account];
        for (uint i = 0; i < assets.length; i++) {
            ClToken asset = assets[i];

            // Read the balances and exchange rate from the clToken
            (oErr, vars.clTokenBalance, vars.borrowBalance, vars.exchangeRateMantissa) = asset.getAccountSnapshot(
                account
            );
            if (oErr != 0) {
                // semi-opaque error code, we assume NO_ERROR == 0 is invariant between upgrades
                return (Error.SNAPSHOT_ERROR, 0, 0);
            }
            vars.collateralFactor = Exp({ mantissa: markets[address(asset)].collateralFactorMantissa });
            vars.exchangeRate = Exp({ mantissa: vars.exchangeRateMantissa });

            // Get the normalized price of the asset
            vars.oraclePriceMantissa = oracle.getUnderlyingPrice(asset);
            if (vars.oraclePriceMantissa == 0) {
                return (Error.PRICE_ERROR, 0, 0);
            }
            vars.oraclePrice = Exp({ mantissa: vars.oraclePriceMantissa });

            // Pre-compute a conversion factor from tokens -> ether (normalized price value)
            vars.tokensToDenom = mul_(mul_(vars.collateralFactor, vars.exchangeRate), vars.oraclePrice);

            // sumCollateral += tokensToDenom * clTokenBalance
            vars.sumCollateral = mul_ScalarTruncateAddUInt(vars.tokensToDenom, vars.clTokenBalance, vars.sumCollateral);

            // sumBorrowPlusEffects += oraclePrice * borrowBalance
            vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(
                vars.oraclePrice,
                vars.borrowBalance,
                vars.sumBorrowPlusEffects
            );

            // Calculate effects of interacting with clTokenModify
            if (asset == clTokenModify) {
                // redeem effect
                // sumBorrowPlusEffects += tokensToDenom * redeemTokens
                vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(
                    vars.tokensToDenom,
                    redeemTokens,
                    vars.sumBorrowPlusEffects
                );

                // borrow effect
                // sumBorrowPlusEffects += oraclePrice * borrowAmount
                vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(
                    vars.oraclePrice,
                    borrowAmount,
                    vars.sumBorrowPlusEffects
                );
            }
        }

        // These are safe, as the underflow condition is checked first
        if (vars.sumCollateral > vars.sumBorrowPlusEffects) {
            return (Error.NO_ERROR, vars.sumCollateral - vars.sumBorrowPlusEffects, 0);
        } else {
            return (Error.NO_ERROR, 0, vars.sumBorrowPlusEffects - vars.sumCollateral);
        }
    }

    /**
     * @notice Calculate number of tokens of collateral asset to seize given an underlying amount
     * @dev Used in liquidation (called in clToken.liquidateBorrowFresh)
     * @param clTokenBorrowed The address of the borrowed clToken
     * @param clTokenCollateral The address of the collateral clToken
     * @param actualRepayAmount The amount of clTokenBorrowed underlying to convert into clTokenCollateral tokens
     * @return (errorCode, number of clTokenCollateral tokens to be seized in a liquidation)
     */
    function liquidateCalculateSeizeTokens(
        address clTokenBorrowed,
        address clTokenCollateral,
        uint actualRepayAmount
    ) external view override returns (uint, uint) {
        /* Read oracle prices for borrowed and collateral markets */
        uint priceBorrowedMantissa = oracle.getUnderlyingPrice(ClToken(clTokenBorrowed));
        uint priceCollateralMantissa = oracle.getUnderlyingPrice(ClToken(clTokenCollateral));
        if (priceBorrowedMantissa == 0 || priceCollateralMantissa == 0) {
            return (uint(Error.PRICE_ERROR), 0);
        }

        /*
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
         *  seizeTokens = seizeAmount / exchangeRate
         *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
         */
        uint exchangeRateMantissa = ClToken(clTokenCollateral).exchangeRateStored(); // Note: reverts on error
        uint seizeTokens;
        Exp memory numerator;
        Exp memory denominator;
        Exp memory ratio;

        numerator = mul_(Exp({ mantissa: liquidationIncentiveMantissa }), Exp({ mantissa: priceBorrowedMantissa }));
        denominator = mul_(Exp({ mantissa: priceCollateralMantissa }), Exp({ mantissa: exchangeRateMantissa }));
        ratio = div_(numerator, denominator);

        seizeTokens = mul_ScalarTruncate(ratio, actualRepayAmount);

        return (uint(Error.NO_ERROR), seizeTokens);
    }

    /*** Admin Functions ***/

    /**
     * @notice Sets a new price oracle for the comptroller
     * @dev Admin function to set a new price oracle
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _setPriceOracle(PriceOracle newOracle) public returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_PRICE_ORACLE_OWNER_CHECK);
        }

        // Track the old oracle for the comptroller
        PriceOracle oldOracle = oracle;

        // Set comptroller's oracle to newOracle
        oracle = newOracle;

        // Emit NewPriceOracle(oldOracle, newOracle)
        emit NewPriceOracle(oldOracle, newOracle);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Sets the closeFactor used when liquidating borrows
     * @dev Admin function to set closeFactor
     * @param newCloseFactorMantissa New close factor, scaled by 1e18
     * @return uint 0=success, otherwise a failure
     */
    function _setCloseFactor(uint newCloseFactorMantissa) external returns (uint) {
        // Check caller is admin
        require(msg.sender == admin, "only admin can set close factor");

        uint oldCloseFactorMantissa = closeFactorMantissa;
        closeFactorMantissa = newCloseFactorMantissa;
        emit NewCloseFactor(oldCloseFactorMantissa, closeFactorMantissa);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Sets the collateralFactor for a market
     * @dev Admin function to set per-market collateralFactor
     * @param clToken The market to set the factor on
     * @param newCollateralFactorMantissa The new collateral factor, scaled by 1e18
     * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)
     */
    function _setCollateralFactor(ClToken clToken, uint newCollateralFactorMantissa) external returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_COLLATERAL_FACTOR_OWNER_CHECK);
        }

        // Verify market is listed
        Market storage market = markets[address(clToken)];
        if (!market.isListed) {
            return fail(Error.MARKET_NOT_LISTED, FailureInfo.SET_COLLATERAL_FACTOR_NO_EXISTS);
        }

        Exp memory newCollateralFactorExp = Exp({ mantissa: newCollateralFactorMantissa });

        // Check collateral factor <= 0.9
        Exp memory highLimit = Exp({ mantissa: collateralFactorMaxMantissa });
        if (lessThanExp(highLimit, newCollateralFactorExp)) {
            return fail(Error.INVALID_COLLATERAL_FACTOR, FailureInfo.SET_COLLATERAL_FACTOR_VALIDATION);
        }

        // If collateral factor != 0, fail if price == 0
        if (newCollateralFactorMantissa != 0 && oracle.getUnderlyingPrice(clToken) == 0) {
            return fail(Error.PRICE_ERROR, FailureInfo.SET_COLLATERAL_FACTOR_WITHOUT_PRICE);
        }

        // Set market's collateral factor to new collateral factor, remember old value
        uint oldCollateralFactorMantissa = market.collateralFactorMantissa;
        market.collateralFactorMantissa = newCollateralFactorMantissa;

        // Emit event with asset, old collateral factor, and new collateral factor
        emit NewCollateralFactor(clToken, oldCollateralFactorMantissa, newCollateralFactorMantissa);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Sets liquidationIncentive
     * @dev Admin function to set liquidationIncentive
     * @param newLiquidationIncentiveMantissa New liquidationIncentive scaled by 1e18
     * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)
     */
    function _setLiquidationIncentive(uint newLiquidationIncentiveMantissa) external returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_LIQUIDATION_INCENTIVE_OWNER_CHECK);
        }

        // Save current value for use in log
        uint oldLiquidationIncentiveMantissa = liquidationIncentiveMantissa;

        // Set liquidation incentive to new incentive
        liquidationIncentiveMantissa = newLiquidationIncentiveMantissa;

        // Emit event with old incentive, new incentive
        emit NewLiquidationIncentive(oldLiquidationIncentiveMantissa, newLiquidationIncentiveMantissa);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Add the market to the markets mapping and set it as listed
     * @dev Admin function to set isListed and add support for the market
     * @param clToken The address of the market (token) to list
     * @return uint 0=success, otherwise a failure. (See enum Error for details)
     */
    function _supportMarket(ClToken clToken) external returns (uint) {
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SUPPORT_MARKET_OWNER_CHECK);
        }

        if (markets[address(clToken)].isListed) {
            return fail(Error.MARKET_ALREADY_LISTED, FailureInfo.SUPPORT_MARKET_EXISTS);
        }

        clToken.isClToken(); // Sanity check to make sure its really a ClToken

        // Note that isClred is not in active use anymore
        Market storage newMarket = markets[address(clToken)];
        newMarket.isListed = true;
        newMarket.isClred = false;
        newMarket.collateralFactorMantissa = 0;

        _addMarketInternal(address(clToken));
        _initializeMarket(address(clToken));

        emit MarketListed(clToken);

        return uint(Error.NO_ERROR);
    }

    function _addMarketInternal(address clToken) internal {
        for (uint i = 0; i < allMarkets.length; i++) {
            require(allMarkets[i] != ClToken(clToken), "market already added");
        }
        allMarkets.push(ClToken(clToken));
    }

    function _initializeMarket(address clToken) internal {
        uint32 blockNumber = safe32(getBlockNumber(), "block number exceeds 32 bits");

        ClrMarketState storage supplyState = clrSupplyState[clToken];
        ClrMarketState storage borrowState = clrBorrowState[clToken];

        /*
         * Update market state indices
         */
        if (supplyState.index == 0) {
            // Initialize supply state index with default value
            supplyState.index = clrInitialIndex;
        }

        if (borrowState.index == 0) {
            // Initialize borrow state index with default value
            borrowState.index = clrInitialIndex;
        }

        /*
         * Update market state block numbers
         */
        supplyState.block = borrowState.block = blockNumber;
    }

    /**
     * @notice Set the given borrow caps for the given clToken markets.
     * Borrowing that brings total borrows to or above borrow cap will revert.
     * @dev Admin or borrowCapGuardian function to set the borrow caps.
     * A borrow cap of 0 corresponds to unlimited borrowing.
     * @param clTokens The addresses of the markets (tokens) to change the borrow caps for
     * @param newBorrowCaps The new borrow cap values in underlying to be set.
     * A value of 0 corresponds to unlimited borrowing.
     */
    function _setMarketBorrowCaps(ClToken[] calldata clTokens, uint[] calldata newBorrowCaps) external {
        require(
            msg.sender == admin || msg.sender == borrowCapGuardian,
            "only admin or borrow cap guardian can set borrow caps"
        );

        uint numMarkets = clTokens.length;
        uint numBorrowCaps = newBorrowCaps.length;

        require(numMarkets != 0 && numMarkets == numBorrowCaps, "invalid input");

        for (uint i = 0; i < numMarkets; i++) {
            borrowCaps[address(clTokens[i])] = newBorrowCaps[i];
            emit NewBorrowCap(clTokens[i], newBorrowCaps[i]);
        }
    }

    /**
     * @notice Admin function to change the Borrow Cap Guardian
     * @param newBorrowCapGuardian The address of the new Borrow Cap Guardian
     */
    function _setBorrowCapGuardian(address newBorrowCapGuardian) external {
        require(msg.sender == admin, "only admin can set borrow cap guardian");

        // Save current value for inclusion in log
        address oldBorrowCapGuardian = borrowCapGuardian;

        // Store borrowCapGuardian with value newBorrowCapGuardian
        borrowCapGuardian = newBorrowCapGuardian;

        // Emit NewBorrowCapGuardian(OldBorrowCapGuardian, NewBorrowCapGuardian)
        emit NewBorrowCapGuardian(oldBorrowCapGuardian, newBorrowCapGuardian);
    }

    /**
     * @notice Admin function to change the Pause Guardian
     * @param newPauseGuardian The address of the new Pause Guardian
     * @return uint 0=success, otherwise a failure. (See enum Error for details)
     */
    function _setPauseGuardian(address newPauseGuardian) public returns (uint) {
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_PAUSE_GUARDIAN_OWNER_CHECK);
        }

        // Save current value for inclusion in log
        address oldPauseGuardian = pauseGuardian;

        // Store pauseGuardian with value newPauseGuardian
        pauseGuardian = newPauseGuardian;

        // Emit NewPauseGuardian(OldPauseGuardian, NewPauseGuardian)
        emit NewPauseGuardian(oldPauseGuardian, pauseGuardian);

        return uint(Error.NO_ERROR);
    }

    function _setMintPaused(ClToken clToken, bool state) public returns (bool) {
        require(markets[address(clToken)].isListed, "cannot pause a market that is not listed");
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        mintGuardianPaused[address(clToken)] = state;
        emit ActionPaused(clToken, "Mint", state);
        return state;
    }

    function _setBorrowPaused(ClToken clToken, bool state) public returns (bool) {
        require(markets[address(clToken)].isListed, "cannot pause a market that is not listed");
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        borrowGuardianPaused[address(clToken)] = state;
        emit ActionPaused(clToken, "Borrow", state);
        return state;
    }

    function _setTransferPaused(bool state) public returns (bool) {
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        transferGuardianPaused = state;
        emit ActionPaused("Transfer", state);
        return state;
    }

    function _setSeizePaused(bool state) public returns (bool) {
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        seizeGuardianPaused = state;
        emit ActionPaused("Seize", state);
        return state;
    }

    function _become(Unitroller unitroller) public {
        require(msg.sender == unitroller.admin(), "only unitroller admin can change brains");
        require(unitroller._acceptImplementation() == 0, "change not authorized");
    }

    /// @notice Delete this function after proposal 65 is executed
    function fixBadAccruals(address[] calldata affectedUsers, uint[] calldata amounts) external {
        // Only the timelock can call this function
        require(msg.sender == admin, "Only admin can call this function");
        // Require that this function is only called once
        require(!proposal65FixExecuted, "Already executed this one-off function");
        require(affectedUsers.length == amounts.length, "Invalid input");

        // Loop variables
        address user;
        uint currentAccrual;
        uint amountToSubtract;
        uint newAccrual;

        // Iterate through all affected users
        for (uint i = 0; i < affectedUsers.length; ++i) {
            user = affectedUsers[i];
            currentAccrual = clrAccrued[user];

            amountToSubtract = amounts[i];

            // The case where the user has claimed and received an incorrect amount of CLR.
            // The user has less currently accrued than the amount they incorrectly received.
            if (amountToSubtract > currentAccrual) {
                // Amount of CLR the user owes the protocol
                // Underflow safe since amountToSubtract > currentAccrual
                uint accountReceivable = amountToSubtract - currentAccrual;

                uint oldReceivable = clrReceivable[user];
                uint newReceivable = add_(oldReceivable, accountReceivable);

                // Accounting: record the CLR debt for the user
                clrReceivable[user] = newReceivable;

                emit ClrReceivableUpdated(user, oldReceivable, newReceivable);

                amountToSubtract = currentAccrual;
            }

            if (amountToSubtract > 0) {
                // Subtract the bad accrual amount from what they have accrued.
                // Users will keep whatever they have correctly accrued.
                clrAccrued[user] = newAccrual = sub_(currentAccrual, amountToSubtract);

                emit ClrAccruedAdjusted(user, currentAccrual, newAccrual);
            }
        }

        proposal65FixExecuted = true; // Makes it so that this function cannot be called again
    }

    /**
     * @notice Checks caller is admin, or this contract is becoming the new implementation
     */
    function adminOrInitializing() internal view returns (bool) {
        return msg.sender == admin || msg.sender == comptrollerImplementation;
    }

    /*** Clr Distribution ***/

    /**
     * @notice Set CLR speed for a single market
     * @param clToken The market whose CLR speed to update
     * @param supplySpeed New supply-side CLR speed for market
     * @param borrowSpeed New borrow-side CLR speed for market
     */
    function setClrSpeedInternal(ClToken clToken, uint supplySpeed, uint borrowSpeed) internal {
        Market storage market = markets[address(clToken)];
        require(market.isListed, "clr market is not listed");

        if (clrSupplySpeeds[address(clToken)] != supplySpeed) {
            // Supply speed updated so let's update supply state to ensure that
            //  1. CLR accrued properly for the old speed, and
            //  2. CLR accrued at the new speed starts after this block.
            updateClrSupplyIndex(address(clToken));

            // Update speed and emit event
            clrSupplySpeeds[address(clToken)] = supplySpeed;
            emit ClrSupplySpeedUpdated(clToken, supplySpeed);
        }

        if (clrBorrowSpeeds[address(clToken)] != borrowSpeed) {
            // Borrow speed updated so let's update borrow state to ensure that
            //  1. CLR accrued properly for the old speed, and
            //  2. CLR accrued at the new speed starts after this block.
            Exp memory borrowIndex = Exp({ mantissa: clToken.borrowIndex() });
            updateClrBorrowIndex(address(clToken), borrowIndex);

            // Update speed and emit event
            clrBorrowSpeeds[address(clToken)] = borrowSpeed;
            emit ClrBorrowSpeedUpdated(clToken, borrowSpeed);
        }
    }

    /**
     * @notice Accrue CLR to the market by updating the supply index
     * @param clToken The market whose supply index to update
     * @dev Index is a cumulative sum of the CLR per clToken accrued.
     */
    function updateClrSupplyIndex(address clToken) internal {
        ClrMarketState storage supplyState = clrSupplyState[clToken];
        uint supplySpeed = clrSupplySpeeds[clToken];
        uint32 blockNumber = safe32(getBlockNumber(), "block number exceeds 32 bits");
        uint deltaBlocks = sub_(uint(blockNumber), uint(supplyState.block));
        if (deltaBlocks > 0 && supplySpeed > 0) {
            uint supplyTokens = ClToken(clToken).totalSupply();
            uint clrAccrued = mul_(deltaBlocks, supplySpeed);
            Double memory ratio = supplyTokens > 0 ? fraction(clrAccrued, supplyTokens) : Double({ mantissa: 0 });
            supplyState.index = safe224(
                add_(Double({ mantissa: supplyState.index }), ratio).mantissa,
                "new index exceeds 224 bits"
            );
            supplyState.block = blockNumber;
        } else if (deltaBlocks > 0) {
            supplyState.block = blockNumber;
        }
    }

    /**
     * @notice Accrue CLR to the market by updating the borrow index
     * @param clToken The market whose borrow index to update
     * @dev Index is a cumulative sum of the CLR per clToken accrued.
     */
    function updateClrBorrowIndex(address clToken, Exp memory marketBorrowIndex) internal {
        ClrMarketState storage borrowState = clrBorrowState[clToken];
        uint borrowSpeed = clrBorrowSpeeds[clToken];
        uint32 blockNumber = safe32(getBlockNumber(), "block number exceeds 32 bits");
        uint deltaBlocks = sub_(uint(blockNumber), uint(borrowState.block));
        if (deltaBlocks > 0 && borrowSpeed > 0) {
            uint borrowAmount = div_(ClToken(clToken).totalBorrows(), marketBorrowIndex);
            uint clrAccrued = mul_(deltaBlocks, borrowSpeed);
            Double memory ratio = borrowAmount > 0 ? fraction(clrAccrued, borrowAmount) : Double({ mantissa: 0 });
            borrowState.index = safe224(
                add_(Double({ mantissa: borrowState.index }), ratio).mantissa,
                "new index exceeds 224 bits"
            );
            borrowState.block = blockNumber;
        } else if (deltaBlocks > 0) {
            borrowState.block = blockNumber;
        }
    }

    /**
     * @notice Calculate CLR accrued by a supplier and possibly transfer it to them
     * @param clToken The market in which the supplier is interacting
     * @param supplier The address of the supplier to distribute CLR to
     */
    function distributeSupplierClr(address clToken, address supplier) internal {
        // TODO: Don't distribute supplier CLR if the user is not in the supplier market.
        // This check should be as gas efficient as possible as distributeSupplierClr is called in many places.
        // - We really don't want to call an external contract as that's quite expensive.

        ClrMarketState storage supplyState = clrSupplyState[clToken];
        uint supplyIndex = supplyState.index;
        uint supplierIndex = clrSupplierIndex[clToken][supplier];

        // Update supplier's index to the current index since we are distributing accrued CLR
        clrSupplierIndex[clToken][supplier] = supplyIndex;

        if (supplierIndex == 0 && supplyIndex >= clrInitialIndex) {
            // Covers the case where users supplied tokens before the market's supply state index was set.
            // Rewards the user with CLR accrued from the start of when supplier rewards were first
            // set for the market.
            supplierIndex = clrInitialIndex;
        }

        // Calculate change in the cumulative sum of the CLR per clToken accrued
        Double memory deltaIndex = Double({ mantissa: sub_(supplyIndex, supplierIndex) });

        uint supplierTokens = ClToken(clToken).balanceOf(supplier);

        // Calculate CLR accrued: clTokenAmount * accruedPerClToken
        uint supplierDelta = mul_(supplierTokens, deltaIndex);

        uint supplierAccrued = add_(clrAccrued[supplier], supplierDelta);
        clrAccrued[supplier] = supplierAccrued;

        emit DistributedSupplierClr(ClToken(clToken), supplier, supplierDelta, supplyIndex);
    }

    /**
     * @notice Calculate CLR accrued by a borrower and possibly transfer it to them
     * @dev Borrowers will not begin to accrue until after the first interaction with the protocol.
     * @param clToken The market in which the borrower is interacting
     * @param borrower The address of the borrower to distribute CLR to
     */
    function distributeBorrowerClr(address clToken, address borrower, Exp memory marketBorrowIndex) internal {
        // TODO: Don't distribute supplier CLR if the user is not in the borrower market.
        // This check should be as gas efficient as possible as distributeBorrowerClr is called in many places.
        // - We really don't want to call an external contract as that's quite expensive.

        ClrMarketState storage borrowState = clrBorrowState[clToken];
        uint borrowIndex = borrowState.index;
        uint borrowerIndex = clrBorrowerIndex[clToken][borrower];

        // Update borrowers's index to the current index since we are distributing accrued CLR
        clrBorrowerIndex[clToken][borrower] = borrowIndex;

        if (borrowerIndex == 0 && borrowIndex >= clrInitialIndex) {
            // Covers the case where users borrowed tokens before the market's borrow state index was set.
            // Rewards the user with CLR accrued from the start of when borrower rewards were first
            // set for the market.
            borrowerIndex = clrInitialIndex;
        }

        // Calculate change in the cumulative sum of the CLR per borrowed unit accrued
        Double memory deltaIndex = Double({ mantissa: sub_(borrowIndex, borrowerIndex) });

        uint borrowerAmount = div_(ClToken(clToken).borrowBalanceStored(borrower), marketBorrowIndex);

        // Calculate CLR accrued: clTokenAmount * accruedPerBorrowedUnit
        uint borrowerDelta = mul_(borrowerAmount, deltaIndex);

        uint borrowerAccrued = add_(clrAccrued[borrower], borrowerDelta);
        clrAccrued[borrower] = borrowerAccrued;

        emit DistributedBorrowerClr(ClToken(clToken), borrower, borrowerDelta, borrowIndex);
    }

    /**
     * @notice Calculate additional accrued CLR for a contributor since last accrual
     * @param contributor The address to calculate contributor rewards for
     */
    function updateContributorRewards(address contributor) public {
        uint clrSpeed = clrContributorSpeeds[contributor];
        uint blockNumber = getBlockNumber();
        uint deltaBlocks = sub_(blockNumber, lastContributorBlock[contributor]);
        if (deltaBlocks > 0 && clrSpeed > 0) {
            uint newAccrued = mul_(deltaBlocks, clrSpeed);
            uint contributorAccrued = add_(clrAccrued[contributor], newAccrued);

            clrAccrued[contributor] = contributorAccrued;
            lastContributorBlock[contributor] = blockNumber;
        }
    }

    /**
     * @notice Claim all the clr accrued by holder in all markets
     * @param holder The address to claim CLR for
     */
    function claimClr(address holder) public {
        return claimClr(holder, allMarkets);
    }

    /**
     * @notice Claim all the clr accrued by holder in the specified markets
     * @param holder The address to claim CLR for
     * @param clTokens The list of markets to claim CLR in
     */
    function claimClr(address holder, ClToken[] memory clTokens) public {
        address[] memory holders = new address[](1);
        holders[0] = holder;
        claimClr(holders, clTokens, true, true);
    }

    /**
     * @notice Claim all clr accrued by the holders
     * @param holders The addresses to claim CLR for
     * @param clTokens The list of markets to claim CLR in
     * @param borrowers Whether or not to claim CLR earned by borrowing
     * @param suppliers Whether or not to claim CLR earned by supplying
     */
    function claimClr(address[] memory holders, ClToken[] memory clTokens, bool borrowers, bool suppliers) public {
        for (uint i = 0; i < clTokens.length; i++) {
            ClToken clToken = clTokens[i];
            require(markets[address(clToken)].isListed, "market must be listed");
            if (borrowers == true) {
                Exp memory borrowIndex = Exp({ mantissa: clToken.borrowIndex() });
                updateClrBorrowIndex(address(clToken), borrowIndex);
                for (uint j = 0; j < holders.length; j++) {
                    distributeBorrowerClr(address(clToken), holders[j], borrowIndex);
                }
            }
            if (suppliers == true) {
                updateClrSupplyIndex(address(clToken));
                for (uint j = 0; j < holders.length; j++) {
                    distributeSupplierClr(address(clToken), holders[j]);
                }
            }
        }
        for (uint j = 0; j < holders.length; j++) {
            clrAccrued[holders[j]] = grantClrInternal(holders[j], clrAccrued[holders[j]]);
        }
    }

    /**
     * @notice Transfer CLR to the user
     * @dev Note: If there is not enough CLR, we do not perform the transfer all.
     * @param user The address of the user to transfer CLR to
     * @param amount The amount of CLR to (possibly) transfer
     * @return The amount of CLR which was NOT transferred to the user
     */
    function grantClrInternal(address user, uint amount) internal returns (uint) {
        Cluster clr = Cluster(getClrAddress());
        uint clrRemaining = clr.balanceOf(address(this));
        if (amount > 0 && amount <= clrRemaining) {
            clr.transfer(user, amount);
            return 0;
        }
        return amount;
    }

    /*** Clr Distribution Admin ***/

    /**
     * @notice Transfer CLR to the recipient
     * @dev Note: If there is not enough CLR, we do not perform the transfer all.
     * @param recipient The address of the recipient to transfer CLR to
     * @param amount The amount of CLR to (possibly) transfer
     */
    function _grantClr(address recipient, uint amount) public {
        require(adminOrInitializing(), "only admin can grant clr");
        uint amountLeft = grantClrInternal(recipient, amount);
        require(amountLeft == 0, "insufficient clr for grant");
        emit ClrGranted(recipient, amount);
    }

    /**
     * @notice Set CLR borrow and supply speeds for the specified markets.
     * @param clTokens The markets whose CLR speed to update.
     * @param supplySpeeds New supply-side CLR speed for the corresponding market.
     * @param borrowSpeeds New borrow-side CLR speed for the corresponding market.
     */
    function _setClrSpeeds(ClToken[] memory clTokens, uint[] memory supplySpeeds, uint[] memory borrowSpeeds) public {
        require(adminOrInitializing(), "only admin can set clr speed");

        uint numTokens = clTokens.length;
        require(
            numTokens == supplySpeeds.length && numTokens == borrowSpeeds.length,
            "Comptroller::_setClrSpeeds invalid input"
        );

        for (uint i = 0; i < numTokens; ++i) {
            setClrSpeedInternal(clTokens[i], supplySpeeds[i], borrowSpeeds[i]);
        }
    }

    /**
     * @notice Set CLR speed for a single contributor
     * @param contributor The contributor whose CLR speed to update
     * @param clrSpeed New CLR speed for contributor
     */
    function _setContributorClrSpeed(address contributor, uint clrSpeed) public {
        require(adminOrInitializing(), "only admin can set clr speed");

        // note that CLR speed could be set to 0 to halt liquidity rewards for a contributor
        updateContributorRewards(contributor);
        if (clrSpeed == 0) {
            // release storage
            delete lastContributorBlock[contributor];
        } else {
            lastContributorBlock[contributor] = getBlockNumber();
        }
        clrContributorSpeeds[contributor] = clrSpeed;

        emit ContributorClrSpeedUpdated(contributor, clrSpeed);
    }

    /**
     * @notice Return all of the markets
     * @dev The automatic getter may be used to access an individual market.
     * @return The list of market addresses
     */
    function getAllMarkets() public view returns (ClToken[] memory) {
        return allMarkets;
    }

    /**
     * @notice Returns true if the given clToken market has been deprecated
     * @dev All borrows in a deprecated clToken market can be immediately liquidated
     * @param clToken The market to check if deprecated
     */
    function isDeprecated(ClToken clToken) public view returns (bool) {
        return
            markets[address(clToken)].collateralFactorMantissa == 0 &&
            borrowGuardianPaused[address(clToken)] == true &&
            clToken.reserveFactorMantissa() == 1e18;
    }

    function getBlockNumber() public view virtual returns (uint) {
        return block.number;
    }

    /**
     * @notice Return the address of the CLR token
     * @return The address of CLR
     */
    function getClrAddress() public view virtual returns (address) {
        return 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    }
}
