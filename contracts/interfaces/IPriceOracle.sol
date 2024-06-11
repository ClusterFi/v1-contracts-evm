// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IClErc20 } from "./IClErc20.sol";

interface IPriceOracle {
    /// @dev Emitted when a new price override by admin is posted
    event PricePosted(
        address asset,
        uint256 previousPriceMantissa,
        uint256 requestedPriceMantissa,
        uint256 newPriceMantissa
    );

    /// @dev Emitted when a new feed is set
    event FeedSet(address feed, string symbol);

    error InvalidAnswer();
    error InvalidUpdatedAt();
    error InvalidFeedAddress();

    function isPriceOracle() external view returns (bool);

    /**
     * @notice Gets the underlying price of a clErc20 asset
     * @param _clErc20 The clErc20 to get the underlying price of
     * @return The underlying asset price mantissa (scaled by 1e18).
     *  Zero means the price is unavailable.
     */
    function getUnderlyingPrice(IClErc20 _clErc20) external view returns (uint256);
}
