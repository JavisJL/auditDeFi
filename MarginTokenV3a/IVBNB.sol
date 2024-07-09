// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;


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


}


