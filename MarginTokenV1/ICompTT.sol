// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;

import "./IChainlinkOracle.sol";
import "./ITrendToken.sol";
import "./CompTT.sol";


contract ICompTT {

    function oracle() external view returns (IOracle);
    function compVenus() external view returns(address);
    function protocolPaused() external view returns(bool);
    //function depositOrRedeemAllowed(address trendToken, uint amount) external view returns(bool);
    //function tradeAllowed(address trendToken, uint amount) external view returns (bool);
    //function returnVToken(address underlying) external view returns(address);



    // Trend Token return functions
    function isLockedTrendToken(address trendToken) external view returns(bool); // .isLocked --> allows Trend Tokens manager to make changes
    function trendTokenActiveStatus(address trendToken) external view returns(bool); // .isActive
    function trendTokenUserActions(address trendToken) external view returns(bool,bool,bool); // .isDeposit, .isRedeem, .isTrade
    function trendTokenVenusActions(address trendToken) external view returns(bool, bool); // .isSupply, .isBorrow
    function trendTokenMaxFees(address trendToken) external view returns(uint,uint) ; // (maxTradeFee,maxPerformanceFee)
    function trendTokenMaxValues(address trendToken) external view returns(uint,uint,uint); // (.maxDiableValue, .maxBorrowFactor, .maxMargin)


    // Underlying return functions
    function underlyingSupported(address underlying) external view returns(bool);
    function priceBEP20(IERC20 _underlying) external view returns(uint256); // price of underlying
    function underlyingActiveStatus(address underlying) external view returns(bool); // isActive
    function underlyingForUserActions(address underlying) external view returns(bool,bool,bool); // isDeposit, isRedeem, isTrade
    function returnVToken(address underlying) external view returns(address); // .vToken
    function underlyingForVenusActions(address underlying) external view returns(bool,bool,bool); // isActiveVenus, isSupplyVenus, isRedeemVenus




    // Portfolio permissions
    function permissionPortfolio(address trendToken, address underlying, bool isSupply, bool isBorrow) external view returns(bool);

    // Trend Token permissions
    function permissionDepositTT(address trendToken, address underlyingIn, uint amount) external view returns(bool);
    function permissionRedeemTT(address trendToken, address underlyingOut, uint amount) external view returns(bool);
    function permissionTrade(address trendToken, address underlyingIn, address underlyingOut, uint amount) external view returns(bool);

    // Venus permissions
    function permissionSupply(address trendToken, address underlying, uint supplyAmount) external view returns(address);
    function permissionRedeem(address trendToken, address underlying, uint redeemAmount) external view returns(address);
    function permissionBorrow(address trendToken, address underlying, uint borrowAmount) external view returns(address);
    function permissionRepay(address trendToken, address underlying, uint repayAmount) external view returns(address);

    

}