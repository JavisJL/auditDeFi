// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

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


    // ----------- Aded Functionality

    function underlying() external view returns(address);


}