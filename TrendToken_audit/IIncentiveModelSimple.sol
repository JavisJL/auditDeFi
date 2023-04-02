// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;
//pragma experimental ABIEncoderV2;


import "./IERC20.sol";


interface IIncentiveModelSimple {

    /**
     * @notice For Lens
     */
    function protocolFeeTrade() external view returns(uint);

    function protocolFeeDeposit() external view returns(uint);

    function protocolFeeRedeem() external view returns(uint);



    function isIncentiveModel() external view returns(bool);
    function totalDepositFee(IERC20 _depositBEP20, uint _valueDeposit, int priorDelta, int postDelta, uint price, uint balanceXTT)  external view returns(int totalFee, uint protocolFeePerc, uint reward, uint fee);
    function totalRedeemFee(IERC20 _redeemBep20, uint _valueRedeem, int priorDelta, int postDelta, uint price, uint balanceXTT) external view returns(int totalFee, uint protocolFeePerc, uint reward, uint fee);
    function valueOutAfterSell(IERC20 _tokenIn, uint _valueIn, int priorDeltaIn, int postDeltaIn, uint balanceXTT) external view returns(uint redeemValue);
    function valueOutAfterBuy(IERC20 _tokenOut, uint _valueAfterSell, int priorDeltaOut, int postDeltaOut) external view returns(uint buyValue);

}