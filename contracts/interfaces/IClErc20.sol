// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IClErc20 {
    /*** Errors ***/

    error CanNotSweepUnderlyingToken();

    /*** View Functions ***/

    function underlying() external view returns (address);

    /*** User Functions ***/

    function mint(uint _mintAmount) external;

    function redeem(uint _redeemTokens) external;

    function redeemUnderlying(uint _redeemAmount) external;

    function borrow(uint _borrowAmount) external;

    function borrowBehalf(address _borrower, uint _borrowAmount) external;

    function repayBorrow(uint _repayAmount) external;

    function repayBorrowBehalf(address _borrower, uint _repayAmount) external;

    function liquidateBorrow(
        address _borrower,
        uint _repayAmount,
        address _clTokenCollateral
    ) external;

    function sweepToken(address _token) external;

    /*** Admin Functions ***/

    function addReserves(uint _addAmount) external;
}
