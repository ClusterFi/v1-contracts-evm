// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { AggregatorV3Interface } from "../interfaces/external/AggregatorV3Interface.sol";

contract ChainlinkOracleMock is AggregatorV3Interface {
    // fixed value
    int256 private _value;
    uint8 private _decimals;

    // mocked data
    uint80 private _roundId;
    uint256 private _startedAt;
    uint256 private _updatedAt;
    uint80 private _answeredInRound;

    constructor(int256 value, uint8 oracleDecimals) {
        _value = value;
        _decimals = oracleDecimals;
        _roundId = 42;
        _startedAt = 1620651856;
        _updatedAt = 1620651856;
        _answeredInRound = 42;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external pure override returns (string memory) {
        return "Mock Chainlink Oracle";
    }

    function getRoundData(
        uint80 _getRoundId
    )
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_getRoundId, _value, 1620651856, 1620651856, _getRoundId);
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, _value, block.timestamp, block.timestamp, _answeredInRound);
    }

    function set(
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) external {
        _roundId = roundId;
        _value = answer;
        _startedAt = startedAt;
        _updatedAt = updatedAt;
        _answeredInRound = answeredInRound;
    }

    function version() external pure override returns (uint256) {
        return 1;
    }
}
