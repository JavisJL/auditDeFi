// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.5.16;


import "./IERC20.sol";
import "./SafeMath.sol";
import "./AggregatorV2V3Interface.sol";


contract PriceOracle {

    using SafeMath for uint;
    
    // addresses and stale period
    address public admin;
    address public wbnb;
    uint public maxStalePeriod;
    
    // store chainlink price feeds
    mapping(address => AggregatorV2V3Interface) internal feeds;


    // Events 
    event NewAdmin(address oldAdmin, address newAdmin);
    event FeedSet(address feed, address underlying);
    event MaxStalePeriodUpdated(uint oldMaxStalePeriod, uint newMaxStalePeriod);


    constructor(uint maxStalePeriod_, address _wbnb) public {
        admin = msg.sender;
        maxStalePeriod = maxStalePeriod_;
        wbnb = _wbnb;
    }


    modifier onlyAdmin() {
      require(msg.sender == admin, "only admin may call");
      _;
    }


    // ------- SET VALUES --------- //


    /**
     * @notice Allows admin to set a new max stale period
     */
    function _updateMaxStalePeriod(uint _maxStalePeriod) external onlyAdmin() {
        uint oldStalePeriod = maxStalePeriod;
        maxStalePeriod = _maxStalePeriod;
        emit MaxStalePeriodUpdated(oldStalePeriod, maxStalePeriod);
    }

    /**
     * @notice Allows admin to set a new admin address
     */
    function _setAdmin(address newAdmin) external onlyAdmin() {
        address oldAdmin = admin;
        admin = newAdmin;
        emit NewAdmin(oldAdmin, newAdmin);
    }


    /**
     * @notice Allows admin to set underlying price feed using chainlink price oracle
     * @dev Must be 18 decimals or Margin Token will mis-calculate USD values
     * @dev DOGE and one of TRX (on Venus) are the only main tokens not 18 decimals
     */
    function _setFeed(address underlying, address feed) external onlyAdmin() {
        require(feed != address(0) && feed != address(this), "invalid feed address");
        require(underlying != address(0) && underlying != address(this), "invalid underlying address");
        require(IERC20(underlying).decimals() == uint8(18),"underlying must be 18 decimals.");
        emit FeedSet(feed, underlying);
        feeds[underlying] = AggregatorV2V3Interface(feed);
    }


    // ------- GET VALUES --------- //
    

    /**
     * @notice Fetches stored chainlink price feed from underlying address
     * @dev Admin must have _setFeed(symbol, feed) first
     * @return Chainlink price feed
     */
    function getFeed(address underlying) public view returns (AggregatorV2V3Interface) {
        return feeds[underlying];
    }
    

    /**
     * @notice Fetches price from chainlink price feed
     * @return Feed's price
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
     * @notice Fetches price from underlying address using stored price feed
     * @return Underlying's price
     */
    function getPriceFromAddress(address underlying) external view returns (uint price) {
 
        AggregatorV2V3Interface feed = getFeed(underlying);
        price = getPriceFromFeed(feed);
        return price;

    }


}
