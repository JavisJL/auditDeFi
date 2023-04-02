// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;


import "./ICompTT.sol";
import "./IChainlinkOracle.sol";
import "./CompStorageTT.sol";
import "./UniTT.sol";


contract CompTT is ComptrollerStorage {//}, ComptrollerErrorReporter, ExponentialNoError {
    /// @notice Emitted when an admin supports a market
    event TrendTokenListed(ITrendToken trendToken);

    /// @notice Emitted when price oracle is changed
    event NewPriceOracle(IOracle oldPriceOracle, IOracle newPriceOracle);

    /// @notice Emitted when pause guardian is changed
    event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);

    /// @notice Emitted when an action is paused globally
    event ActionPaused(string action, bool pauseState);

    /// @notice Emitted when protocol state is changed by admin
    event ActionProtocolPaused(bool state);

    /// @notice Emitted when protocol state is changed by admin
    event ActionMintPaused(address trendToken, bool state);

    /// @notice Emitted when token is supported by admin
    event SupportToken(address underlying, address iToken);


    constructor() public {
        admin = msg.sender;
    }

    // -------- MODIFIERS AND CHECKS ------------ // 


    modifier onlyProtocolAllowed {
        require(!protocolPaused, "protocol is paused");
        _;
    }


    function ensureAdmin() private view {
        require(msg.sender == admin, "!admin");
    }


    function ensureNonzeroAddress(address someone) private pure {
        require(someone != address(0), "can't be zero address");
    }


    modifier onlyListedTrendTokens(ITrendToken trendToken) {
        require(trendTokens[address(trendToken)].isListed, "venus market is not listed");
        _;
    }


    /**
     * @notice Must return True for protcol to be puased
     */
    modifier validPauseState(bool state) {
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can");
        require(msg.sender == admin || state, "only admin can unpause");
        _;
    }


    /**
     * @notice Checks caller is admin, or this contract is becoming the new implementation
     */
    function adminOrInitializing() internal view returns (bool) {
        return msg.sender == admin || msg.sender == comptrollerImplementation;
    }


    /** CHANGE: SUPPLY ALLOWED
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param trendToken The market to verify the mint against
     * param minter The account which would get the minted tokens
     * param mintAmount The amount of underlying being supplied to the market in exchange for tokens
     * @return 0 if the mint is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function depositOrRedeemAllowed(address trendToken, uint amount) external view onlyProtocolAllowed returns (bool) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(amount>0,"amount must be greater than 0");
        require(!mintGuardianPaused[trendToken], "mint is paused");
        require(trendTokens[trendToken].isListed, "trend token not listed");
        require(trendTokens[trendToken].isActive, "trend token not active");
        return true; 
    }


    /** 
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param trendToken The market to verify the mint against
     * param minter The account which would get the minted tokens
     * param mintAmount The amount of underlying being supplied to the market in exchange for tokens
     * @return 0 if the mint is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function tradeAllowed(address trendToken, uint amount) external view onlyProtocolAllowed returns (bool) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(amount>0,"amount must be greater than 0");
        require(!mintGuardianPaused[trendToken], "mint is paused");
        require(trendTokens[trendToken].isListed, "trend token not listed");
        require(trendTokens[trendToken].isActive, "trend token not active");
        require(trendTokens[trendToken].isTrade, "trend token not tradeable");
        return true; 
    }


    // ---------- EXTERNAL VIEW FUNCTIONS ----------- // 


    /**
     * @notice Return all of the markets (trend tokens)
     * @dev The automatic getter may be used to access an individual market.
     * @return The list of market addresses
     */
    function getAllTrendTokens() external view returns (ITrendToken[] memory) {
        return allTrendTokens;
    }

    
    /**
     * @notice Returns current block number
     */
    function getBlockNumber() external view returns (uint) {
        return block.number;
    }


    /**
     * @notice Return the address of the XVS token
     * @return The address of XVS
     */
    function getXVSAddress() external pure returns (address) {
        return 0xf79c28eB5bd0cC10B58F04DfF7c34d0c8D39BdE6; //0xcF6BB5389c92Bdda8a3747Ddb454cB7a64626C63;
    }


    /**
     * @notice Allows a Trend Token to enable a token (add to portfolio)
     * @return Returns zero address if 
     */
    function returnDToken(address underlying) external view onlyProtocolAllowed returns(address) {
        return tokenToDToken[underlying];
    }


    /**
     * @notice Returns Trend Token list status
     */
    function trendTokenIsListed(address trendToken) external view returns(bool) {
        return trendTokens[address(trendToken)].isListed;
    }


    /**
     * @notice Returns Trend Token active status
     */
    function trendTokenIsActive(address trendToken) external view returns(bool) {
        return trendTokens[address(trendToken)].isActive;
    }


    /**
     * @notice Returns Trend Token active status
     */
    function trendTokenIsTrade(address trendToken) external view returns(bool) {
        return trendTokens[address(trendToken)].isTrade;
    }



    /**
     * @notice Returns whether or not the Trend Token is allowed to supply on Dual Pools
     */
    function trendTokenAllowedDualPools(address trendToken) external view returns(bool) {
        return trendTokens[address(trendToken)].allowedDualPools;
    }


    /**
     * @notice Returns the maximum trade fee for the Trend Token
     */
    function trendTokenMaxTradeFee(address trendToken) external view returns(uint) {
        return trendTokens[address(trendToken)].maxTradeFee;
    }


    /**
     * @notice Returns the maximum performance fee for the Trend Token
     */
    function trendTokenMaxPerformanceFee(address trendToken) external view returns(uint) {
        return trendTokens[address(trendToken)].maxPerformanceFee;
    }


    /**
     * @notice Returns the maximum vlaue in a token for it to be disabled
     */
    function trendTokenMaxDisableValue(address trendToken) external view returns(uint) {
        return trendTokens[address(trendToken)].maxDisableValue;
    }


    // ------------- PROTOCOL WIDE (all trend tokens) FUNCTIONS --------------- // 


    /**
     * @notice Sets this contract to become Unicontroller
     */
    function _become(Unitroller unitroller) external {
        require(msg.sender == unitroller.admin(), "only unitroller admin can");
        require(unitroller._acceptImplementation() == 0, "not authorized");
    }


    /**
     * @notice Set whole protocol pause/unpause state
     */
    function _setProtocolPaused(bool state) external validPauseState(state) returns(bool) {
        protocolPaused = state;
        emit ActionProtocolPaused(state);
        return state;
    }

    /**
     * @notice Set depsoit, redeem, and trade to paused
     */
    function _setMintPaused(address _trendToken, bool state) external validPauseState(state) returns(bool) {
        mintGuardianPaused[_trendToken] = state;
        emit ActionMintPaused(_trendToken, state);
        return state;
    }


    /**
      * @notice Sets a new price oracle for the comptroller
      * @dev Admin function to set a new price oracle
      * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
      */
    function _setPriceOracle(IOracle newOracle) external returns (bool) {
        // Check caller is admin
        ensureAdmin();

        ensureNonzeroAddress(address(newOracle));

        // Track the old oracle for the comptroller
        IOracle oldOracle = oracle;

        // Set comptroller's oracle to newOracle
        oracle = newOracle;

        // Emit NewPriceOracle(oldOracle, newOracle)
        emit NewPriceOracle(oldOracle, newOracle);

        return true;
    }


    /**
     * @notice Admin function to change the Pause Guardian
     * @param newPauseGuardian The address of the new Pause Guardian
     * @return uint 0=success, otherwise a failure. (See enum Error for details)
     */
    function _setPauseGuardian(address newPauseGuardian) external returns (bool) {
        ensureAdmin();

        ensureNonzeroAddress(newPauseGuardian);

        // Save current value for inclusion in log
        address oldPauseGuardian = pauseGuardian;

        // Store pauseGuardian with value newPauseGuardian
        pauseGuardian = newPauseGuardian;

        // Emit NewPauseGuardian(OldPauseGuardian, NewPauseGuardian)
        emit NewPauseGuardian(oldPauseGuardian, newPauseGuardian);

        return true;
    }


    /**
     * @notice Internal function to support token (for example, BTCB)
     * @param underlying The address of underlying asset (BTCB)
     * @param dToken The dToken address of underlying asset (dBTCB)
     */
    function supportTokenFresh(address underlying, address dToken) internal returns(uint) {
        ensureAdmin();
        require(oracle.getUnderlyingPrice(dToken) != 0,"no price in Oracle");
        tokenToDToken[underlying] = dToken;
        supportedTokens.push(underlying);

    }


    /**
     * Allows admin to support tokens so Trend Tokens can use them
     * This requires a price from the Chainlink Oracle
     * underlying and iToken are added to the mappings
     */
    function _supportToken(address underlying, address dToken) external returns(uint) {
        supportTokenFresh(underlying, dToken);
        emit SupportToken(underlying, dToken);
    }


    // --------- SUPPORT TREND TOKEN AND UPDATE PARAMETERS -------------- // 


    /**
     * @notice Internal function to check Trend Token isnt already added and verify it is a trend token
     * @param trendToken The trend token desired to be supported by Comptroller Trend Token 
     */
    function _supportTrendTokenFresh(ITrendToken trendToken) internal {
        for (uint i = 0; i < allTrendTokens.length; i ++) {
            require(allTrendTokens[i] != trendToken, "Trend Token already added");
        }
        require(trendToken.isTrendToken(),"not a trend token");
        allTrendTokens.push(trendToken);
    }


    /**
      * @notice Add the Trend Token to the Trend Token mapping and set initial conditions
      * @dev Admin function to set isListed and add support for the market
      * @param trendToken The address of the Trend Token to list
      * @return uint 0=success, otherwise a failure. (See enum Error for details)
      */
    function _supportTrendToken(ITrendToken trendToken) external returns (bool) {
        ensureAdmin();
        require(!trendTokens[address(trendToken)].isListed,"trend token already listed");

        trendToken.isTrendToken(); // Sanity check to make sure its really a Trend Token

        // Note that isVenus is not in active use anymore
        trendTokens[address(trendToken)] = TrendToken({isListed: true, isActive: true, isTrade: true, allowedDualPools: true, 
                                                       maxTradeFee: 0.05e18, maxPerformanceFee: 0.50e18, maxDisableValue: 10000e18 });

        _supportTrendTokenFresh(trendToken);

        emit TrendTokenListed(trendToken);

        return true;
    }


    /**
     * @notice Allows admin to change Trend Token active state
     * @dev False sets Trend Token to paused (cannot deposit, redeem, or public rebalance)
     */
    function _newIsActive(address trendToken, bool _isActive) external {
        ensureAdmin();
        trendTokens[trendToken].isActive = _isActive;
    } 

    /**
     * @notice Allows admin to change Trend Token trade state
     * @dev False halts trading activity of underlying <--> underlying
     */
    function _newIsTrade(address trendToken, bool _isTrade) external {
        ensureAdmin();
        trendTokens[trendToken].isTrade = _isTrade;
    } 


    /**
     * @notice Allows admin to change allowedDualPools status
     * @dev Allows Trend Token supply assets to Dual Pools
     */
    function _newAllowedDualPools(address trendToken, bool _allowedDualPools) external {
        ensureAdmin();
        trendTokens[trendToken].allowedDualPools = _allowedDualPools;
    } 


    /**
     * @notice Allows admin to change maxTradeFee
     * @dev Trade Fee is charged when users deposit or redeem trend tokens
     */
    function _newMaxTradeFee(address trendToken, uint _maxTradeFee) external {
        ensureAdmin();
        require(_maxTradeFee <= 0.25e18,"max trade fee exceeded upper limit");
        trendTokens[trendToken].maxTradeFee = _maxTradeFee;
    } 


    /**
     * @notice Allows admin to change maxTradeFee
     * @dev Trade Fee is charged when users deposit or redeem trend tokens
     */
    function _newMaxPerformanceFee(address trendToken, uint _maxPerformanceFee) external {
        ensureAdmin();
        require(_maxPerformanceFee <= 1e18,"max performance fee exceeded upper limit");
        trendTokens[trendToken].maxPerformanceFee = _maxPerformanceFee;
    } 


    /**
     * @notice Allows admin to change maxTradeFee
     * @dev Trade Fee is charged when users deposit or redeem trend tokens
     */
    function _newMaxDisableValue(address trendToken, uint _maxDisableValue) external {
        ensureAdmin();
        require(_maxDisableValue <= 1e18,"max performance fee exceeded upper limit");
        trendTokens[trendToken].maxDisableValue = _maxDisableValue;
    } 


}

