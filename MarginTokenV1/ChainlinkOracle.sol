// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.5.16;

// Copyright 2020 Venus Labs, Inc.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A 
// PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, 
// PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, 
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.



import "./IERC20.sol";
import "./SafeMath.sol";
import "./AggregatorV2V3Interface.sol";

/**
 *
 *** MODIFICATIONS ***
 * getUnderlyingPrice() removed VAI and XVS if-else statements
 *
 */



contract PriceOracle {

    // Storage
    using SafeMath for uint;
    uint public constant VAI_VALUE = 1e18;
    address public admin;
    address public wbnb;
    uint public maxStalePeriod;
    mapping(address => uint) internal prices;
    mapping(address => AggregatorV2V3Interface) internal feeds;


    // Events 
    event PricePosted(address asset, uint previousPriceMantissa, uint requestedPriceMantissa, uint newPriceMantissa);
    event NewAdmin(address oldAdmin, address newAdmin);
    event FeedSet(address feed, address underlying);
    event MaxStalePeriodUpdated(uint oldMaxStalePeriod, uint newMaxStalePeriod);


    /**
     * !testnet: 1000000000000000000,0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd
     */
    constructor(uint maxStalePeriod_, address _wbnb) public {
        admin = msg.sender;
        maxStalePeriod = maxStalePeriod_;
        wbnb = _wbnb;
    }

    // Modifier 
    modifier onlyAdmin() {
      require(msg.sender == admin, "only admin may call");
      _;
    }



    // ------- SET VALUES --------- //

    function _setAdmin(address newAdmin) external onlyAdmin() {
        address oldAdmin = admin;
        admin = newAdmin;
        emit NewAdmin(oldAdmin, newAdmin);
    }

    /**
     * !testnet: 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526
     */
    function _setFeed(address underlying, address feed) external onlyAdmin() {
        require(feed != address(0) && feed != address(this), "invalid feed address");
        require(underlying != address(0) && underlying != address(this), "invalid underlying address");
        emit FeedSet(feed, underlying);
        feeds[underlying] = AggregatorV2V3Interface(feed);
    }



    // ------- GET VALUES --------- //
    
    /**
     * @notice Fetches stored chainlink price feed from symbol
     * @dev Admin must have _setFeed(symbol, feed) first
     */
    function getFeed(address underlying) public view returns (AggregatorV2V3Interface) {
        return feeds[underlying];
    }

    /**
     * @notice Allows any address to get price from Chainlink price feed address
     */
    function getPriceFromFeed(AggregatorV2V3Interface feed) public view returns (uint) {
        
        // Chainlink USD-denominated feeds store answers at 8 decimals
        uint decimalDelta = uint(18).sub(feed.decimals());

        (, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();
        
        // Returns zero if maxStalePeriod exceeded
        if (block.timestamp.sub(updatedAt) > maxStalePeriod) {
            return 0;
        }

        // Adjust to 18 decimals
        if (decimalDelta > 0) {
            return uint(answer).mul(10**decimalDelta);
        } else {
            return uint(answer);
        }
    }


    /**
     * @notice Allows any address to get price from token symbol
     */
    function getPriceFromAddress(address underlying) external view returns (uint price) {
 
        AggregatorV2V3Interface feed = getFeed(underlying);
        price = getPriceFromFeed(feed);
        return price;

    }





}
