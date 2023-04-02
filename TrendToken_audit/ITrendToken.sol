// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16; 

import "./IVBep20.sol";
import "./ITrendTokenTkn.sol";
import "./IIncentiveModelSimple.sol";

interface ITrendToken {

    /**
     * @notice For lens
     */
    function incentiveModel() external view returns(IIncentiveModelSimple);
    function storedEquity() external view returns(address[] memory,uint[] memory,uint[] memory,uint[] memory,uint[] memory,uint);
    function trendToken() external view returns(ITrendTokenTkn);
    function performanceFee() external view returns(uint);



    function lastRebalance() external view returns(uint);
    function isTrendToken() external view returns(bool);

    function dBNB() external view returns(IVBep20);
    function priceExt(IVBep20 _dToken) external view returns(uint);
    function trendTokenToUSD() external view returns(uint,uint);
    function trendTokenOutExternal(IERC20 _depositBep20, IVBep20 _dToken, uint _sellAmtBEP20) external view returns(uint, uint, uint, uint, uint, int); 
    function trendTokenInExternal(IERC20 _redeemBep20, IVBep20 _dToken, uint _redeemAmt) external view returns(uint, uint, uint, uint, uint, int);

}