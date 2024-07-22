// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { AggregatorV3Interface } from "./interfaces/external/AggregatorV3Interface.sol";
import { IStETH } from "./interfaces/external/IStETH.sol";

/**
 * @title CompositeChainlinkOracle
 * @notice Combines multiple chainlink oracle prices together.
 * allows combination of either 2 or 3 chainlink oracles.
 */
contract CompositeChainlinkOracle {
    error InvalidExpectedDecimals();
    error InvalidOracleData();

    /// @notice reference to a base price feed chainlink oracle
    /// in case of steth this would be eth/usd
    address public immutable base;

    /// @notice reference to the first multiplier. in the case of weeth or cbeth
    /// this is then eth/weeth or eth/cbeth
    address public immutable multiplier;

    /// @notice reference to the second multiplier contract
    /// this should be the wsteth/eth conversion contract
    address public immutable secondMultiplier;

    /// @notice scaling factor applied to price, always 18 decimals to avoid additional
    /// logic in the chainlink oracle contract
    /// @dev this is also used for backwards compatability in the PriceOracle.sol contract
    /// and makes that contract think this composite oracle is talking directly to chainlink
    uint8 public constant decimals = 18;

    /// @notice construct the contract
    /// @param baseAddress The base oracle address
    /// @param multiplierAddress The multiplier oracle address
    /// @param secondMultiplierAddress The second multiplier oracle address
    constructor(address baseAddress, address multiplierAddress, address secondMultiplierAddress) {
        base = baseAddress;
        multiplier = multiplierAddress;
        secondMultiplier = secondMultiplierAddress;
    }

    /// @notice Get the latest price of a base/quote pair
    /// interface for compatabililty with _getChainlinkPrice function in PriceOracle.sol
    function latestRoundData()
        external
        view
        returns (
            uint80, /// roundId always 0, value unused in PriceOracle.sol
            int256, /// the composite price
            uint256, /// startedAt always 0, value unused in PriceOracle.sol
            uint256, /// always block.timestamp
            uint80 /// answeredInRound always 0, value unused in PriceOracle.sol
        )
    {
        if (secondMultiplier == address(0)) {
            /// if there is only one multiplier, just use that
            return (
                0,
                /// fetch uint256, then cast back to int256, this cast to uint256 is a sanity check
                /// that chainlink did not return a negative value
                int256(getDerivedPrice(base, multiplier, decimals)),
                0,
                block.timestamp, /// return current block timestamp
                0
            );
        }

        /// if there is a second multiplier apply it
        return (
            0, /// unused
            int256(getDerivedPriceThreeOracles(base, multiplier, secondMultiplier, decimals)),
            0, /// unused
            block.timestamp, /// return current block timestamp
            0 /// unused
        );
    }

    /// @notice Get the derived price of a base/quote pair
    /// @param baseAddress The base oracle address
    /// @param multiplierAddress The multiplier oracle address
    /// @param expectedDecimals The expected decimals of the derived price
    /// @dev always returns positive, otherwise reverts as comptroller only accepts positive oracle values
    function getDerivedPrice(
        address baseAddress,
        address multiplierAddress,
        uint8 expectedDecimals
    ) public view returns (uint256) {
        if (expectedDecimals == 0 || expectedDecimals > 18) {
            revert InvalidExpectedDecimals();
        }

        // calculate expected decimals for end quote
        int256 scalingFactor = int256(10 ** uint256(expectedDecimals));

        int256 basePrice = getPriceAndScale(baseAddress, expectedDecimals);
        int256 quotePrice = 0;
        // Consider exchange rate stETH/wstETH on Ethereum mainnet.
        if (_compareStrings(AggregatorV3Interface(baseAddress).description(), "STETH / USD")) {
            quotePrice = int256(IStETH(multiplierAddress).getPooledEthByShares(1 ether));
        } else {
            quotePrice = getPriceAndScale(multiplierAddress, expectedDecimals);
        }
        /// both quote and base price should be scaled up to 18 decimals by now if expectedDecimals is 18
        return _calculatePrice(basePrice, quotePrice, scalingFactor);
    }

    /// @notice fetch ETH price, multiply by stETH-ETH exchange rate,
    /// then multiply by wstETH-stETH exchange rate
    /// @param usdBaseAddress The base oracle address that gets the base asset price
    /// @param multiplierAddress The multiplier oracle address that gets the multiplier asset price
    /// @param secondMultiplierAddress The second oracle address that gets the second asset price
    /// @param expectedDecimals The amount of decimals the price should have
    /// @return the derived price from all three oracles. Multiply the base price by the multiplier
    /// price, then multiply by the second multiplier price
    function getDerivedPriceThreeOracles(
        address usdBaseAddress,
        address multiplierAddress,
        address secondMultiplierAddress,
        uint8 expectedDecimals
    ) public view returns (uint256) {
        if (expectedDecimals == 0 || expectedDecimals > 18) {
            revert InvalidExpectedDecimals();
        }

        /// should never overflow as should return 1e36
        /// calculate expected decimals for end quote
        int256 scalingFactor = int256(10 ** uint256(expectedDecimals * 2));

        int256 firstPrice = getPriceAndScale(usdBaseAddress, expectedDecimals);
        int256 secondPrice = getPriceAndScale(multiplierAddress, expectedDecimals);

        int256 thirdPrice = getPriceAndScale(secondMultiplierAddress, expectedDecimals);

        return uint256((firstPrice * secondPrice * thirdPrice) / scalingFactor);
    }

    /// @notice Get the price of a base/quote pair
    /// and then scale up to the expected decimals amount
    /// @param oracleAddress The oracle address
    /// @param expectedDecimals The amount of decimals the price should have
    function getPriceAndScale(
        address oracleAddress,
        uint8 expectedDecimals
    ) public view returns (int256) {
        (int256 price, uint8 actualDecimals) = getPriceAndDecimals(oracleAddress);
        return _scalePrice(price, actualDecimals, expectedDecimals);
    }

    /// @notice helper function to retrieve price from chainlink
    /// @param oracleAddress The address of the chainlink oracle
    /// returns the price and then the decimals of the given asset
    /// reverts if price is 0 or if the oracle data is invalid
    function getPriceAndDecimals(address oracleAddress) public view returns (int256, uint8) {
        (uint80 roundId, int256 price, , , uint80 answeredInRound) = AggregatorV3Interface(
            oracleAddress
        ).latestRoundData();
        bool valid = price > 0 && answeredInRound == roundId;
        if (!valid) revert InvalidOracleData();

        uint8 oracleDecimals = AggregatorV3Interface(oracleAddress).decimals();

        return (price, oracleDecimals); /// price always gt 0 at this point
    }

    /// @notice Get the derived price of a base/quote pair with price data
    /// @param basePrice The price of the base token
    /// @param priceMultiplier The price of the quote token
    /// @param scalingFactor The expected decimals of the derived price scaled up by 10 ** decimals
    function _calculatePrice(
        int256 basePrice,
        int256 priceMultiplier,
        int256 scalingFactor
    ) internal pure returns (uint256) {
        return uint256((basePrice * priceMultiplier) / scalingFactor);
    }

    /// @notice scale price up or down to the desired amount of decimals
    /// @param price The price to scale
    /// @param priceDecimals The amount of decimals the price has
    /// @param expectedDecimals The amount of decimals the price should have
    /// @return the scaled price
    function _scalePrice(
        int256 price,
        uint8 priceDecimals,
        uint8 expectedDecimals
    ) internal pure returns (int256) {
        if (priceDecimals < expectedDecimals) {
            return price * int256(10 ** uint256(expectedDecimals - priceDecimals));
        } else if (priceDecimals > expectedDecimals) {
            return price / int256(10 ** uint256(priceDecimals - expectedDecimals));
        }

        /// if priceDecimals == expectedDecimals, return price without any changes
        return price;
    }

    function _compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
}
