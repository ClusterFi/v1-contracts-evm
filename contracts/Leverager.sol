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
import { ILeverager } from "./interfaces/ILeverager.sol";

/**
 * @title Leverager
 * @notice This contract allows users to leverage their positions by borrowing 
 * assets, increasing their supply and thus enabling higher yields.
 * @dev The contract implements the Ownable, IFlashLoanRecipient, and ReentrancyGuard. 
 * It uses SafeERC20 for safe token transfers.
 * @author Cluster
 */
contract Leverager is ILeverager, Ownable, IFlashLoanRecipient, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant DIVISOR = 1e4;
    uint16 public constant MAX_LEVERAGE = 40_000; // in {DIVISOR} terms. f.g. 40_000 = 4.0;
    // Default fee percentage (can be updated via admin function below)
    uint256 public protocolFee = 0; // basis points, f.g. 0.25% = 25 bps

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
     * @param _protocolFee The new fee percentage
     */
    function updateProtocolFee(uint256 _protocolFee) external onlyOwner {
        protocolFee = _protocolFee;

        emit ProtocolFeeUpdated(_protocolFee);
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

        UserData memory data = abi.decode(userData, (UserData));

        // TODO
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
