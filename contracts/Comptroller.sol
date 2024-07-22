// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.20;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IClErc20, IPriceOracle } from "./interfaces/IPriceOracle.sol";
import { IClToken } from "./interfaces/IClToken.sol";
import { IComptroller } from "./interfaces/IComptroller.sol";
import { IClusterToken } from "./interfaces/IClusterToken.sol";
import { ExponentialNoError } from "./ExponentialNoError.sol";
import { ComptrollerStorage } from "./base/ComptrollerStorage.sol";

/**
 * @title Cluster's Comptroller Contract
 * @author Cluster
 */
contract Comptroller is Initializable, IComptroller, ExponentialNoError, ComptrollerStorage {
    /// @notice Indicator that this is a Comptroller contract (for inspection)
    bool public constant isComptroller = true;

    /// @notice The initial CLR index for a market
    uint224 public constant clrInitialIndex = 1e36;

    /// @dev closeFactorMantissa must be strictly greater than this value
    uint internal constant closeFactorMinMantissa = 0.05e18; // 0.05

    /// @dev closeFactorMantissa must not exceed this value
    uint internal constant closeFactorMaxMantissa = 0.9e18; // 0.9

    /// @dev No collateralFactorMantissa may exceed this value
    uint internal constant collateralFactorMaxMantissa = 0.9e18; // 0.9

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        admin = msg.sender;
    }

    /*** Admin Functions ***/

    /**
     * @notice Admin function to begin change of admin.
     * @dev Begins transfer of admin rights. The newPendingAdmin must call `acceptAdmin` to
     * finalize the transfer.
     * @param _newPendingAdmin The new pending admin.
     */
    function setPendingAdmin(address _newPendingAdmin) public {
        // Check if caller is admin
        _onlyAdmin();
        // check if new admin is not zero address
        if (_newPendingAdmin == address(0)) revert ZeroAddress();

        address _oldPendingAdmin = pendingAdmin;

        pendingAdmin = _newPendingAdmin;

        emit NewPendingAdmin(_oldPendingAdmin, _newPendingAdmin);
    }

    /**
     * @notice Accepts transfer of admin rights. The caller must be pendingAdmin.
     * @dev Admin function for pending admin to accept role and update admin.
     */
    function acceptAdmin() public {
        // Check if caller is pendingAdmin
        if (msg.sender != pendingAdmin) revert NotPendingAdmin();

        address _oldAdmin = admin;
        address _oldPendingAdmin = pendingAdmin;

        admin = pendingAdmin;

        // Clear the pending value
        pendingAdmin = address(0);

        emit NewAdmin(_oldAdmin, admin);
        emit NewPendingAdmin(_oldPendingAdmin, pendingAdmin);
    }

    /**
     * @notice Add the market to the markets mapping and set it as listed
     * @dev Admin function to set isListed and add support for the market
     * @param clToken The address of the market (token) to list
     */
    function supportMarket(address clToken) external {
        _onlyAdmin();

        if (markets[clToken].isListed) {
            revert MarketIsAlreadyListed(clToken);
        }

        // Sanity check to make sure its really a ClToken
        IClToken(clToken).isClToken();

        // Note that isClred is not in active use anymore
        Market storage newMarket = markets[clToken];
        newMarket.isListed = true;
        newMarket.isClred = false;
        newMarket.collateralFactorMantissa = 0;

        _addMarketInternal(clToken);
        _initializeMarket(clToken);

        emit MarketListed(clToken);
    }

    /**
     * @notice Sets a new price oracle for the comptroller
     * @dev Admin function to set a new price oracle
     */
    function setPriceOracle(address _newOracle) public {
        // Check caller is admin
        _onlyAdmin();

        // Sanity check to make sure its really a PriceOracle
        IPriceOracle(_newOracle).isPriceOracle();

        // Track the old oracle for the comptroller
        address oldOracle = oracle;

        // Set comptroller's oracle to newOracle
        oracle = _newOracle;

        // Emit NewPriceOracle(oldOracle, newOracle)
        emit NewPriceOracle(oldOracle, _newOracle);
    }

    /**
     * @notice Sets the closeFactor used when liquidating borrows
     * @dev Admin function to set closeFactor
     * @param newCloseFactorMantissa New close factor, scaled by 1e18
     */
    function setCloseFactor(uint newCloseFactorMantissa) external {
        // Check caller is admin
        _onlyAdmin();

        uint oldCloseFactorMantissa = closeFactorMantissa;
        closeFactorMantissa = newCloseFactorMantissa;
        emit NewCloseFactor(oldCloseFactorMantissa, closeFactorMantissa);
    }

    /**
     * @notice Sets the collateralFactor for a market
     * @dev Admin function to set per-market collateralFactor
     * @param clToken The market to set the factor on
     * @param newCollateralFactorMantissa The new collateral factor, scaled by 1e18
     */
    function setCollateralFactor(address clToken, uint newCollateralFactorMantissa) external {
        // Check caller is admin
        _onlyAdmin();

        // Verify market is listed
        Market storage market = markets[clToken];
        if (!market.isListed) {
            revert MarketIsNotListed(clToken);
        }

        Exp memory newCollateralFactorExp = Exp({ mantissa: newCollateralFactorMantissa });

        // Check collateral factor <= 0.9
        Exp memory highLimit = Exp({ mantissa: collateralFactorMaxMantissa });
        if (lessThanExp(highLimit, newCollateralFactorExp)) {
            revert InvalidCollateralFactor();
        }

        // If collateral factor != 0, fail if price == 0
        if (
            newCollateralFactorMantissa != 0 &&
            IPriceOracle(oracle).getUnderlyingPrice(IClErc20(clToken)) == 0
        ) {
            revert SetCollFactorWithoutPrice();
        }

        // Set market's collateral factor to new collateral factor, remember old value
        uint oldCollateralFactorMantissa = market.collateralFactorMantissa;
        market.collateralFactorMantissa = newCollateralFactorMantissa;

        // Emit event with asset, old collateral factor, and new collateral factor
        emit NewCollateralFactor(clToken, oldCollateralFactorMantissa, newCollateralFactorMantissa);
    }

    /**
     * @notice Sets liquidationIncentive
     * @dev Admin function to set liquidationIncentive
     * @param newLiquidationIncentiveMantissa New liquidationIncentive scaled by 1e18
     */
    function setLiquidationIncentive(uint newLiquidationIncentiveMantissa) external {
        _onlyAdmin();

        // Save current value for use in log
        uint oldLiquidationIncentiveMantissa = liquidationIncentiveMantissa;

        // Set liquidation incentive to new incentive
        liquidationIncentiveMantissa = newLiquidationIncentiveMantissa;

        // Emit event with old incentive, new incentive
        emit NewLiquidationIncentive(
            oldLiquidationIncentiveMantissa,
            newLiquidationIncentiveMantissa
        );
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
    function setMarketBorrowCaps(
        address[] calldata clTokens,
        uint[] calldata newBorrowCaps
    ) external {
        if (msg.sender != admin && msg.sender != borrowCapGuardian) {
            revert NotAdminOrBorrowCapGuardian();
        }

        uint numMarkets = clTokens.length;
        uint numBorrowCaps = newBorrowCaps.length;

        if (numMarkets == 0 || numMarkets != numBorrowCaps) {
            revert ArrayLengthMismatch();
        }

        for (uint i = 0; i < numMarkets; ) {
            borrowCaps[clTokens[i]] = newBorrowCaps[i];
            emit NewBorrowCap(clTokens[i], newBorrowCaps[i]);

            unchecked {
                i++;
            }
        }
    }

    /**
     * @notice Admin function to change the Borrow Cap Guardian
     * @param newBorrowCapGuardian The address of the new Borrow Cap Guardian
     */
    function setBorrowCapGuardian(address newBorrowCapGuardian) external {
        _onlyAdmin();

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
     */
    function setPauseGuardian(address newPauseGuardian) external {
        _onlyAdmin();

        // Save current value for inclusion in log
        address oldPauseGuardian = pauseGuardian;

        // Store pauseGuardian with value newPauseGuardian
        pauseGuardian = newPauseGuardian;

        // Emit NewPauseGuardian(OldPauseGuardian, NewPauseGuardian)
        emit NewPauseGuardian(oldPauseGuardian, pauseGuardian);
    }

    function setMintPaused(address clToken, bool state) external returns (bool) {
        if (!markets[clToken].isListed) {
            revert MarketIsNotListed(clToken);
        }
        if (msg.sender != pauseGuardian && msg.sender != admin) {
            revert NotAdminOrPauseGuardian();
        }
        if (msg.sender != admin && state == false) {
            revert NotAdmin();
        }

        mintGuardianPaused[clToken] = state;
        emit MarketActionPaused(clToken, "Mint", state);
        return state;
    }

    function setBorrowPaused(address clToken, bool state) external returns (bool) {
        if (!markets[clToken].isListed) {
            revert MarketIsNotListed(clToken);
        }
        if (msg.sender != pauseGuardian && msg.sender != admin) {
            revert NotAdminOrPauseGuardian();
        }
        if (msg.sender != admin && state == false) {
            revert NotAdmin();
        }

        borrowGuardianPaused[clToken] = state;
        emit MarketActionPaused(clToken, "Borrow", state);
        return state;
    }

    function setTransferPaused(bool state) external returns (bool) {
        if (msg.sender != pauseGuardian && msg.sender != admin) {
            revert NotAdminOrPauseGuardian();
        }
        if (msg.sender != admin && state == false) {
            revert NotAdmin();
        }

        transferGuardianPaused = state;
        emit ActionPaused("Transfer", state);
        return state;
    }

    function setSeizePaused(bool state) external returns (bool) {
        if (msg.sender != pauseGuardian && msg.sender != admin) {
            revert NotAdminOrPauseGuardian();
        }
        if (msg.sender != admin && state == false) {
            revert NotAdmin();
        }

        seizeGuardianPaused = state;
        emit ActionPaused("Seize", state);
        return state;
    }

    /**
     * @notice Set the Cluster token address
     * @param newClrAddress New CLR token address
     */
    function setClrAddress(address newClrAddress) external {
        _onlyAdmin();

        address oldClrAddress = clrAddress;

        clrAddress = newClrAddress;

        emit NewClrAddress(oldClrAddress, newClrAddress);
    }

    function setLeverageAddress(address newLeverage) external {
        _onlyAdmin();

        address oldLeverageAddress = leverageAddress;

        leverageAddress = newLeverage;

        emit NewLeverageAddress(oldLeverageAddress, newLeverage);
    }

    /*** Clr Distribution Admin ***/

    /**
     * @notice Set CLR speed for a single contributor
     * @param contributor The contributor whose CLR speed to update
     * @param clrSpeed New CLR speed for contributor
     */
    function setContributorClrSpeed(address contributor, uint clrSpeed) public {
        _onlyAdmin();

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
     * @notice Set CLR borrow and supply speeds for the specified markets.
     * @param clTokens The markets whose CLR speed to update.
     * @param supplySpeeds New supply-side CLR speed for the corresponding market.
     * @param borrowSpeeds New borrow-side CLR speed for the corresponding market.
     */
    function setClrSpeeds(
        address[] memory clTokens,
        uint[] memory supplySpeeds,
        uint[] memory borrowSpeeds
    ) public {
        _onlyAdmin();

        uint numTokens = clTokens.length;
        if (numTokens != supplySpeeds.length || numTokens != borrowSpeeds.length) {
            revert ArrayLengthMismatch();
        }

        for (uint i = 0; i < numTokens; ) {
            setClrSpeedInternal(clTokens[i], supplySpeeds[i], borrowSpeeds[i]);
            unchecked {
                i++;
            }
        }
    }

    /**
     * @notice Transfer CLR to the recipient
     * @dev Note: If there is not enough CLR, we do not perform the transfer all.
     * @param recipient The address of the recipient to transfer CLR to
     * @param amount The amount of CLR to (possibly) transfer
     */
    function grantClr(address recipient, uint amount) public {
        _onlyAdmin();

        uint amountLeft = grantClrInternal(recipient, amount);
        if (amountLeft > 0) {
            revert InsufficientClrForGrant();
        }
        emit ClrGranted(recipient, amount);
    }

    function getMarketInfo(address clToken) external view returns (bool, uint256) {
        Market storage market = markets[clToken];
        return (market.isListed, market.collateralFactorMantissa);
    }

    /*** Assets You Are In ***/

    /**
     * @notice Returns the assets an account has entered
     * @param account The address of the account to pull assets for
     * @return A dynamic list with the assets the account has entered
     */
    function getAssetsIn(address account) external view returns (address[] memory) {
        address[] memory assetsIn = accountAssets[account];

        return assetsIn;
    }

    /**
     * @notice Returns whether the given account is entered in the given asset
     * @param account The address of the account to check
     * @param clToken The clToken to check
     * @return True if the account is in the asset, otherwise false.
     */
    function checkMembership(address account, address clToken) external view returns (bool) {
        return markets[clToken].accountMembership[account];
    }

    /**
     * @notice Add assets to be included in account liquidity calculation
     * @param clTokens The list of addresses of the clToken markets to be enabled
     */
    function enterMarkets(address[] memory clTokens) public {
        uint len = clTokens.length;

        for (uint i = 0; i < len; ) {
            addToMarketInternal(clTokens[i], msg.sender);
            unchecked {
                i++;
            }
        }
    }

    /**
     * @notice Add the market to the borrower's "assets in" for liquidity calculations
     * @param clToken The market to enter
     * @param borrower The address of the account to modify
     */
    function addToMarketInternal(address clToken, address borrower) internal {
        Market storage marketToJoin = markets[clToken];

        if (!marketToJoin.isListed) {
            // market is not listed, cannot join
            revert MarketIsNotListed(clToken);
        }

        if (marketToJoin.accountMembership[borrower] == true) return;

        // survived the gauntlet, add to list
        // NOTE: we store these somewhat redundantly as a significant optimization
        //  this avoids having to iterate through the list for the most common use cases
        //  that is, only when we need to perform liquidity checks
        //  and not whenever we want to check if an account is in a particular market
        marketToJoin.accountMembership[borrower] = true;
        accountAssets[borrower].push(clToken);

        emit MarketEntered(clToken, borrower);
    }

    /**
     * @notice Removes asset from sender's account liquidity calculation
     * @dev Sender must not have an outstanding borrow balance in the asset,
     *  or be providing necessary collateral for an outstanding borrow.
     * @param clTokenAddress The address of the asset to be removed
     */
    function exitMarket(address clTokenAddress) external {
        IClToken clToken = IClToken(clTokenAddress);
        /* Get sender tokensHeld and amountOwed underlying from the clToken */
        (uint tokensHeld, uint amountOwed, ) = clToken.getAccountSnapshot(msg.sender);

        /* Fail if the sender has a borrow balance */
        if (amountOwed != 0) {
            revert NonZeroBorrowBalance();
        }

        /* Fail if the sender is not permitted to redeem all of their tokens */
        redeemAllowedInternal(clTokenAddress, msg.sender, tokensHeld);

        Market storage marketToExit = markets[address(clToken)];

        /* Return true if the sender is not already ‘in’ the market */
        if (!marketToExit.accountMembership[msg.sender]) return;

        /* Set clToken account membership to false */
        delete marketToExit.accountMembership[msg.sender];

        /* Delete clToken from the account’s list of assets */
        // load into memory for faster iteration
        address[] memory userAssetList = accountAssets[msg.sender];
        uint len = userAssetList.length;
        uint assetIndex = len;
        for (uint i = 0; i < len; i++) {
            if (userAssetList[i] == address(clToken)) {
                assetIndex = i;
                break;
            }
        }

        // We *must* have found the asset in the list or our redundant data structure is broken
        assert(assetIndex < len);

        // copy last item in list to location of item to be removed, reduce length by 1
        address[] storage storedList = accountAssets[msg.sender];
        storedList[assetIndex] = storedList[storedList.length - 1];
        storedList.pop();

        emit MarketExited(address(clToken), msg.sender);
    }

    /*** Policy Hooks ***/

    /**
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param clToken The market to verify the mint against
     * @param minter The account which would get the minted tokens
     * @param mintAmount The amount of underlying being supplied to the market in exchange for tokens
     */
    function mintAllowed(address clToken, address minter, uint mintAmount) external {
        // Pausing is a very serious situation - we revert to sound the alarms
        if (mintGuardianPaused[clToken]) {
            revert MintIsPaused();
        }
        // Shh - currently unused
        minter;
        mintAmount;

        if (!markets[clToken].isListed) {
            revert MarketIsNotListed(clToken);
        }

        // Keep the flywheel moving
        updateClrSupplyIndex(clToken);
        distributeSupplierClr(clToken, minter);
    }

    /**
     * @notice Checks if the account should be allowed to redeem tokens in the given market
     * @param clToken The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param redeemTokens The number of clTokens to exchange for the underlying asset in the market
     */
    function redeemAllowed(address clToken, address redeemer, uint redeemTokens) external {
        redeemAllowedInternal(clToken, redeemer, redeemTokens);

        // Keep the flywheel moving
        updateClrSupplyIndex(clToken);
        distributeSupplierClr(clToken, redeemer);
    }

    function redeemAllowedInternal(
        address clToken,
        address redeemer,
        uint redeemTokens
    ) internal view {
        if (!markets[clToken].isListed) {
            revert MarketIsNotListed(clToken);
        }

        /* If the redeemer is not 'in' the market, then we can bypass the liquidity check */
        if (!markets[clToken].accountMembership[redeemer]) return;

        /* Otherwise, perform a hypothetical liquidity check to guard against shortfall */
        (, uint shortfall) = getHypotheticalAccountLiquidityInternal(
            redeemer,
            clToken,
            redeemTokens,
            0
        );

        if (shortfall > 0) {
            revert InsufficientLiquidity();
        }
    }

    /**
     * @notice Validates redeem and reverts on rejection. May emit logs.
     * @param clToken Asset being redeemed
     * @param redeemer The address redeeming the tokens
     * @param redeemAmount The amount of the underlying asset being redeemed
     * @param redeemTokens The number of tokens being redeemed
     */
    function redeemVerify(
        address clToken,
        address redeemer,
        uint redeemAmount,
        uint redeemTokens
    ) external pure {
        // Shh - currently unused
        clToken;
        redeemer;

        // Require tokens is zero or amount is also zero
        if (redeemTokens == 0 && redeemAmount > 0) {
            revert ZeroRedeemTokens();
        }
    }

    /**
     * @notice Checks if the account should be allowed to borrow the underlying asset of the given market
     * @param clToken The market to verify the borrow against
     * @param borrower The account which would borrow the asset
     * @param borrowAmount The amount of underlying the account would borrow
     */
    function borrowAllowed(address clToken, address borrower, uint borrowAmount) external {
        // Pausing is a very serious situation - we revert to sound the alarms
        if (borrowGuardianPaused[clToken]) {
            revert BorrowIsPaused();
        }

        if (!markets[clToken].isListed) {
            revert MarketIsNotListed(clToken);
        }

        if (!markets[clToken].accountMembership[borrower]) {
            // only clTokens may call borrowAllowed if borrower not in market
            if (msg.sender != clToken) {
                revert SenderMustBeClToken();
            }
            // attempt to add borrower to the market
            addToMarketInternal(msg.sender, borrower);

            // it should be impossible to break the important invariant
            assert(markets[clToken].accountMembership[borrower]);
        }

        if (IPriceOracle(oracle).getUnderlyingPrice(IClErc20(clToken)) == 0) {
            revert ZeroPrice();
        }

        uint borrowCap = borrowCaps[clToken];
        // Borrow cap of 0 corresponds to unlimited borrowing
        if (borrowCap != 0) {
            uint totalBorrows = IClToken(clToken).totalBorrows();
            uint nextTotalBorrows = add_(totalBorrows, borrowAmount);
            if (nextTotalBorrows >= borrowCap) {
                revert BorrowCapReached();
            }
        }

        (, uint shortfall) = getHypotheticalAccountLiquidityInternal(
            borrower,
            clToken,
            0,
            borrowAmount
        );

        if (shortfall > 0) {
            revert InsufficientLiquidity();
        }

        // Keep the flywheel moving
        Exp memory borrowIndex = Exp({ mantissa: IClToken(clToken).borrowIndex() });
        updateClrBorrowIndex(clToken, borrowIndex);
        distributeBorrowerClr(clToken, borrower, borrowIndex);
    }

    function borrowBehalfAllowed(address sender) external view {
        if (sender != leverageAddress) {
            revert SenderMustBeLeverage();
        }
    }

    /**
     * @notice Checks if the account should be allowed to repay a borrow in the given market
     * @param clToken The market to verify the repay against
     * @param payer The account which would repay the asset
     * @param borrower The account which would borrowed the asset
     * @param repayAmount The amount of the underlying asset the account would repay
     */
    function repayBorrowAllowed(
        address clToken,
        address payer,
        address borrower,
        uint repayAmount
    ) external {
        // Shh - currently unused
        payer;
        borrower;
        repayAmount;

        if (!markets[clToken].isListed) {
            revert MarketIsNotListed(clToken);
        }

        // Keep the flywheel moving
        Exp memory borrowIndex = Exp({ mantissa: IClToken(clToken).borrowIndex() });
        updateClrBorrowIndex(clToken, borrowIndex);
        distributeBorrowerClr(clToken, borrower, borrowIndex);
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
    ) external view {
        // Shh - currently unused
        liquidator;

        if (!markets[clTokenBorrowed].isListed) revert MarketIsNotListed(clTokenBorrowed);
        if (!markets[clTokenCollateral].isListed) revert MarketIsNotListed(clTokenCollateral);

        uint borrowBalance = IClToken(clTokenBorrowed).borrowBalanceStored(borrower);

        /* allow accounts to be liquidated if the market is deprecated */
        if (isDeprecated(clTokenBorrowed)) {
            if (borrowBalance < repayAmount) revert RepayShouldBeLessThanTotalBorrow();
        } else {
            /* The borrower must have shortfall in order to be liquidatable */
            (, uint shortfall) = getAccountLiquidityInternal(borrower);

            if (shortfall == 0) {
                revert InsufficientShortfall();
            }

            /* The liquidator may not repay more than what is allowed by the closeFactor */
            uint maxClose = mul_ScalarTruncate(
                Exp({ mantissa: closeFactorMantissa }),
                borrowBalance
            );
            if (repayAmount > maxClose) {
                revert TooMuchRepay();
            }
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
    ) external {
        // Pausing is a very serious situation - we revert to sound the alarms
        if (seizeGuardianPaused) {
            revert SeizeIsPaused();
        }

        // Shh - currently unused
        seizeTokens;

        if (!markets[clTokenCollateral].isListed) revert MarketIsNotListed(clTokenCollateral);
        if (!markets[clTokenBorrowed].isListed) revert MarketIsNotListed(clTokenBorrowed);

        if (IClToken(clTokenCollateral).comptroller() != IClToken(clTokenBorrowed).comptroller()) {
            revert ComptrollerMismatch();
        }

        // Keep the flywheel moving
        updateClrSupplyIndex(clTokenCollateral);
        distributeSupplierClr(clTokenCollateral, borrower);
        distributeSupplierClr(clTokenCollateral, liquidator);
    }

    /**
     * @notice Checks if the account should be allowed to transfer tokens in the given market
     * @param clToken The market to verify the transfer against
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of clTokens to transfer
     */
    function transferAllowed(
        address clToken,
        address src,
        address dst,
        uint transferTokens
    ) external {
        // Pausing is a very serious situation - we revert to sound the alarms
        if (transferGuardianPaused) {
            revert TransferIsPaused();
        }

        // Currently the only consideration is whether or not
        // the src is allowed to redeem this many tokens
        redeemAllowedInternal(clToken, src, transferTokens);

        // Keep the flywheel moving
        updateClrSupplyIndex(clToken);
        distributeSupplierClr(clToken, src);
        distributeSupplierClr(clToken, dst);
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
     * @return (account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidity(address account) public view returns (uint, uint) {
        (uint liquidity, uint shortfall) = getHypotheticalAccountLiquidityInternal(
            account,
            address(0),
            0,
            0
        );

        return (liquidity, shortfall);
    }

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return (possible error code,
                account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidityInternal(address account) internal view returns (uint, uint) {
        return getHypotheticalAccountLiquidityInternal(account, address(0), 0, 0);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param clTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @return (hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidity(
        address account,
        address clTokenModify,
        uint redeemTokens,
        uint borrowAmount
    ) public view returns (uint, uint) {
        (uint liquidity, uint shortfall) = getHypotheticalAccountLiquidityInternal(
            account,
            clTokenModify,
            redeemTokens,
            borrowAmount
        );
        return (liquidity, shortfall);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param clTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @dev Note that we calculate the exchangeRateStored for each collateral clToken using stored data,
     *  without calculating accumulated interest.
     * @return (hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidityInternal(
        address account,
        address clTokenModify,
        uint redeemTokens,
        uint borrowAmount
    ) internal view returns (uint, uint) {
        AccountLiquidityLocalVars memory vars; // Holds all our calculation results

        // For each asset the account is in
        address[] memory assets = accountAssets[account];
        for (uint i = 0; i < assets.length; i++) {
            IClToken asset = IClToken(assets[i]);

            // Read the balances and exchange rate from the clToken
            (vars.clTokenBalance, vars.borrowBalance, vars.exchangeRateMantissa) = asset
                .getAccountSnapshot(account);

            vars.collateralFactor = Exp({
                mantissa: markets[address(asset)].collateralFactorMantissa
            });
            vars.exchangeRate = Exp({ mantissa: vars.exchangeRateMantissa });

            // Get the normalized price of the asset
            vars.oraclePriceMantissa = IPriceOracle(oracle).getUnderlyingPrice(
                IClErc20(address(asset))
            );
            if (vars.oraclePriceMantissa == 0) {
                revert ZeroPrice();
            }

            vars.oraclePrice = Exp({ mantissa: vars.oraclePriceMantissa });

            // Pre-compute a conversion factor from tokens -> ether (normalized price value)
            vars.tokensToDenom = mul_(
                mul_(vars.collateralFactor, vars.exchangeRate),
                vars.oraclePrice
            );

            // sumCollateral += tokensToDenom * clTokenBalance
            vars.sumCollateral = mul_ScalarTruncateAddUInt(
                vars.tokensToDenom,
                vars.clTokenBalance,
                vars.sumCollateral
            );

            // sumBorrowPlusEffects += oraclePrice * borrowBalance
            vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(
                vars.oraclePrice,
                vars.borrowBalance,
                vars.sumBorrowPlusEffects
            );

            // Calculate effects of interacting with clTokenModify
            if (address(asset) == clTokenModify) {
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
            return (vars.sumCollateral - vars.sumBorrowPlusEffects, 0);
        } else {
            return (0, vars.sumBorrowPlusEffects - vars.sumCollateral);
        }
    }

    /**
     * @notice Calculate number of tokens of collateral asset to seize given an underlying amount
     * @dev Used in liquidation (called in clToken.liquidateBorrowFresh)
     * @param clTokenBorrowed The address of the borrowed clToken
     * @param clTokenCollateral The address of the collateral clToken
     * @param actualRepayAmount The amount of clTokenBorrowed underlying to convert into clTokenCollateral tokens
     * @return The number of clTokenCollateral tokens to be seized in a liquidation
     */
    function liquidateCalculateSeizeTokens(
        address clTokenBorrowed,
        address clTokenCollateral,
        uint actualRepayAmount
    ) external view override returns (uint) {
        /* Read oracle prices for borrowed and collateral markets */
        uint priceBorrowedMantissa = IPriceOracle(oracle).getUnderlyingPrice(
            IClErc20(clTokenBorrowed)
        );
        uint priceCollateralMantissa = IPriceOracle(oracle).getUnderlyingPrice(
            IClErc20(clTokenCollateral)
        );
        if (priceBorrowedMantissa == 0 || priceCollateralMantissa == 0) {
            return 0;
        }

        /*
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
         *  seizeTokens = seizeAmount / exchangeRate
         *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
         */
        uint exchangeRateMantissa = IClToken(clTokenCollateral).exchangeRateStored(); // Note: reverts on error
        uint seizeTokens;
        Exp memory numerator;
        Exp memory denominator;
        Exp memory ratio;

        numerator = mul_(
            Exp({ mantissa: liquidationIncentiveMantissa }),
            Exp({ mantissa: priceBorrowedMantissa })
        );
        denominator = mul_(
            Exp({ mantissa: priceCollateralMantissa }),
            Exp({ mantissa: exchangeRateMantissa })
        );
        ratio = div_(numerator, denominator);

        seizeTokens = mul_ScalarTruncate(ratio, actualRepayAmount);

        return seizeTokens;
    }

    /*** CLR Distribution ***/

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
        claimClr(holder, allMarkets);
    }

    /**
     * @notice Claim all the clr accrued by holder in the specified markets
     * @param holder The address to claim CLR for
     * @param clTokens The list of markets to claim CLR in
     */
    function claimClr(address holder, address[] memory clTokens) public {
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
    function claimClr(
        address[] memory holders,
        address[] memory clTokens,
        bool borrowers,
        bool suppliers
    ) public {
        for (uint i = 0; i < clTokens.length; i++) {
            address clToken = clTokens[i];
            if (!markets[clToken].isListed) {
                revert MarketIsNotListed(clToken);
            }
            if (borrowers == true) {
                Exp memory borrowIndex = Exp({ mantissa: IClToken(clToken).borrowIndex() });
                updateClrBorrowIndex(clToken, borrowIndex);
                for (uint j = 0; j < holders.length; j++) {
                    distributeBorrowerClr(clToken, holders[j], borrowIndex);
                }
            }
            if (suppliers == true) {
                updateClrSupplyIndex(clToken);
                for (uint j = 0; j < holders.length; j++) {
                    distributeSupplierClr(clToken, holders[j]);
                }
            }
        }
        for (uint j = 0; j < holders.length; j++) {
            clrAccrued[holders[j]] = grantClrInternal(holders[j], clrAccrued[holders[j]]);
        }
    }

    /**
     * @notice Set CLR speed for a single market
     * @param clToken The market whose CLR speed to update
     * @param supplySpeed New supply-side CLR speed for market
     * @param borrowSpeed New borrow-side CLR speed for market
     */
    function setClrSpeedInternal(address clToken, uint supplySpeed, uint borrowSpeed) internal {
        Market storage market = markets[clToken];
        if (!market.isListed) {
            revert MarketIsNotListed(clToken);
        }

        if (clrSupplySpeeds[clToken] != supplySpeed) {
            // Supply speed updated so let's update supply state to ensure that
            //  1. CLR accrued properly for the old speed, and
            //  2. CLR accrued at the new speed starts after this block.
            updateClrSupplyIndex(clToken);

            // Update speed and emit event
            clrSupplySpeeds[clToken] = supplySpeed;
            emit ClrSupplySpeedUpdated(clToken, supplySpeed);
        }

        if (clrBorrowSpeeds[clToken] != borrowSpeed) {
            // Borrow speed updated so let's update borrow state to ensure that
            //  1. CLR accrued properly for the old speed, and
            //  2. CLR accrued at the new speed starts after this block.
            Exp memory borrowIndex = Exp({ mantissa: IClToken(clToken).borrowIndex() });
            updateClrBorrowIndex(clToken, borrowIndex);

            // Update speed and emit event
            clrBorrowSpeeds[clToken] = borrowSpeed;
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
            uint _supplyTokens = IClToken(clToken).totalSupply();
            uint _clrAccrued = mul_(deltaBlocks, supplySpeed);
            Double memory ratio = _supplyTokens > 0
                ? fraction(_clrAccrued, _supplyTokens)
                : Double({ mantissa: 0 });
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
            uint _borrowAmount = div_(IClToken(clToken).totalBorrows(), marketBorrowIndex);
            uint _clrAccrued = mul_(deltaBlocks, borrowSpeed);
            Double memory ratio = _borrowAmount > 0
                ? fraction(_clrAccrued, _borrowAmount)
                : Double({ mantissa: 0 });
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

        uint supplierTokens = IClToken(clToken).balanceOf(supplier);

        // Calculate CLR accrued: clTokenAmount * accruedPerClToken
        uint supplierDelta = mul_(supplierTokens, deltaIndex);

        uint supplierAccrued = add_(clrAccrued[supplier], supplierDelta);
        clrAccrued[supplier] = supplierAccrued;

        emit DistributedSupplierClr(clToken, supplier, supplierDelta, supplyIndex);
    }

    /**
     * @notice Calculate CLR accrued by a borrower and possibly transfer it to them
     * @dev Borrowers will not begin to accrue until after the first interaction with the protocol.
     * @param clToken The market in which the borrower is interacting
     * @param borrower The address of the borrower to distribute CLR to
     */
    function distributeBorrowerClr(
        address clToken,
        address borrower,
        Exp memory marketBorrowIndex
    ) internal {
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

        uint borrowerAmount = div_(
            IClToken(clToken).borrowBalanceStored(borrower),
            marketBorrowIndex
        );

        // Calculate CLR accrued: clTokenAmount * accruedPerBorrowedUnit
        uint borrowerDelta = mul_(borrowerAmount, deltaIndex);

        uint borrowerAccrued = add_(clrAccrued[borrower], borrowerDelta);
        clrAccrued[borrower] = borrowerAccrued;

        emit DistributedBorrowerClr(clToken, borrower, borrowerDelta, borrowIndex);
    }

    /**
     * @notice Transfer CLR to the user
     * @dev Note: If there is not enough CLR, we do not perform the transfer all.
     * @param user The address of the user to transfer CLR to
     * @param amount The amount of CLR to (possibly) transfer
     * @return The amount of CLR which was NOT transferred to the user
     */
    function grantClrInternal(address user, uint amount) internal returns (uint) {
        uint clrRemaining = IClusterToken(clrAddress).balanceOf(address(this));
        if (amount > 0 && amount <= clrRemaining) {
            IClusterToken(clrAddress).transfer(user, amount);
            return 0;
        }
        return amount;
    }

    /**
     * @notice Return all of the markets
     * @dev The automatic getter may be used to access an individual market.
     * @return The list of market addresses
     */
    function getAllMarkets() public view returns (address[] memory) {
        return allMarkets;
    }

    /**
     * @notice Returns true if the given clToken market has been deprecated
     * @dev All borrows in a deprecated clToken market can be immediately liquidated
     * @param clToken The market to check if deprecated
     */
    function isDeprecated(address clToken) public view returns (bool) {
        return
            markets[clToken].collateralFactorMantissa == 0 &&
            borrowGuardianPaused[clToken] == true &&
            IClToken(clToken).reserveFactorMantissa() == 1e18;
    }

    function getBlockNumber() public view virtual returns (uint) {
        return block.number;
    }

    function _addMarketInternal(address clToken) internal {
        for (uint i = 0; i < allMarkets.length; i++) {
            if (allMarkets[i] == clToken) {
                revert MarketAlreadyAdded();
            }
        }
        allMarkets.push(clToken);
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

    /// @dev Checks if caller is admin
    function _onlyAdmin() internal view {
        if (msg.sender != admin) revert NotAdmin();
    }
}
