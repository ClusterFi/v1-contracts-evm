// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.20;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IClErc20 } from "./interfaces/IClErc20.sol";
import { ClToken } from "./base/ClToken.sol";

/**
 * @title Cluster's ClErc20 Contract
 * @notice ClTokens which wrap an EIP-20 underlying
 * @dev Modified from Compound V2 CErc20Immutable
 * (https://github.com/compound-finance/compound-protocol/blob/master/contracts/CErc20Immutable.sol)
 * @author Cluster
 */
contract ClErc20 is IClErc20, ClToken {
    using SafeERC20 for IERC20;

    /**
     * @notice Underlying asset for this clToken
     */
    address public underlying;

    /**
     * @notice Initialize the new money market
     * @param _underlying The address of the underlying asset
     * @param _comptroller The address of the Comptroller
     * @param _interestRateModel The address of the interest rate model
     * @param _initialExchangeRateMantissa The initial exchange rate, scaled by 1e18
     * @param _name ERC-20 name of this token
     * @param _symbol ERC-20 symbol of this token
     * @param _decimals ERC-20 decimal precision of this token
     * @param _admin Address of the administrator of this token
     */
    constructor(
        address _underlying,
        address _comptroller,
        address _interestRateModel,
        uint _initialExchangeRateMantissa,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address payable _admin
    ) {
        // Creator of the contract is admin during initialization
        admin = payable(msg.sender);

        // ClToken initialize does the bulk of the work
        super.initialize(
            _comptroller,
            _interestRateModel,
            _initialExchangeRateMantissa,
            _name,
            _symbol,
            _decimals
        );

        // Set underlying and sanity check it
        underlying = _underlying;
        IERC20(underlying).totalSupply();

        admin = _admin;
    }

    /*** User Interface ***/

    /**
     * @notice Sender supplies assets into the market and receives clTokens in exchange
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param _mintAmount The amount of the underlying asset to supply
     */
    function mint(uint _mintAmount) external override {
        mintInternal(_mintAmount);
    }

    /**
     * @notice Sender redeems clTokens in exchange for the underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param _redeemTokens The number of clTokens to redeem into underlying
     */
    function redeem(uint _redeemTokens) external override {
        redeemInternal(_redeemTokens);
    }

    /**
     * @notice Sender redeems clTokens in exchange for a specified amount of underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param _redeemAmount The amount of underlying to redeem
     */
    function redeemUnderlying(uint _redeemAmount) external override {
        redeemUnderlyingInternal(_redeemAmount);
    }

    /**
     * @notice Sender borrows assets from the protocol to their own address
     * @param _borrowAmount The amount of the underlying asset to borrow
     */
    function borrow(uint _borrowAmount) external override {
        borrowInternal(_borrowAmount);
    }

    /**
     * @notice Sender borrows assets from the protocol to the specific borrower
     * @dev The caller must be leverage contract otherwise reverts
     * @param borrowAmount The amount of the underlying asset to borrow
     * @param borrower the user to borrow on behalf of
     */
    function borrowBehalf(address borrower, uint borrowAmount) external override {
        borrowBehalfInternal(borrower, borrowAmount);
    }

    /**
     * @notice Sender repays their own borrow
     * @param _repayAmount The amount to repay, or -1 for the full outstanding amount
     */
    function repayBorrow(uint _repayAmount) external override {
        repayBorrowInternal(_repayAmount);
    }

    /**
     * @notice Sender repays a borrow belonging to borrower
     * @param _borrower the account with the debt being payed off
     * @param _repayAmount The amount to repay, or -1 for the full outstanding amount
     */
    function repayBorrowBehalf(address _borrower, uint _repayAmount) external override {
        repayBorrowBehalfInternal(_borrower, _repayAmount);
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param _borrower The borrower of this clToken to be liquidated
     * @param _repayAmount The amount of the underlying borrowed asset to repay
     * @param _clTokenCollateral The market in which to seize collateral from the borrower
     */
    function liquidateBorrow(
        address _borrower,
        uint _repayAmount,
        address _clTokenCollateral
    ) external override {
        liquidateBorrowInternal(_borrower, _repayAmount, _clTokenCollateral);
    }

    /**
     * @notice A public function to sweep accidental ERC-20 transfers to this contract.
     * Tokens are sent to admin
     * @param _token The address of the ERC-20 token to sweep
     */
    function sweepToken(address _token) external override {
        if (msg.sender != admin) revert NotAdmin();
        if (_token == underlying) revert CanNotSweepUnderlyingToken();

        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(admin, balance);
    }

    /**
     * @notice The sender adds to reserves.
     * @param _addAmount The amount fo underlying token to add as reserves
     */
    function addReserves(uint _addAmount) external override {
        _addReservesInternal(_addAmount);
    }

    /*** Safe Token ***/

    /**
     * @notice Gets balance of this contract in terms of the underlying
     * @dev This excludes the value of the current message, if any
     * @return The quantity of underlying tokens owned by this contract
     */
    function getCashPrior() internal view virtual override returns (uint) {
        return IERC20(underlying).balanceOf(address(this));
    }

    /**
     * @dev Similar to EIP20 transfer, except it handles a False result from `transferFrom` and reverts in that case.
     * This will revert due to insufficient balance or insufficient allowance.
     * This function returns the actual amount received,
     * which may be less than `amount` if there is a fee attached to the transfer.
     *
     * Note: This wrapper safely handles non-standard ERC-20 tokens that do not return a value.
     * See here: https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
     */
    function doTransferIn(address _from, uint _amount) internal virtual override returns (uint) {
        // Read from storage once
        address _underlying = underlying;
        uint balanceBefore = IERC20(_underlying).balanceOf(address(this));
        IERC20(_underlying).safeTransferFrom(_from, address(this), _amount);

        // Calculate the amount that was *actually* transferred
        uint balanceAfter = IERC20(_underlying).balanceOf(address(this));
        // underflow already checked above, just subtract
        return balanceAfter - balanceBefore;
    }

    /**
     * @dev Similar to EIP20 transfer, except it handles a False success from `transfer` and returns an explanatory
     * error code rather than reverting. If caller has not called checked protocol's balance, this may revert due to
     * insufficient cash held in this contract. If caller has checked protocol's balance prior to this call,
     * and verified it is >= amount, this should not revert in normal conditions.
     *
     * Note: This wrapper safely handles non-standard ERC-20 tokens that do not return a value.
     * See here: https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
     */
    function doTransferOut(address payable _to, uint _amount) internal virtual override {
        IERC20(underlying).safeTransfer(_to, _amount);
    }
}
