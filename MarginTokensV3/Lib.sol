// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

library Lib {


    // Contastants 
    uint public constant PRICE_DEN = 1e18;

    // -----   PancakeSwap ----------- //

    
    function pathGenerator2(address coinIn, address coinOut) internal pure returns(address[] memory) {
        address[] memory path = new address[](2);
        path[0] = address(coinIn);
        path[1] = address(coinOut);
        return path;
    }


    function getValue(uint256 _amount, uint256 _price) internal pure returns(uint256) {
        return _amount * _price / PRICE_DEN;
    }


    function getAssetAmt(uint256 _usdAmount, uint256 _price) internal pure returns(uint256) {
        return _usdAmount * PRICE_DEN / _price;
    }


    /**
     * @notice Checks if targetAddr is in listAddrs
     * @return True if targetAddr is in listAddr, else False
     */
    function addressInList(address targetAddr, address[] memory listAddrs) internal pure returns(bool) {
        for (uint i=0; i<listAddrs.length; i++) {
            address listAddr = listAddrs[i];
            if (targetAddr == listAddr) {
                return true;
            }
        }
        return false;
    }


}