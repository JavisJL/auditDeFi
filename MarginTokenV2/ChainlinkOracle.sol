// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.5.16;


import "./IERC20.sol";
import "./SafeMath.sol";
import "./AggregatorV2V3Interface.sol";
import "./ICompTT.sol";



contract PriceOracle {

    using SafeMath for uint;
    
    // addresses and stale period
    ICompTT public compTT;
    address public admin;
    address public wbnb;
    uint public maxStalePeriod;
    uint public MAX_STALE_PERIOD_LIMIT = 86400; // 24hrs
    bool public allowedSetOracleFeeds; // grants permission for admin to set feeds
    bool public allowedChangeOracleFeeds; // grants permission for admin to change feeds (rare)

    // store chainlink price feeds
    mapping(address => AggregatorV2V3Interface) internal feeds;


    // Events 
    event NewAdmin(address oldAdmin, address newAdmin);
    event FeedSet(address feed, address underlying);
    event MaxStalePeriodUpdated(uint oldMaxStalePeriod, uint newMaxStalePeriod);
    event SetPermissionSetOracleFeeds(bool oldStatus, bool newStatus);
    event SetPermissionChangeOracleFeeds(bool oldStatus, bool newStatus);


    constructor(ICompTT _compTT, uint maxStalePeriod_) public {
        compTT = _compTT;
        maxStalePeriodLimit(maxStalePeriod_);
        admin = msg.sender;
        maxStalePeriod = maxStalePeriod_;
        wbnb = compTT.wbnb();
    }


    modifier onlyAdmin() {
      require(msg.sender == admin, "only admin may call");
      _;
    }

    modifier onlyCompAdmin() {
      require(msg.sender == compTT.admin(), "only Comp admin may call");
      _;
    }

    function ensureNonzeroAddress(address someone) private pure {
        require(someone != address(0), "can't be zero address");
    }

    /**
     * @notice Sets a limit (in seconds) since last price update to be valid
     */
    function maxStalePeriodLimit(uint _maxStalePeriod) private view {
        require(_maxStalePeriod <= MAX_STALE_PERIOD_LIMIT,"maxStalePeriod 24hr");
    }

    /**
     * @notice Returns the admin address for CompTT
     */
    function returnCompAdmin() external view returns(address) {
        return compTT.admin();
    }


    // ------- SET VALUES --------- //


    /**
      * @notice Allows CompTT admin to grant permission to Chainlink Oracle admin to set price feeds
      * @dev CompTT admin is the most secure keys and may be governed by XTT token
      * @param _allowedSetOracleFeeds True if gives permission to Oracle admin to set price feeds
      * @return true if successful, otherwise error message from require statements
      */
    function _setPermissionSetOracleFeeds(bool _allowedSetOracleFeeds) external onlyCompAdmin() returns(bool) {

        // Track the old oracle for the comptroller
        bool oldAllowedSetOracleFeeds = _allowedSetOracleFeeds;

        // Set comptroller's oracle to newOracle
        allowedSetOracleFeeds = _allowedSetOracleFeeds;

        // Emit NewPriceOracle(oldOracle, newOracle)
        emit SetPermissionSetOracleFeeds(oldAllowedSetOracleFeeds, allowedSetOracleFeeds);

        return true;

    }

    /**
      * @notice Allows CompTT admin to grant permission to Chainlink Oracle admin to change price feeds
      * @dev CompTT admin is the most secure keys and may be governed by XTT token
      * @param _allowedChangeOracleFeeds True if gives permission to Oracle admin to set price feeds
      * @return true if successful, otherwise error message from require statements
      */
    function _setPermissionChangeOracleFeeds(bool _allowedChangeOracleFeeds) external onlyCompAdmin() returns(bool) {

        // Track the old oracle for the comptroller
        bool oldAllowedChangeOracleFeeds = _allowedChangeOracleFeeds;

        // Set comptroller's oracle to newOracle
        allowedChangeOracleFeeds = _allowedChangeOracleFeeds;

        // Emit NewPriceOracle(oldOracle, newOracle)
        emit SetPermissionChangeOracleFeeds(oldAllowedChangeOracleFeeds, allowedChangeOracleFeeds);

        return true;

    }

    /**
     * @notice Determines if Oracle feeds is allowed to be updated
     * @dev Permission for changing and setting feeds are seperate
     * @dev Changing feed is a higher risk operation as Trend Tokens may have active positions
     */
    function permissionAdjustOracleFeeds(address underlying) internal view returns(bool) {
        // ensures feed is allowed to be changed
        if (address(feeds[underlying]) != address(0)) {
            if (allowedChangeOracleFeeds) {
                return true;
            } else {
                return false;
            }
        } else { // ensures oracle is allowed to be added
            if (allowedSetOracleFeeds) {
                return true;
            } else {
                return false;
            }
        }
    }


    /**
     * @notice Allows admin to set a new max stale period
     */
    function _updateMaxStalePeriod(uint _maxStalePeriod) external onlyAdmin() {
        maxStalePeriodLimit(_maxStalePeriod);
        uint oldStalePeriod = maxStalePeriod;
        maxStalePeriod = _maxStalePeriod;
        emit MaxStalePeriodUpdated(oldStalePeriod, maxStalePeriod);
    }

    /**
     * @notice Allows admin to set a new admin address
     */
    function _setAdmin(address newAdmin) external onlyAdmin() {
        ensureNonzeroAddress(newAdmin);
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
        require(permissionAdjustOracleFeeds(underlying),"admin must have permission to set or change feeds");
        require(feed != address(0) && feed != address(this), "invalid feed address");
        require(underlying != address(0) && underlying != address(this), "invalid underlying address");
        require(IERC20(underlying).decimals() == uint8(18),"underlying must be 18 decimals.");
        emit FeedSet(feed, underlying);
        feeds[underlying] = AggregatorV2V3Interface(feed);
        allowedSetOracleFeeds = false;
        allowedChangeOracleFeeds = false;
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
