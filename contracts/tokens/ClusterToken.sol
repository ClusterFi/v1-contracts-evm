// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract ClusterToken is ERC20, ERC20Burnable, ERC20Permit, Ownable {

    event Minted(address indexed minter, address indexed to, uint256 amount);

    error ZeroAddress();
    error AlreadyInitialMinted();
    error OnlyMinter(address caller);

    bool public initialMinted = false;

    address public minter;

    constructor(address initialOwner)
        ERC20("ClusterToken", "CLR")
        ERC20Permit("ClusterToken")
        Ownable(initialOwner)
    {
        _mint(initialOwner, 0);
    }

    /**
     * @notice Sets a minter address, only called by an owner.
     * @param _minter The account to access a minter role.
     */
    function setMinter(address _minter) external onlyOwner {
        if (_minter == address(0)) revert ZeroAddress();
        minter = _minter;
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
     * @param _account The receiver address.
     * @param _amount The amount to mint.
     */
    function mint(address _account, uint256 _amount) external {
        if (msg.sender != minter) revert OnlyMinter(msg.sender);
        _mint(_account, _amount);
        emit Minted(msg.sender, _account, _amount);
    }
}
