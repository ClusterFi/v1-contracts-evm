// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @notice rETH is a tokenised stake in the Rocket Pool network.
 * rETH is backed by ETH (subject to liquidity) at a variable exchange rate.
 */
contract RETHMock is ERC20 {
    error TotalEthBalanceIsZero();
    error ZeroAmount();
    error InsufficientBalance();

    uint256 public rethSupply;
    uint256 public totalEthBalance;

    /// @notice Version of the contract
    uint8 public version;

    constructor() ERC20("Rocket Pool ETH", "rETH") {
        version = 1;
    }

    function setRethSupply(uint256 _rethSupply) public {
        rethSupply = _rethSupply;
    }

    function setTotalEthBalance(uint256 _totalEthBalance) public {
        totalEthBalance = _totalEthBalance;
    }

    /// @notice Calculate the amount of ETH backing an amount of rETH
    function getEthValue(uint256 _rethAmount) public view returns (uint256) {
        // Use 1:1 ratio if no rETH is minted
        if (rethSupply == 0) return _rethAmount;
        // Calculate and return
        return (_rethAmount * totalEthBalance) / rethSupply;
    }

    /// @notice Calculate the amount of rETH backed by an amount of ETH
    function getRethValue(uint256 _ethAmount) public view returns (uint256) {
        // Use 1:1 ratio if no rETH is minted
        if (rethSupply == 0) return _ethAmount;
        // Check network ETH balance
        // Cannot calculate rETH token amount while total network balance is zero
        if (totalEthBalance == 0) {
            revert TotalEthBalanceIsZero();
        }
        // Calculate and return
        return (_ethAmount * rethSupply) / totalEthBalance;
    }

    /// @notice Get the current ETH : rETH exchange rate
    /// Returns the amount of ETH backing 1 rETH
    function getExchangeRate() external view returns (uint256) {
        return getEthValue(1 ether);
    }

    // Mint rETH from ETH
    function mint(uint256 _ethAmount, address _to) external {
        // Get rETH amount
        uint256 rethAmount = getRethValue(_ethAmount);
        // Check rETH amount
        if (rethAmount == 0) revert ZeroAmount();
        // Update balance & supply
        _mint(_to, rethAmount);
    }

    // Burn rETH for ETH
    function burn(uint256 _rethAmount) external {
        // Check rETH amount
        if (_rethAmount == 0) revert ZeroAmount();
        if (balanceOf(msg.sender) < _rethAmount) revert InsufficientBalance();
        // Get ETH amount
        uint256 ethAmount = getEthValue(_rethAmount);
        // Update balance & supply
        _burn(msg.sender, _rethAmount);
        // Transfer ETH to sender
        payable(msg.sender).transfer(ethAmount);
    }
}
