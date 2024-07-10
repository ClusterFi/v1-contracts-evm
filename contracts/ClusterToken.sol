// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IClusterToken } from "./interfaces/IClusterToken.sol";

contract ClusterToken is ERC20, ERC20Burnable, ERC20Permit, Ownable, IClusterToken {
    bool public initialMinted = false;

    address public minter;

    constructor(
        address initialOwner
    ) ERC20("ClusterToken", "CLR") ERC20Permit("ClusterToken") Ownable(initialOwner) {
        _mint(initialOwner, 0);
    }

    /**
     * @notice Sets a minter address, only called by an owner.
     * @param minter_ The account to access a minter role.
     */
    function setMinter(address minter_) external onlyOwner {
        if (minter_ == address(0)) revert ZeroAddress();
        minter = minter_;
    }

    /**
     * @notice Creates initial supply, called only once by an owner.
     * @param recipient The address to receive initial supply.
     * @param amount The amount to mint
     */
    function initialMint(address recipient, uint256 amount) external onlyOwner {
        if (initialMinted) revert AlreadyInitialMinted();
        initialMinted = true;
        _mint(recipient, amount);
    }

    /**
     * @notice Creates specific amount of tokens and assigns them to `account`.
     * @dev Only called by an account with a minter role.
     * @param account The receiver address.
     * @param amount The amount to mint.
     */
    function mint(address account, uint256 amount) external {
        if (msg.sender != minter) revert OnlyMinter(msg.sender);
        _mint(account, amount);
        emit Minted(msg.sender, account, amount);
    }
}
