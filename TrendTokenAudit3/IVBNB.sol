// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;


interface IVBNB {
    function balanceOf(address _owner) external view returns(uint256);
    function balanceOfUnderlying(address _owner) external returns(uint256);
    function mint() external payable; // different for IVBep20
    function repayBorrow() external payable;
    function redeemUnderlying(uint256 _amount) external returns(uint256);
    function exchangeRateStored() external view returns(uint256);
    function borrowBalanceCurrent(address account) external returns (uint);
    function borrow(uint256 _amount) external returns(uint256);
    function getAccountSnapshot(address account) external view returns (uint, uint, uint, uint);
    function borrowBalanceStored(address account) external view returns (uint);
    function totalBorrowsCurrent() external returns (uint);

    /*** Trading Functionality ***/
    //function swapExactTokenForBNB(address _iTokenIn, uint _amountTokenIn, uint _minOut, uint _deadline) external;
    function swapExactETHForTokens(uint _minOut, address[] calldata dTokenOut_referrer, address payable _sendTo, uint _deadline) external payable;
}


