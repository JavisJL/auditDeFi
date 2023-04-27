// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;

interface ICompDP {

    function enterMarkets(address[] calldata _markets) external returns(uint[] memory);
    function claimXDP(address _recipient) external;
    function venusAccrued(address holder) external view returns(uint256);
    function getAssetsIn(address account) external view returns (address[] memory);
    
    function markets(address vTokenAddress) external view returns (bool, uint, bool); // (isListed, collateralFactorMantissa, isXvsed)
    
    function getAccountLiquidity(address account) external view returns (uint, uint, uint); //  (error, liquidity, shortfall)
    function closeFactorMantissa() external view returns (uint); // multiply by token borrow balance to see how much can be repaid
    function exitMarket(address vToken) external returns (uint);
    function getHypotheticalAccountLiquidity(address account,address vTokenModify,uint redeemTokens,uint borrowAmount) external view returns (uint, uint, uint);
    
    function checkMembership(address account, address vToken) external view returns (bool);

    
    //** ----------- Trade Functionlaity ----------- **//
    function iUSDaddress() external pure returns(address); // in contract, delared public (so might not work as external




}
