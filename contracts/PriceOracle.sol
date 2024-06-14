// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IClErc20, IPriceOracle } from "./interfaces/IPriceOracle.sol";
import { AggregatorV3Interface } from "./interfaces/external/AggregatorV3Interface.sol";

/**
 * @title PriceOracle
 * @notice Stores all chainlink oracle addresses for each respective underlying asset.
 */
contract PriceOracle is IPriceOracle, Ownable {
    /// @notice Indicator that this is a PriceOracle contract (for inspection)
    bool public constant isPriceOracle = true;

    /// @notice overridden prices for assets, not used if unset
    mapping(address => uint256) internal prices;

    /// @notice chainlink feeds for assets, maps the hash of a
    /// token symbol to the corresponding chainlink feed
    mapping(bytes32 => AggregatorV3Interface) internal feeds;

    constructor() Ownable(msg.sender) {}

    /// @notice Sets the price of an asset overriding the value returned from Chainlink
    /// @param _clErc20 The clErc20 to set the price of
    /// @param _underlyingPriceMantissa The price scaled by mantissa of the asset
    function setUnderlyingPrice(
        IClErc20 _clErc20,
        uint256 _underlyingPriceMantissa
    ) external onlyOwner {
        address asset = address(IClErc20(address(_clErc20)).underlying());
        emit PricePosted(asset, prices[asset], _underlyingPriceMantissa, _underlyingPriceMantissa);
        prices[asset] = _underlyingPriceMantissa;
    }

    /// @notice Sets the price of an asset overriding the value returned from Chainlink
    /// @param _asset The asset to set the price of
    /// @param _price The price scaled by 1e18 of the asset
    function setDirectPrice(address _asset, uint256 _price) external onlyOwner {
        emit PricePosted(_asset, prices[_asset], _price, _price);
        prices[_asset] = _price;
    }

    /// @notice Sets the chainlink feed for a given token symbol
    /// @param _symbol The symbol of the clErc20's underlying token to set the feed for
    /// if the underlying token has symbol of MKR, the symbol would be "MKR"
    /// @param _feed The address of the chainlink feed
    function setFeed(string calldata _symbol, address _feed) external onlyOwner {
        if (_feed == address(0) || _feed == address(this)) {
            revert InvalidFeedAddress();
        }

        feeds[keccak256(abi.encodePacked(_symbol))] = AggregatorV3Interface(_feed);

        emit FeedSet(_feed, _symbol);
    }

    /// @notice Get the underlying price of a listed clToken asset
    /// @param _clErc20 The clToken to get the underlying price of
    /// @return The underlying asset price mantissa scaled by 1e18
    function getUnderlyingPrice(IClErc20 _clErc20) public view override returns (uint256) {
        return _getPrice(_clErc20);
    }

    /// @notice Gets the chainlink feed for a given token symbol
    /// @param _symbol The symbol of the clErc20's underlying token to get the feed for
    /// @return The address of the chainlink feed
    function getFeed(string memory _symbol) public view returns (AggregatorV3Interface) {
        return feeds[keccak256(abi.encodePacked(_symbol))];
    }

    /// @notice Gets the price of an asset from the override config
    /// @param _asset The asset to get the price of
    /// @return The price of the asset scaled by 1e18
    function assetPrices(address _asset) external view returns (uint256) {
        return prices[_asset];
    }

    /// @notice Get the underlying price of a token
    /// @param _clErc20 The clToken to get the underlying price of
    /// @return price The underlying asset price mantissa scaled by 1e18
    /// @dev if the owner sets the price override, this function will
    /// return that instead of the chainlink price
    function _getPrice(IClErc20 _clErc20) internal view returns (uint256 price) {
        IERC20Metadata token = IERC20Metadata(_clErc20.underlying());

        if (prices[address(token)] != 0) {
            price = prices[address(token)];
        } else if (address(getFeed(token.symbol())) != address(0)) {
            price = _getChainlinkPrice(getFeed(token.symbol()));
        } else {
            price = 0;
        }

        uint256 decimalDelta = uint256(18) - uint256(token.decimals());
        // Ensure that we don't multiply the result by 0
        if (decimalDelta > 0) {
            return price * (10 ** decimalDelta);
        } else {
            return price;
        }
    }

    /// @notice Gets the price of a token from Chainlink price feed
    /// @param _feed The Chainlink feed to get the price
    /// @return The price of the asset from Chainlink scaled by 1e18
    function _getChainlinkPrice(AggregatorV3Interface _feed) internal view returns (uint256) {
        (, int256 answer, , uint256 updatedAt, ) = AggregatorV3Interface(_feed).latestRoundData();

        if (answer == 0) revert InvalidAnswer();
        if (updatedAt == 0) revert InvalidUpdatedAt();

        // Chainlink USD-denominated feeds store answers at 8 decimals
        uint256 decimalDelta = uint256(18) - _feed.decimals();
        // Ensure that we don't multiply the result by 0
        if (decimalDelta > 0) {
            return uint256(answer) * (10 ** decimalDelta);
        } else {
            return uint256(answer);
        }
    }
}
