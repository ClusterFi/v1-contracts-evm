// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.20;

/**
  * @title Cluster's InterestRateModel Abstract
  * @author Cluster
  * @notice An abstract interest rate model contract with no functions that defines an interface for all interest rate models. 
  * This contract is used by the JumpRateModel contract.
  * This is a modified version of the Compound InterestRateModel interface
  * https://github.com/compound-finance/compound-protocol/blob/master/contracts/InterestRateModel.sol
  */
abstract contract InterestRateModel {
    /// @notice Indicator that this is an InterestRateModel contract (for inspection)
    bool public constant isInterestRateModel = true;

    /**
      * @notice Calculates the current borrow interest rate per block
      * @param cash The total amount of cash the market has
      * @param borrows The total amount of borrows the market has outstanding
      * @param reserves The total amount of reserves the market has
      * @return The borrow rate per block (as a percentage, and scaled by 1e18)
      */
    function getBorrowRate(
      uint cash, 
      uint borrows, 
      uint reserves
    ) external view virtual returns (uint);

    /**
      * @notice Calculates the current supply interest rate per block
      * @param cash The total amount of cash the market has
      * @param borrows The total amount of borrows the market has outstanding
      * @param reserves The total amount of reserves the market has
      * @param reserveFactorMantissa The current reserve factor the market has
      * @return The supply rate per block (as a percentage, and scaled by 1e18)
      */
    function getSupplyRate(
      uint cash, 
      uint borrows, 
      uint reserves, 
      uint reserveFactorMantissa
    ) external view virtual returns (uint);
}