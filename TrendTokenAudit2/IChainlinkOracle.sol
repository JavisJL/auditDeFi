// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;

import "./AggregatorV2V3Interface.sol";

interface IOracle {
    function getUnderlyingPrice(address vtoken) external view returns(uint256);

    function getFeed(string calldata symbol) external view returns (AggregatorV2V3Interface);
    function getChainlinkPrice(AggregatorV2V3Interface feed) external view returns (uint);

}

