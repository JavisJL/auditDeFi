// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "./IVBep20.sol";
import "./ITrendTokenTkn.sol";
import "./IIncentiveModel.sol";

interface IMarginToken {

    /**
     * @notice For lens
     */
    function incentiveModel() external view returns(IIncentiveModel);
    function storedEquityExternal() external view returns(address[] memory,uint[] memory,uint[] memory,uint[] memory,uint[] memory,uint);
    function trendToken() external view returns(ITrendTokenTkn);
    function performanceFee() external view returns(uint);
    function depositsDisabled(address underlying) external view returns(bool);


    function isTrendToken() external view returns(bool);
    function trendTokenToUSDext() external view returns(uint, uint);

    // get contract desired positions
    function portfolioTokens(uint index) external view returns(address);
    function contractAllo(uint index) external view returns(uint);
    function collateralAllo(uint index) external view returns(uint);
    function borrowAllo(uint index) external view returns(uint);


}

