// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

library OracleLib {
    
    error OracleLib__PriceFeedStale();

    uint256 private constant TIMEOUT = 3 hours;

    function staleCheckLatestRoundData(AggregatorV3Interface pricefeed) 
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = pricefeed.latestRoundData();

        uint256 secondsSince = block.timestamp - updatedAt;
        if(secondsSince > TIMEOUT) revert OracleLib__PriceFeedStale();

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}