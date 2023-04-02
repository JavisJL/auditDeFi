// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;

import "./SafeMath.sol";
import "./SignedSafeMath.sol";


library Lib { // deployed at: 0x92EB22eb4f4dFE719a988F328cE88ce36DD5279A

    using SafeMath for uint;
    using SignedSafeMath for int;

    // Contastants 
    uint public constant PRICE_DEN = 1e18;

    // -----   PancakeSwap ----------- //

    
    function pathGenerator2(address coinIn, address coinOut) internal pure returns(address[] memory) {
        address[] memory path = new address[](2);
        path[0] = address(coinIn);
        path[1] = address(coinOut);
        return path;
    }


    function pathGenerator3(address _coinIn, address _interRoute1, address _coinOut) internal pure returns(address[] memory) {
        address[] memory path = new address[](3);
        path[0] = address(_coinIn);
        path[1] = address(_interRoute1);
        path[2] = address(_coinOut);
        return path;
    }


    function getValue(uint256 _amount, uint256 _price) internal pure returns(uint256) {
        return _amount.mul(_price).div(PRICE_DEN);
    }


    function getAssetAmt(uint256 _usdAmount, uint256 _price) internal pure returns(uint256) {
        return _usdAmount.mul(PRICE_DEN).div(_price);
    }


    // -------- UTILITY FUNCTIONS ------------- //

    function min(uint256 a, uint256 b) internal pure returns(uint256) {
        return b >= a ? a : b;
    }


    /**
     * Returns cummulative sum of all values in array
     */
    function countValueArray(uint[] memory _array) internal pure returns(uint) {
        uint sum;
        for(uint i=0; i<_array.length; i++) { 
            sum = sum.add(_array[i]);
        }
        return sum;
    }


}