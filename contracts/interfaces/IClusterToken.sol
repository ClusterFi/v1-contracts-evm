// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IClusterToken is IERC20 {
    event Minted(address indexed minter, address indexed to, uint256 amount);

    error ZeroAddress();
    error AlreadyInitialMinted();
    error OnlyMinter(address caller);

    function minter() external view returns (address);
}
