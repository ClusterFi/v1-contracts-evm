// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IFlashLoanRecipient } from "./interfaces/balancer/IFlashLoanRecipient.sol";
import { IVault } from "./interfaces/balancer/IVault.sol";
import { ISwapRouter } from "./interfaces/uniswap/ISwapRouter.sol";
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
contract Leverage is ILeverage, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant DIVISOR = 1e4;
    uint16 public constant MAX_LEVERAGE = 40_000; // in {DIVISOR} terms. f.g. 40_000 = 4.0;
    // Default fee percentage (can be updated via admin function below)
    uint256 public leverageFee = 0; // basis points, f.g. 0.25% = 25 bps

    // BALANCER VAULT
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    // Comptroller
    address public comptroller;

    // add mapping to store the allowed tokens. Mapping provides faster access than array
    mapping(address => bool) public allowedTokens;
    // add mapping to store clToken contracts
    mapping(address => address) private clTokenMapping;
    // add mapping to store lToken collateral factors
    mapping(address => uint256) private collateralFactor;

    constructor(address _comptroller) Ownable (msg.sender) {
        comptroller = _comptroller;
    }

    /**
     * @notice Allows the owner to add a token for leverage
     * @param _clToken The address of clToken contract to add
     */
    function addToken(address _clToken) external onlyOwner {
        address underlying = IClErc20(_clToken).underlying();

        if (underlying == address(0)) revert InvalidMarket();
        if (allowedTokens[underlying]) revert AlreadyAllowedMarket();

        (
            bool isListed,
            uint256 collateralFactorMantissa
        ) = IComptroller(comptroller).getMarketInfo(_clToken);

        if (!isListed) revert MarketIsNotListed();

        allowedTokens[underlying] = true;

        clTokenMapping[underlying] = _clToken;
        collateralFactor[underlying] = collateralFactorMantissa;
    }

    /**
     * @notice Allows the owner to remove a token from leverage
     * @param _clToken The address of clToken contract to remove
     */
    function removeToken(address _clToken) external onlyOwner {
        address underlying = IClErc20(_clToken).underlying();

        if (underlying == address(0)) revert InvalidMarket();
        if (!allowedTokens[underlying]) revert NotAllowedMarket();

        allowedTokens[underlying] = false;

        // nullify, essentially, existing records
        delete clTokenMapping[underlying];
        delete collateralFactor[underlying];
    }

    /**
     * @notice Allows the owner to update the protocol's fee percentage
     * @param _leverageFee The new fee percentage
     */
    function updateLeverageFee(uint256 _leverageFee) external onlyOwner {
        leverageFee = _leverageFee;

        emit LeverageFeeUpdated(_leverageFee);
    }

    function loop(
        address _token,
        uint256 _collateralAmount,
        uint256 _borrowAmount
    ) external nonReentrant {
        if (!allowedTokens[_token]) revert NotAllowedMarket();
        if (_borrowAmount == 0) revert ZeroBorrowAmount();

        address _clToken = clTokenMapping[_token];
        if (_collateralAmount > 0) {
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _collateralAmount);

            // Supply
            IERC20(_token).approve(_clToken, _collateralAmount);
            IClErc20(_clToken).mint(_collateralAmount);
        }
        // Recalculate borrow amount considering leverage fee
        // _borrowAmount = _borrowAmount * (DIVISOR + leverageFee) / DIVISOR;
        
        if (IERC20(_token).balanceOf(BALANCER_VAULT) < _borrowAmount) {
            revert TooMuchForFlashloan();
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

        IVault(BALANCER_VAULT).flashLoan(IFlashLoanRecipient(address(this)), tokens, amounts, abi.encode(userData));
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
    ) external override nonReentrant {
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
        IERC20(uData.borrowedToken).safeTransferFrom(uData.user, msg.sender, repayAmount);
    }

    /**
     * @dev Internal helper function that calculates the notional loan amount based on
     * the token quantity and the leverage. Computed by multiplying the notional token amount by the leverage factor
     * (minus the divisor), then dividing by the divisor.
     * Note: The function assumes that the inputs (_notionalTokenAmountIn1e18 and _leverage) have been validated beforehand.
     * @param _notionalTokenAmountIn1e18 The quantity of the token, represented in a denomination of 1e18.
     * @param _leverage The leverage factor to apply to the loan amount.
     * @return The notional loan amount.
     */
    function _getNotionalLoanAmountIn1e18(
        uint256 _notionalTokenAmountIn1e18,
        uint16 _leverage
    ) private pure returns (uint256) {
        unchecked {
            return ((_leverage - DIVISOR) * _notionalTokenAmountIn1e18) / DIVISOR;
        }
    }
}
