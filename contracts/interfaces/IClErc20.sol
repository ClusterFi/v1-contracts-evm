// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IClErc20 {
    /*** View Functions ***/
    function underlying() external view returns (address);

    /*** User Functions ***/
    function mint(uint _mintAmount) external returns (uint);
    function redeem(uint _redeemTokens) external returns (uint);
    function redeemUnderlying(uint _redeemAmount) external returns (uint);
    function borrow(uint _borrowAmount) external returns (uint);
    function repayBorrow(uint _repayAmount) external returns (uint);
    function repayBorrowBehalf(
        address _borrower,
        uint _repayAmount
    ) external returns (uint);
    function liquidateBorrow(
        address _borrower,
        uint _repayAmount,
        address _clTokenCollateral
    ) external returns (uint);
    function sweepToken(address _token) external;

    /*** Admin Functions ***/
    function addReserves(uint _addAmount) external returns (uint);
}
