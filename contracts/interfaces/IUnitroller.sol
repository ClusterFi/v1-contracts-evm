// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IUnitroller {
    function admin() external view returns (address);
    function acceptImplementation() external;
}
