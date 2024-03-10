// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;

interface IVBep20 {

    function balanceOf(address _user) external view returns(uint256);
    function balanceOfUnderlying(address account) external returns (uint);

    function mint(uint mintAmount) external returns (uint); // Different for IVBNB
    function repayBorrow(uint256 _amount) external returns(uint256); // Different for IVBNB

    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function exchangeRateStored() external view returns(uint256);
    function borrowBalanceCurrent(address _owner) external returns(uint256);
    function borrow(uint256 _amount) external returns(uint256);

    function getCash() external view returns (uint);

    // @return 
    function getAccountSnapshot(address account) external view returns (uint, uint, uint, uint);
    function borrowBalanceStored(address account) external view returns (uint);
    function totalBorrowsCurrent() external returns (uint);

    function accrueInterest() external returns (uint);

    /*** Trading Functionality ***/
    
    //function amountsOut(address _dTokenIn, address _dTokenOut, uint _amountIn, address _trader, address _referrer) external view returns(uint amountOut, uint reserveFeeUnderly, uint totalFeeAndSlip);
    //function swapExactTokensForTokens(uint256 _amountTokenIn, uint256 _minOut, address[] calldata dTokenOut_referrer, address payable _sendTo, uint256 _deadline) external;

    // ----------- Aded Functionality

    function underlying() external view returns(address);


}