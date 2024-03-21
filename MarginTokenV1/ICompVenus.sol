// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;

interface ICompVenus {

    function getXVSAddress() external view returns(address);
    function enterMarkets(address[] calldata _markets) external returns(uint[] memory);
    function claimVenus(address _recipient) external;
    function venusAccrued(address holder) external view returns(uint256);
    function getAssetsIn(address account) external view returns (address[] memory);
    
    function markets(address vTokenAddress) external view returns (bool, uint, bool); // (isListed, collateralFactorMantissa, isXvsed)
    
    function getAccountLiquidity(address account) external view returns (uint, uint, uint); //  (error, liquidity, shortfall)
    function closeFactorMantissa() external view returns (uint); // multiply by token borrow balance to see how much can be repaid
    function exitMarket(address vToken) external returns (uint);
    
    function checkMembership(address account, address vToken) external view returns (bool);
    function oracle() external view returns (address);
    function comptrollerLens() external view returns(address); 

    // Comptroller Lens
    function getHypotheticalAccountLiquidity(address comptroller,address account,address vTokenModify,uint redeemTokens,uint borrowAmount) external view returns (uint, uint, uint);
    




}
