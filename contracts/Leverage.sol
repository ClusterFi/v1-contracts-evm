// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IFlashLoanRecipient } from "./interfaces/balancer/IFlashLoanRecipient.sol";
import { IVault } from "./interfaces/balancer/IVault.sol";
import { IComptroller } from "./interfaces/IComptroller.sol";
import { IClErc20 } from "./interfaces/IClErc20.sol";
import { IClToken } from "./interfaces/IClToken.sol";
import { ILeverage } from "./interfaces/ILeverage.sol";

/**
 * @title Leverager
 * @notice This contract allows users to leverage their positions by borrowing
 * assets, increasing their supply and thus enabling higher yields.
 * @dev The contract implements the Ownable, IFlashLoanRecipient, and ReentrancyGuard.
 * It uses SafeERC20 for safe token transfers.
 * @author Cluster
 */
contract Leverage is ILeverage, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    // BALANCER VAULT
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    // Comptroller
    address public comptroller;

    // add mapping to store the allowed tokens. Mapping provides faster access than array
    mapping(address => bool) public allowedTokens;
    // add mapping to store clToken contracts
    mapping(address => address) public clTokenMapping;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _comptroller) public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        comptroller = _comptroller;
    }

    /**
     * @notice Allows the owner to add a token for leverage
     * @param _clToken The address of clToken contract to add
     */
    function addMarket(address _clToken) external onlyOwner {
        if (_clToken == address(0)) revert InvalidMarket();

        address underlying = IClErc20(_clToken).underlying();
        if (allowedTokens[underlying]) revert AlreadyAllowedMarket();

        (bool isListed, ) = IComptroller(comptroller).getMarketInfo(_clToken);

        if (!isListed) revert MarketIsNotListed();

        allowedTokens[underlying] = true;
        clTokenMapping[underlying] = _clToken;

        emit AddMarket(_clToken, underlying);
    }

    /**
     * @notice Allows the owner to remove a token from leverage
     * @param _clToken The address of clToken contract to remove
     */
    function removeMarket(address _clToken) external onlyOwner {
        if (_clToken == address(0)) revert InvalidMarket();

        address underlying = IClErc20(_clToken).underlying();
        if (!allowedTokens[underlying]) revert NotAllowedMarket();

        allowedTokens[underlying] = false;

        // nullify, essentially, existing records
        delete clTokenMapping[underlying];

        emit RemoveMarket(_clToken, underlying);
    }

    function loop(address _token, uint256 _amount, uint256 _borrowAmount) external nonReentrant {
        if (!allowedTokens[_token]) revert NotAllowedMarket();

        address _clToken = clTokenMapping[_token];
        if (_amount > 0) {
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

            // Supply
            IERC20(_token).approve(_clToken, _amount);
            uint256 beforeBalance = IERC20(_clToken).balanceOf(address(this));
            IClErc20(_clToken).mint(_amount);
            uint256 afterBalance = IERC20(_clToken).balanceOf(address(this));
            IClToken(_clToken).transfer(msg.sender, afterBalance - beforeBalance);
        }

        if (_borrowAmount > 0) {
            if (IERC20(_token).balanceOf(BALANCER_VAULT) < _borrowAmount) {
                revert TooMuchBorrow();
            }

            IERC20[] memory tokens = new IERC20[](1);
            tokens[0] = IERC20(_token);

            uint256[] memory amounts = new uint256[](1);
            amounts[0] = _borrowAmount;

            UserData memory userData = UserData({
                user: msg.sender,
                borrowedToken: _token,
                borrowedAmount: _borrowAmount
            });

            IVault(BALANCER_VAULT).flashLoan(
                IFlashLoanRecipient(address(this)),
                tokens,
                amounts,
                abi.encode(userData)
            );
        }
    }

    /**
     * @notice Callback function to be executed after the flash loan operation
     * @param tokens Array of token addresses involved in the loan
     * @param amounts Array of token amounts involved in the loan
     * @param feeAmounts Array of fee amounts for the loan
     * @param userData Data regarding the user of the loan
     */
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        if (msg.sender != BALANCER_VAULT) revert NotBalancerVault();

        uint256 feeAmount = 0;
        if (feeAmounts.length > 0) {
            feeAmount = feeAmounts[0]; // balancer flashloan fee, currently 0
        }

        UserData memory uData = abi.decode(userData, (UserData));
        // ensure we borrowed the proper amounts
        if (uData.borrowedAmount != amounts[0] || uData.borrowedToken != address(tokens[0])) {
            revert InvalidLoanData();
        }

        address _clToken = clTokenMapping[uData.borrowedToken];

        // supply borrowed amount
        IERC20(uData.borrowedToken).approve(_clToken, uData.borrowedAmount);
        IClErc20(_clToken).mint(uData.borrowedAmount);

        // transfer minted clTokens to user
        uint256 clTokenAmount = IClToken(_clToken).balanceOf(address(this));
        IClToken(_clToken).transfer(uData.user, clTokenAmount);

        uint256 repayAmount = uData.borrowedAmount + feeAmount;
        // borrow on behalf of user to repay flashloan
        IClErc20(_clToken).borrowBehalf(uData.user, repayAmount);

        // repay flashloan, where msg.sender = vault
        IERC20(uData.borrowedToken).safeTransferFrom(uData.user, BALANCER_VAULT, repayAmount);
    }
}
