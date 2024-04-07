// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;

import "./AggregatorV2V3Interface.sol";

interface IOracle {
    
    function compTT() external view returns(address);
    function getPriceFromAddress(address underlying) external view returns (uint price);
    function getFeed(address underlying) external view returns (AggregatorV2V3Interface);

}

