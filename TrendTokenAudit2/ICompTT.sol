// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;

import "./IChainlinkOracle.sol";
import "./ITrendToken.sol";
import "./CompTT.sol";


contract ICompTT {

    function oracle() external view returns (IOracle);
    function protocolPaused() external view returns(bool);
    function depositOrRedeemAllowed(address trendToken, uint amount) external view returns(bool);
    function tradeAllowed(address trendToken, uint amount) external view returns (bool);
    function returnDToken(address underlying) external view returns(address);

    function trendTokenIsListed(address trendToken) external view returns(bool);
    function trendTokenIsActive(address trendToken) external view returns(bool);
    function trendTokenIsTrade(address trendToken) external view returns(bool);
    function trendTokenAllowedDualPools(address trendToken) external view returns(bool);
    function trendTokenMaxTradeFee(address trendToken) external view returns(uint);
    function trendTokenMaxPerformanceFee(address trendToken) external view returns(uint);
    function trendTokenMaxDisableValue(address trendToken) external view returns(uint);

}