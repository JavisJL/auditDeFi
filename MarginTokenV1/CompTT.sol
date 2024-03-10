// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;

import "./IERC20.sol";
import "./ICompTT.sol";
import "./IChainlinkOracle.sol";
import "./CompStorageTT.sol";
import "./UniTT.sol";
import "./SafeMath.sol";
import "./SignedSafeMath.sol";


// ------- CONFIGURE COMPTROLLER --------- //
// _updateLocked(): false
// _setPriceOracle(): 0xF4365dE16CDA0756Bb9b5886B4734B71De6F3353
// _setVenusComp(): 0x94d1820b2D1c7c7452A163983Dc888CEC546b77D
// _setBNB(): 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x2E7222e51c0f6e98610A1543Aa3836E092CDe62c
// _supportUnderlying(): 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd
//                       0xA808e341e8e723DC6BA0Bb5204Bafc2330d7B8e4


// --------- DEPLOY AND CONFIGURE TREND TOKEN --------- //
// Deploy /MarginTokens.sol
// _supportTrendToken(): address from step above
// do some tests (update portfolio, deposit, redeemTT, trade)


// ---------- SUPPORT VENUS ACTIONS (supply only) ---------- //
// _supportVToken():     0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x2E7222e51c0f6e98610A1543Aa3836E092CDe62c
//                       0xA808e341e8e723DC6BA0Bb5204Bafc2330d7B8e4,0xb6e9322C49FD75a367Fcb17B0Fcd62C5070EbCBe
// default: _updateUnderlyingForVenusAction(): 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,true,true,false
// default: _updateTrendTokenVenusActions(): 0x0000000000000000000000000000000000000000,true,false
// go to Margin Token and supply, make sure to set desired direction check





// 1. Set max leverage and some other key factors (instead of in Trend Token code)
//      Then call comptroller (with some values) for permission for user to borrow or redeem! 
//      Code handled here is safer and lighter on Trend Token bytes 
//      Maybe also check priceDiscrpancy between Venus and Oracle for any Venus interaction (gas but who cares)



// Questions: should redeems ever be disabled?
// Questions: should vToken address for underlying be updated

// 1. Support underlying (make sure it has a price)
// 2. Support vToken support for underlying token

contract CompTT is ComptrollerStorage {//}, ComptrollerErrorReporter, ExponentialNoError {

    using SignedSafeMath for int;
    using SafeMath for uint;

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

    /// @notice Emitted when locked state changes
    event Locked(bool oldState, bool newState);

    /// @notice Emitted when lockedWallet address is updated
    event UpdateLockedWallet(address oldWallet, address lockedWallet);

    //// @notice Emitted when compVenus address is updated
    event NewCompVenus(address oldCompVenus, address compVenus);

    //// @notice Emmited when wBNB and vBNB addresses are set
    event NewSetBNB(address oldBNB, address oldVBNB, address newBNB, address newVBNB);



    constructor() public {
        admin = msg.sender;
        lockedWallet = msg.sender;
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


    modifier onlySupportedTrendTokens(address trendToken) {
        require(trendTokenSupported(ITrendToken(trendToken)), "Trend Token is not supported");
        _;
    }

    modifier onlySupportedUnderlyins(address underlying) {
        require(isUnderlyingSupported(underlying), "Underlying is not supported");
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
     * @notice Prevents Manager from executing highly secure operations
     */
    modifier requireUnlocked() {
        require(!locked,"!locked");
        _;
    }


    // ---------- EXTERNAL VIEW FUNCTIONS (LENS) ----------- // 

    /**
     * @notice Returns current block number
     */
    function getBlockNumber() external view returns (uint) {
        return block.number;
    }


    /**
     * @notice Return the address of the XVS token
     * @return The address of XVS
     * testnet: 0xB9e0E753630434d7863528cc73CB7AC638a7c8ff
     * mainnet: 0xcF6BB5389c92Bdda8a3747Ddb454cB7a64626C63
     */
    function getXVSAddress() external pure returns (address) {
        return 0xB9e0E753630434d7863528cc73CB7AC638a7c8ff;
    }



    // ------------- PROTOCOL WIDE (all trend tokens) FUNCTIONS --------------- // 


    /**
     * @notice Sets this contract to become Unicontroller
     */
    function _become(Unitroller unitroller) external requireUnlocked {
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
     * @notice Allows trading bot to change state of locked
     * @dev if locked is true, manager actions are limited (higher security) 
     *      as a result, some actions require permission of both
     */
    function _updateLockedState(bool _state) external {
        require(msg.sender == lockedWallet,"not lockedWallet");
        bool oldState = locked;
        locked = _state;
        emit Locked(oldState, locked);
    }


    /**
     * @notice Allows LockedWallet to change address
     */
    function _updateLockedWallet(address _newWallet) external {
        require(msg.sender == lockedWallet, "not lockedWallet");
        require(_newWallet != address(0),"locked wallet cannot be zero address");
        address oldWallet = lockedWallet;
        lockedWallet = _newWallet;
        emit UpdateLockedWallet(oldWallet, lockedWallet);

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
    function _setPriceOracle(IOracle newOracle) external requireUnlocked returns (bool) {
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


    function _setVenusComptroller(ICompVenus _compVenus) external requireUnlocked returns(bool) {

        ensureAdmin();

        ensureNonzeroAddress(address(_compVenus));

        // Track the old oracle for the comptroller
        ICompVenus oldCompVenus = compVenus;

        // Set comptroller's compVenus to newCompVenus
        compVenus = _compVenus;

        // Emit NewCompVenus(oldCompVenus, compVenus);
        emit NewCompVenus(address(oldCompVenus), address(compVenus));

        return true;

    }


    function _setBNB(address _wbnb, address _vbnb) external returns(bool) {
        // Check caller is admin
        ensureAdmin();
        require(address(wbnb) == address(0),"wbnb already set.");

        // track old BNB and vBNB
        address oldBNB = address(wbnb);
        address oldVBNB = address(vbnb);

        // set new values
        wbnb = IERC20(_wbnb);
        vbnb = IVBNB(_vbnb);

        emit NewSetBNB(oldBNB, oldVBNB, address(wbnb), address(vbnb));

        return true;
    }


    /**
     * @notice Admin function to change the Pause Guardian
     * @param newPauseGuardian The address of the new Pause Guardian
     * @return uint 0=success, otherwise a failure. (See enum Error for details)
     */
    function _setPauseGuardian(address newPauseGuardian) external requireUnlocked returns (bool) {
        ensureAdmin();
        require(newPauseGuardian != address(0),"newPauseGuardian cannot be zero address");

        ensureNonzeroAddress(newPauseGuardian);

        // Save current value for inclusion in log
        address oldPauseGuardian = pauseGuardian;

        // Store pauseGuardian with value newPauseGuardian
        pauseGuardian = newPauseGuardian;

        // Emit NewPauseGuardian(OldPauseGuardian, NewPauseGuardian)
        emit NewPauseGuardian(oldPauseGuardian, newPauseGuardian);

        return true;
    }


    // ------------------------- TREND TOKENS SUPPORT ---------------------- // 


    /**
     * @notice Returns true if Trend Token is already supported
     * @dev Is supported if added to allTrendTokens from _supportTrendToken()
     */
    function trendTokenSupported(ITrendToken trendToken) internal view returns(bool) {
        for (uint i = 0; i < allTrendTokens.length; i ++) {
            if (allTrendTokens[i] == trendToken) {
                return true;
            }
        }
        return false;
    }


    /**
      * @notice Add the Trend Token to the Trend Token mapping and set initial conditions
      * @dev Admin function to set isListed and add support for the market
      * @param trendToken The address of the Trend Token to list
      * @return uint 0=success, otherwise a failure. (See enum Error for details)
      */
    function _supportTrendToken(ITrendToken trendToken) external requireUnlocked returns (bool) {
        
        ensureAdmin();

        // make sure trendToken is a trend token
        require(trendToken.isTrendToken(),"not a trend token"); // sanity check

        // Trend Token cannot already be supported
        bool isSupported = trendTokenSupported(trendToken);
        require(!isSupported,"trendToken is already supported.");

        // Set default values for newly supported Trend Token
        trendTokens[address(trendToken)] = TrendToken({ isLocked: false, // default false for flexibility
                                                        isActive: true, // trend token is active
                                                        isDeposit: true, // users may deposit to Trend Token
                                                        isRedeem: true, // users may redeem from Trend Token
                                                        isTrade: true, // users may swap one underlying for another
                                                        maxTradeFee: 0.05e18, // max trade fee of 5%
                                                        maxPerformanceFee: 0.50e18, // max performance fee of 50% (extreme case)
                                                        maxDisableValue: 100e18, // token may be removed from portfolio with balances max $100
                                                        isSupplyVenus: true, // trend token cannot supply to venus
                                                        isBorrowVenus: false, // trend token cannot borrow from venus
                                                        maxBorrowFactor: 0e18, // trend token may borrow maximum 0% of borrowable   
                                                        maxMargin: 0e18}); // trend token cannot apply margin

        allTrendTokens.push(trendToken);

        emit TrendTokenListed(trendToken);

        return true;
    }


    // --------------- Trend Token Update ------------------ // 

    /**
     * @notice Allows admin to change Trend Token locked state
     * @dev Unlocked allows manager of Trend Token to make key changes
     */
    function _updateTrendTokenLocked(address trendToken, bool _isLocked) external requireUnlocked onlySupportedTrendTokens(trendToken) {
        ensureAdmin();
        trendTokens[trendToken].isLocked = _isLocked;
    } 


    /**
     * @notice Allows admin to change Trend Token active state
     * @dev False sets Trend Token to paused (cannot deposit, redeem, or public rebalance)
     */
    function _updateTrendTokenActiveStatus(address trendToken, bool _isActive) external requireUnlocked onlySupportedTrendTokens(trendToken) {
        ensureAdmin();
        trendTokens[trendToken].isActive = _isActive;
    } 

    /**
     * @notice Allows admin to change Trend Token user interactions
     * @dev False halts trading activity of underlying <--> underlying and buying Trend Tokens
     */
    function _updateTrendTokenUserActions(address trendToken, bool _isDeposit, bool _isRedeem, bool _isTrade) external requireUnlocked onlySupportedTrendTokens(trendToken) {
        ensureAdmin();
        trendTokens[trendToken].isDeposit = _isDeposit;
         trendTokens[trendToken].isRedeem = _isRedeem;
        trendTokens[trendToken].isTrade = _isTrade;
    } 


    /**
     * @notice Allows admin to change the status of Trend Token interactions with Venus
     * @dev Allows trend token to supply and borrow
     */
    function _updateTrendTokenVenusActions(address trendToken, bool _isSupplyVenus, bool _isBorrowVenus) external requireUnlocked onlySupportedTrendTokens(trendToken) {
        ensureAdmin();
        trendTokens[trendToken].isSupplyVenus = _isSupplyVenus;
        trendTokens[trendToken].isBorrowVenus = _isBorrowVenus;
    } 


    /**
     * @notice Allows admin to change maximum deposit and performance fees for a Trend Token
     * @dev False halts trading activity of underlying <--> underlying and buying Trend Tokens
     */
    function _updateTrendTokenMaxFees(address trendToken, uint _maxTradeFee, uint _maxPerformanceFee) external requireUnlocked onlySupportedTrendTokens(trendToken) {
        ensureAdmin();
        require(_maxTradeFee <= 0.10e18 && _maxPerformanceFee <= 0.50e18,"fees are too high.");
        trendTokens[trendToken].maxTradeFee = _maxTradeFee;
        trendTokens[trendToken].maxPerformanceFee = _maxPerformanceFee;
    } 


    /**
     * @notice Allows admin to change maxTradeFee
     * @dev Trade Fee is charged when users deposit or redeem trend tokens
     */
    function _updateMaxDisableValue(address trendToken, uint _maxDisableValue) external requireUnlocked onlySupportedTrendTokens(trendToken) {
        ensureAdmin();
        require(_maxDisableValue <= 1e18,"max performance fee exceeded upper limit");
        trendTokens[trendToken].maxDisableValue = _maxDisableValue;
    } 


    /**
     * @notice Allows admin to change the status of Trend Token interactions with Venus
     * @dev Allows trend token to supply and borrow
     */
    function _updateTrendTokenBorrowLimit(address trendToken, uint _maxBorrowFactor, uint _maxMargin) external requireUnlocked onlySupportedTrendTokens(trendToken) {
        ensureAdmin();
        require(_maxBorrowFactor <= 0.90e18 && _maxMargin<= 3.0e18,"borrow limits too high.");
        trendTokens[trendToken].maxBorrowFactor = _maxBorrowFactor;
        trendTokens[trendToken].maxMargin = _maxMargin;
    } 


    // ----------------- Trend Token Display -------------------- // 


    /**
     * @notice Checks wether the underlying asset is allowed to be part of trendToken's portfolio
     * @dev Checks if underlying is in supportedTokens
     */
    function isSupportedTrendToken(ITrendToken trendToken) external view onlyProtocolAllowed returns(bool) {
        return trendTokenSupported(trendToken);
    }


    /**
     * @notice Checks wether the underlying asset is allowed to be part of trendToken's portfolio
     * @dev Checks if underlying is in supportedTokens
     */
    function isLockedTrendToken(ITrendToken trendToken) external view onlyProtocolAllowed returns(bool) {
        return trendTokens[address(trendToken)].isLocked;
    }


    /**
     * @notice Returns Trend Token active status
     */
    function trendTokenActiveStatus(address trendToken) external view returns(bool) {
        return trendTokens[address(trendToken)].isActive;
    }


    /**
     * @notice Checks if Trend Token is allowed to be used for trading
     * @dev Example BTCB --> ETH using portfolio
     * @return (isDeposit, isRedeem, isTrade)
     */
    function trendTokenUserActions(address trendToken) external view returns(bool,bool,bool) {
        return (trendTokens[trendToken].isDeposit,trendTokens[trendToken].isRedeem, trendTokens[trendToken].isTrade);
    }



    /**
     * @notice Returns whether or not the Trend Token is allowed to supply on Venus
     * @dev If true, any underlying that is supplyable may be supplied
     * @return isSupply, isBorrow
     */
    function trendTokenVenusActions(address trendToken) external view returns(bool, bool) {
        return (trendTokens[address(trendToken)].isSupplyVenus, trendTokens[address(trendToken)].isBorrowVenus);
    }


    /**
     * @notice Returns the maximum trade fee for the Trend Token
     */
    function trendTokenMaxFees(address trendToken) external view returns(uint,uint) {
        uint _maxTradeFee = trendTokens[address(trendToken)].maxTradeFee;
        uint _maxPerformanceFee = trendTokens[address(trendToken)].maxPerformanceFee;
        return (_maxTradeFee, _maxPerformanceFee);
    }


    /**
     * @notice Returns the maximum vlaue in a token for it to be disabled
     * @return maxDisableValue, maxBorrowFactor, maxMargin
     */
    function trendTokenMaxValues(address trendToken) external view returns(uint,uint,uint) {
        return (trendTokens[address(trendToken)].maxDisableValue,
                trendTokens[address(trendToken)].maxBorrowFactor,
                trendTokens[address(trendToken)].maxMargin);
        
    }


    // --------------------- UNDERLYING SUPPORT----------------------- // 

    /**
     * @notice Fetches the price of underlying from this oracle
     */
    function priceUnderlyingFresh(IERC20 _underlying) internal view returns(uint256) { 
        uint price = oracle.getPriceFromAddress(address(_underlying));
        require(price != 0, "price cannot be 0");
        return price;
    }


    /**
     * @notice Checks if underlying is already added to supportedUnderlying
     */
    function isUnderlyingSupported(address underlying) public view returns(bool) {
        for (uint i = 0; i < supportedUnderlying.length; i ++) {
            if (supportedUnderlying[i] == underlying) {
                return true;
            }
        }
        return false;
    }


    /**
     * @notice Allows admin to support an underlying token
     * @dev Does not require vToken support at this stage
     * @return True if successfully added, else False
     */
    function _supportUnderlying(address underlying) external returns(bool) {
        ensureAdmin();
        
        // require underlying has a price in oracle
        uint oraclePrice = oracle.getPriceFromAddress(underlying);
        require(oraclePrice != 0, "oraclePrice cannot be zero");

        // require token not already added
        bool alreadySupported = isUnderlyingSupported(underlying);
        require(!alreadySupported, "underlying cannot already be supported");

        // require 18 decimals
        require(IERC20(underlying).decimals() == uint8(18),"underlying must be 18 decimals.");

        // set default values for underlying
        underlyingInfo[underlying] = Underlying({   isActive: true, // underlying is active (may be added to Trend Tokens)
                                                    isDeposit: true, // users may deposit underlying from Trend Tokens
                                                    isRedeem: true, // users may redeem underlying from Trend Tokens
                                                    isTrade: true, // users may swap one underlying for another
                                                    vToken: address(0), // no vToken
                                                    isVenusActive: true, // underlying cannot supply, redeem, borrow, or repay to Venus
                                                    isSupplyVenus: true, // underlying cannot be supplied to Venus
                                                    isBorrowVenus: false}); // underlying cannot be borrowed from Venus
                                                    //maxPriceDifference: 0.0001e18}); // Oracle and Venus prices must 0.01% price difference

        // add to list of underlying
        supportedUnderlying.push(underlying);

        return true;
    }


    // --------------- UNDERLYING UPDATE ------------------ //

    /**
     * @notice Allows admin to change active status for underlying
     * @dev This includes all 'user-trendToken' and 'trendToken-Venus' interactions
     */
    function _updateUnderlyingActiveStatus(address underlying, bool _isActive) public requireUnlocked onlySupportedUnderlyins(underlying) {
        
        // Only admin may support a new vToken
        ensureAdmin();

        // Set new variables
        underlyingInfo[underlying].isActive = _isActive;

    }


    /** 
     * @notice Allows admin to change the settings for an underlying for User - Trend Token interactions
     */
    function _updateUnderlyingForUserActions(address underlying, bool _isDeposit, bool _isRedeem, bool _isTrade) public requireUnlocked onlySupportedUnderlyins(underlying)  {

        // Only admin may support a new vToken
        ensureAdmin();

        // Set new variables
        underlyingInfo[underlying].isDeposit = _isDeposit;
        underlyingInfo[underlying].isRedeem = _isRedeem;
        underlyingInfo[underlying].isTrade = _isTrade;
    }


    /** 
     * @notice Allows admin to support vToken for underlying which allows for 
     */
    function _supportVToken(address underlying, address _vToken) public requireUnlocked onlySupportedUnderlyins(underlying) {

        // only admin may support a new vToken
        ensureAdmin();

        // ensures vToken not already supported
        require(underlyingInfo[underlying].vToken == address(0), "vToken already supported.");

        // ensure vTokens underlying is same as underlying input
        if (underlying == address(wbnb)) {
            require(_vToken == address(vbnb), "underlying != vToken.underlying.");
        } else {
            address vTokenUnderlying = IVBep20(_vToken).underlying();
            require(underlying == vTokenUnderlying, "underlying != vToken.underlying.");
        }

        // makes sure vToken price and Oracle price are similar(or the same)
        //bool isWithinRange = pricesWithinRange(underlying, _vToken); 
        //require(isWithinRange,"!priceDiscrepancyMax.");

        // assigns _vToken to underlyingInfo
        underlyingInfo[underlying].vToken = _vToken;
    }


    /** 
     * @notice Allows admin to change the settings for an underlying for User - Trend Token interactions
     */
    function _updateUnderlyingForVenusActions(address underlying, bool _isVenusActive, bool _isSupplyVenus, bool _isBorrowVenus) public requireUnlocked onlySupportedUnderlyins(underlying) {

        // Only admin may support a new vToken
        ensureAdmin();

        // ensure a vToken
        require(underlyingInfo[underlying].vToken != address(0), "vToken must be supported.");

        // Set new variables
        underlyingInfo[underlying].isVenusActive = _isVenusActive;
        underlyingInfo[underlying].isSupplyVenus = _isSupplyVenus;
        underlyingInfo[underlying].isBorrowVenus = _isBorrowVenus;
    }


    /**
     * @notice Allows admin to update maxPriceDifference which is price difference between oracle and venusOracle for underlying
     * @dev Used when supporting a _supportVToken() or when Trend Token adds token to portfolio or interacts with Venus  
     
    function _updateUnderlyingMaxPriceDifference(address underlying, uint _maxPriceDifference) public requireUnlocked onlySupportedUnderlyins(underlying) {

        // Only admin may support a new vToken
        ensureAdmin();

        // require price difference isnt too large
        require(_maxPriceDifference < 0.02e18,"MaxPriceDifference cannot be more than 2%.");

        underlyingInfo[underlying].maxPriceDifference = _maxPriceDifference;

    }*/




    // ----------------- UNDERLYING EXTERNAL ------------------- //

        // ------------ User-TrendToken Interactions -------------- // 


    /**
     * @notice Fetch prices of tokens from Chainlink price oracle
     * @param _underlying The underlying assets to get price of
     */
    function priceBEP20(IERC20 _underlying) external view returns(uint256) { 
        return priceUnderlyingFresh(_underlying);
    }


    /**
     * @notice Checks wether the underlying asset is allowed to be part of trendToken's portfolio
     * @dev Checks if underlying is in supportedTokens
     */
    function underlyingSupported(address underlying) external view onlyProtocolAllowed returns(bool) {
        return isUnderlyingSupported(underlying);
    }

    /**
     * @notice Returns whether or not underlying is active
     * @dev Able to be added to portfolio
     */
    function underlyingActiveStatus(address underlying) external view onlyProtocolAllowed returns(bool) {
        return underlyingInfo[underlying].isActive;
    }

    /**
     * @notice Allows a Trend Token to enable a token (add to portfolio)
     * @return Returns zero address if vToken has not been supported for underlying
     */
    function returnVToken(address underlying) external view onlyProtocolAllowed returns(address) {
        return underlyingInfo[underlying].vToken;
    }



    /**
     * @notice Returns the actions users are allowed to take with underlying for all Trend Tokens
     * @return isDeposit, isRedeem, isTrade
     */
    function underlyingForUserActions(address underlying) external view onlyProtocolAllowed returns(bool,bool,bool) {
        return (underlyingInfo[underlying].isDeposit, underlyingInfo[underlying].isRedeem, underlyingInfo[underlying].isTrade);
    }


    /**
     * @notice Returns whether or not underlying is active on Venus and allowed to supply and borrow
     */
    function underlyingForVenusActions(address underlying) external view onlyProtocolAllowed returns(bool,bool,bool) {
        return (underlyingInfo[underlying].isVenusActive,underlyingInfo[underlying].isSupplyVenus,underlyingInfo[underlying].isBorrowVenus);
    }



    // --------- SUPPORT TREND TOKEN AND UPDATE PARAMETERS -------------- //





    // ------------------------ TREND TOKEN SAFETY LAYER ------------------------ // 
    // trend tokens call these functions to get permission for actions
    // buy, sell, or swap. supply, borrow, redeem, repay


    // ------ Permission for Trend Token Interactions -------- //


    function permissionPortfolio(address trendToken, address underlying, bool isSupply, bool isBorrow)  external view onlyProtocolAllowed onlySupportedTrendTokens(trendToken) returns(bool) {
    
        isSupply;
        isBorrow;
        // check Trend Token and underlying are active
        require(trendTokens[trendToken].isActive && underlyingInfo[underlying].isActive,"trendToken not active.");
        require(underlyingInfo[underlying].isActive,"underlying not active.");


        // ensures Venus is active if desire to supply or borrow
        if (isSupply || isBorrow) {
            require(underlyingInfo[underlying].isVenusActive,"Venus not active.");
        }  

        // checks if trendToken and underlying are allowed to supply
        if (isSupply) {
            require(trendTokens[trendToken].isSupplyVenus && underlyingInfo[underlying].isSupplyVenus,"Supply");
        }

        // checks if trendToken and underlying are allowed to supply
        if (isBorrow) {
            require(trendTokens[trendToken].isBorrowVenus && underlyingInfo[underlying].isBorrowVenus,"!permission borrow");
        }

        return true;
    }


    /**
     * @notice Gives permission for users to deposit undelerlyingIn to trendToken
     * @dev Checks if amount greater than zero, trendToken and underlyingIn are active and deposits enabled
     * @dev Trend Token will also have criteria such as token is part of portfolio and enabled
     */
    function permissionDepositTT(address trendToken, address underlyingIn, uint amount) external view onlyProtocolAllowed onlySupportedTrendTokens(trendToken) returns(bool) {

        // amount must be greater than zero
        require(amount>0,"amount must be greater than 0");

        // checks if trendToken has permissions
        require(trendTokens[trendToken].isActive && underlyingInfo[underlyingIn].isActive,"!permission active");

        // checks if trendToken and underlying allows deposits
        require(underlyingInfo[underlyingIn].isDeposit && trendTokens[trendToken].isDeposit,"!isDeposit.");

        return true;
        
    }


    /**
     * @notice Gives permission for users to redeem undelerlyingOut from trendToken
     * @dev Checks if amount greater than zero, trendToken and underlyingOut are active and redeems enabled
     * @dev Trend Token will also have criteria such as token is part of portfolio, enabled, and sufficient supply in contract
     */
    function permissionRedeemTT(address trendToken, address underlyingOut, uint amount) external view onlyProtocolAllowed onlySupportedTrendTokens(trendToken) returns(bool) {

        // amount must be greater than zero
        require(amount>0,"amount must be greater than 0");


        // checks if trendToken has permissions
        require(trendTokens[trendToken].isActive && underlyingInfo[underlyingOut].isActive,"permission active.");

        // checks if trendToken and underlying allows deposits
        require(underlyingInfo[underlyingOut].isRedeem,"underlying has redeems disabled.");

        return true;
        
    }


    function permissionTrade(address trendToken, address underlyingIn, address underlyingOut, uint amount) external view onlyProtocolAllowed onlySupportedTrendTokens(trendToken) returns(bool) {
        trendToken; underlyingIn; underlyingOut;
        // amount must be greater than zero
        require(amount>0,"amount must be greater than 0");

        // tokens cannot be the same
        require(underlyingIn != underlyingOut,"tokens are the same");

        // check activity
        require(trendTokens[trendToken].isActive,"trend token not active.");
        require(underlyingInfo[underlyingIn].isActive && underlyingInfo[underlyingOut].isActive,"underlying not active.");

        // check status
        require(underlyingInfo[underlyingOut].isTrade,"underlying has redeems disabled.");


        return true;

    }


    // ------ Permission for Venus Interactions -------- //


    /**
     * @notice Fetches the price of underlying of vToken
     
    function venusPrice(address vToken) public view returns(uint) {
        IVenusOracle venusOracle = IVenusOracle(ICompVenus(compVenus).oracle());
        return venusOracle.getUnderlyingPrice(vToken); 
    } */

    /**     NO LONGER NEED BECAUSE CHECK IF VTOKENS UNDERLYING MATCHS, CAN CHECK PRICE DIFFERENCES EXTERNALLY AND PAUSE IF NEEDED
     * @notice Checks if prices for underlying are within priceDiscrepancyMax% for Oracle and VenusOracle
     * @dev Used when enabling a vToken and vToken interactions
     
    function pricesWithinRange(address underlying, address vToken) public view returns(bool) {

        // get prices from Oracle and VenusOracle
        uint oraclePrice = oracle.getPriceFromAddress(underlying);
        uint venusOraclePrice = venusPrice(vToken); 

        // get price percent difference (int)
        uint avgPrice = (oraclePrice.add(venusOraclePrice)).mul(1e18).div(2e18);
        int diffPrice = int(oraclePrice).sub(int(venusOraclePrice));
        int diffPerc = diffPrice.mul(1e18).div(int(avgPrice));

        // check if price percent difference is within range
        int diffTol = int(underlyingInfo[underlying].maxPriceDifference);
        if (diffPerc<diffTol && diffPerc>-diffTol) {
            return true;
        } else {
            return false;
        }

    }*/

    /**
     * @notice Fetches the index of underlying in addrs
     * @dev Make sure Trend Token has underlying in portfolio
     */
    function getTokenIndex(address[] memory addrs, address underlying) public pure returns(uint) {
        for (uint i = 0; i < addrs.length; i ++) {
            if (addrs[i] == underlying) {
                return i;
            }
        }
        revert("cannot find underlying index.");
    }


    /**
     * @notice Checks if supply or redeem brings supplied asset closer or farther from desired
     * @dev Used in supply() and redeem() to prevent action that go away from desired
     */
    function performSupplyDirectionCheck(address trendToken, address underlying, uint supplyAmount, uint redeemAmount) public view returns(bool) {

        // get trendToken information
        (address[] memory addrs,
        uint[] memory prices,,
        uint[] memory col,, 
        uint equity) = ITrendToken(trendToken).storedEquityExternal();

        // fetch underlying's index
        uint underlyingIndex = getTokenIndex(addrs, underlying);

        // get underlying price
        uint price = prices[underlyingIndex];
        require(price>0,"!price");

        // get before supply amount
        uint currentSupplyAmount = col[underlyingIndex].mul(1e18).div(price);
        require(redeemAmount <= currentSupplyAmount, "redeem cannot exceed supply amount.");
        uint afterSupplyAmount = currentSupplyAmount.add(supplyAmount).sub(redeemAmount); // invalid repayAmount if negative (error)


        // get desired supply amount
        uint desiredSupplyPercent = ITrendToken(trendToken).collateralAllo(underlyingIndex);
        uint desiredSupplyAmount = desiredSupplyPercent.mul(equity).div(price);

        // user wants permission to supply more
        if (supplyAmount > 0) {
            // check if supply is desireable
            if (afterSupplyAmount <= desiredSupplyAmount) { // users supply would bring closer to desired supply
                return true;
            } else { // supply too much
                return false;
            }

        // user wants permission to redeem
        } else {
            // check if redeem is desireable
            if (afterSupplyAmount >= desiredSupplyAmount) { // users repay would bring closer to desired borrow
                return true;
            } else { // repay too much
                return false;
            }
        }  
        
    }



    /**
     * @notice Gives permission for trend token to redeem underlying of amount
     * @dev Trend Token must also have this token as part of portfolio and action must bring closer to desired borrows
     * @return vToken if permission is granted, otherwise zero address
     */
    function permissionSupply(address trendToken, address underlying, uint supplyAmount) external view onlyProtocolAllowed onlySupportedTrendTokens(trendToken) returns(address) {

        // require vToken exists
        address vToken = underlyingInfo[underlying].vToken;
        require(vToken != address(0), "vToken must be supported.");

        // checks if trendToken and underlying are both active
        require(trendTokens[trendToken].isActive,"trendToken not active.");
        require(underlyingInfo[underlying].isActive && underlyingInfo[underlying].isVenusActive,"underlying not active.");

        // checks if trendToken and underlying are allowed to supply
        require(trendTokens[trendToken].isSupplyVenus && underlyingInfo[underlying].isSupplyVenus,"!supply");

        // makes sure Trend Token Oracle and Venus Oracle have similar prices
        //bool isWithinRange = pricesWithinRange(underlying, vToken);
        //require(isWithinRange,"!priceDiscrepancyMax");

        // makes sure supply brings current redeems closer to desired
        bool supplyDirectionCheck = performSupplyDirectionCheck(trendToken, underlying, supplyAmount, 0);
        require(supplyDirectionCheck, "!supplyDirectionCheck.");

        // make sure token is entered
        bool tokenEntered = compVenus.checkMembership(trendToken, vToken);
        require(tokenEntered,"vToken must be entered.");

        return vToken;
        
    }


    /**
     * @notice Gives permission for trend token to redeem underlying of amount
     * @dev Trend Token must also have this token as part of portfolio and action must bring closer to desired borrows
     * @return vToken if permission is granted, otherwise zero address
     */
    function permissionRedeem(address trendToken, address underlying, uint redeemAmount) external view onlyProtocolAllowed onlySupportedTrendTokens(trendToken) returns(address) {

        // require vToken exists
        address vToken = underlyingInfo[underlying].vToken;
        require(vToken != address(0), "vToken must be supported.");

        // checks if trendToken and underlying are both active
        require(trendTokens[trendToken].isActive,"trendToken not active.");
        require(underlyingInfo[underlying].isActive && underlyingInfo[underlying].isVenusActive,"underlying not active.");

        // makes sure Trend Token Oracle and Venus Oracle have similar prices
        //bool isWithinRange = pricesWithinRange(underlying,vToken);
        //require(isWithinRange,"!priceDiscrepancyMax");

        // makes sure redeem brings current redeems closer to desired
        bool supplyDirectionCheck = performSupplyDirectionCheck(trendToken, underlying, 0, redeemAmount);
        require(supplyDirectionCheck, "!supplyDirectionCheck.");

        // makes sure redeem will not exceed maxBorrowFactor (call compTT)
        bool borrowFactorCleared = performBorrowFactorCheck(trendToken, underlying, vToken, redeemAmount, 0);
        require(borrowFactorCleared, "!borrowFactorCleared.");

        return vToken;
        
    }



    // --------- Venus: borrow and repay ----------- // 


    /**
     * @notice Calculates the total borrows (USD) the trendToken has on Venus
     * @dev Used to perform current BorrowFactor check
     */
    function getStoredBorrowsTotal(address trendToken) public view returns(uint) {

        uint storedBorrows;
        address[] memory vTokens = compVenus.getAssetsIn(trendToken);

        for (uint i = 0; i < vTokens.length; i ++) {

            IVBep20 vToken = IVBep20(vTokens[i]);
            storedBorrows = storedBorrows.add(vToken.borrowBalanceStored(trendToken));
        }

        return storedBorrows;

    }


    /**
     * @param redeemAmount The amount of underlying to be redeemed
     * @return (afterLiquidity, shortfall)
     */
    function getHypoAccountLiquidity(address trendToken, address vToken, uint redeemAmount, uint borrowAmount) public view returns(uint, uint) {

        uint exchangeRate = IVBep20(vToken).exchangeRateStored(); // vTokens * exchangeRate = tokens
        uint redeemTokens = redeemAmount.mul(1e18).div(exchangeRate); // the amount of vTokens to be redeemed

        // get liquidity after deposit or redeem 
        (uint error, uint afterLiquidity, uint shortfall) = ICompVenus(compVenus.comptrollerLens()).getHypotheticalAccountLiquidity(address(compVenus), trendToken, vToken, redeemTokens, borrowAmount);
        require(error == 0, "hypotheticalLiquidity error.");

        return (afterLiquidity, shortfall);

    }



    /** 
     * @notice Checks if borrow or redeem brings borrowFactor above maxBorrowFactor
     * @dev Performed when borrowing or redeeming from Venus
     * @dev BorrowFactor is the amount that is borrowed relative to total borrowable 'borrowed + liquidity'
     * @dev A maxLiquidFactor of 90% means 90% of what can be borrowed is currently borrowed
     *      and assuming an avg colFactor of 70% a 
     * @dev !borrow balance is stored so not updated based on borrows (no issue when protocol active)
     * @param redeemAmount The amount of underlying to redeem
     * @param borrowAmount The amount of underlying to borrow
     * @return True if borrowFactor after action is below maxBorrowFactor
     */
    function performBorrowFactorCheck(address trendToken, address underlying, address vToken, uint redeemAmount, uint borrowAmount) public view returns(bool) {

        // get liquidity after deposit or redeem 
        //(uint error, uint afterLiquidity, uint shortfall) = ICompVenus(compVenus.comptrollerLens()).getHypotheticalAccountLiquidity(address(compVenus), trendToken, vToken, redeemTokens, borrowAmount);
        //require(error == 0, "hypotheticalLiquidity error.");

        (uint afterLiquidity, uint shortfall) = getHypoAccountLiquidity(trendToken, vToken, redeemAmount, borrowAmount);

        // get total borrowed after 'potential' borrow
        uint currentStoredBorrowsTotal = getStoredBorrowsTotal(trendToken);
        uint borrowValue = borrowAmount.mul(priceUnderlyingFresh(IERC20(underlying))).div(1e18);
        uint afterStoredBorrowsTotal = currentStoredBorrowsTotal.add(borrowValue);

        // calculate borrow factor after action 'borrows/borrowable'
        uint afterBorrowFactor = 0;
        if (afterStoredBorrowsTotal>0) {
            uint afterBorrowable = afterStoredBorrowsTotal.add(afterLiquidity);
            afterBorrowFactor = afterStoredBorrowsTotal.mul(1e18).div(afterBorrowable);
        }

        // no borrow or redeem if any shortfall
        uint maxBorrowFactor = trendTokens[trendToken].maxBorrowFactor;
        if (shortfall>0 || afterBorrowFactor > maxBorrowFactor) {
            return false;
        } else {
            return true;
        }

    }


    /** 
     * @notice Checks if borrow or repay brings current borrows closer to desired borrows
     * @dev Performed when borrowing or redeeming 
     * @dev !borrow balance is stored so not updated based on borrows (no issue when protocol active)
     * @return True if action brings current closer to desired 
     */
    function performBorrowDirectionCheck(address trendToken, address underlying, uint borrowAmount, uint repayAmount) public view returns(bool) {

        // get trendToken information
        (address[] memory addrs,
        uint[] memory prices,,,
        uint[] memory bor, 
        uint equity) = ITrendToken(trendToken).storedEquityExternal();

        // fetch underlying's index
        uint underlyingIndex = getTokenIndex(addrs, underlying);

        // get underlying price
        uint price = prices[underlyingIndex];
        require(price>0,"!price");

        // get desired borrow amount
        uint desiredBorrowPercent = ITrendToken(trendToken).borrowAllo(underlyingIndex);
        uint desiredBorrowAmount = desiredBorrowPercent.mul(equity).div(price);

        // get before borrow amount
        uint currentBorrowAmount = bor[underlyingIndex].mul(1e18).div(price);
        require(currentBorrowAmount.add(borrowAmount) > repayAmount, "repay cannot exceed borrow amount");
        uint afterBorrowAmount = currentBorrowAmount.add(borrowAmount).sub(repayAmount); // invalid repayAmount if negative (error)


        // user wants permission to borrow more
        if (borrowAmount > 0) {
            // check if borrow is desireable
            if (afterBorrowAmount <= desiredBorrowAmount) { // users borrow would bring closer to desired borrow 
                return true;
            } else { // borrow too much
                return false;
            }


        // user wants permission to repay
        } else {
            // check if repay is desireable
            if (afterBorrowAmount >= desiredBorrowAmount) { // users repay would bring closer to desired borrow
                return true;
            } else {  // repay too much
                return false;
            }
        }  

    }


    /**
     * @notice Gives permission for trend token to borrow underlying of amount
     * @dev Trend Token must also have this token as part of portfolio and action must bring closer to desired borrows
     * @return vToken if permission is granted, otherwise zero address
     */
    function permissionBorrow(address trendToken, address underlying, uint borrowAmount) external view onlyProtocolAllowed onlySupportedTrendTokens(trendToken) returns(address) {

        // require vToken exists
        address vToken = underlyingInfo[underlying].vToken;
        require(vToken != address(0), "vToken must be supported.");

        // checks if trendToken and underlying are both active
        require(trendTokens[trendToken].isActive,"trendToken not active.");
        require(underlyingInfo[underlying].isActive && underlyingInfo[underlying].isVenusActive,"underlying not active.");


        // check if Trend Token and Underlying has permissions to borrow
        require(trendTokens[trendToken].isBorrowVenus && underlyingInfo[underlying].isBorrowVenus,"!borrow");

        // makes sure Trend Token Oracle and Venus Oracle have similar prices
        //bool isWithinRange = pricesWithinRange(underlying,vToken);
        //require(isWithinRange,"!priceDiscrepancyMax");

        // makes sure borrow will bring current borrows closer to desired
        bool borrowDirectionCleared = performBorrowDirectionCheck(trendToken, underlying, borrowAmount, 0);
        require(borrowDirectionCleared, "!borrowDirectionCleared.");

        // makes sure borrow will not exceed maxBorrowFactor (call compTT)
        bool borrowFactorCleared = performBorrowFactorCheck(trendToken, underlying, vToken, 0, borrowAmount);
        require(borrowFactorCleared, "Borrow would exceed maxBorrowFactor");

        return vToken;

    }


    /**
     * @notice Gives permission for trend token to redeem underlying of amount
     * @dev Trend Token must also have this token as part of portfolio and action must bring closer to desired borrows
     * @dev May not be able to repay if Venus does not allow (such as nothing to repay)
     * @return vToken if permission is granted, otherwise zero address
     */
    function permissionRepay(address trendToken, address underlying, uint repayAmount) external view onlyProtocolAllowed onlySupportedTrendTokens(trendToken) returns(address) {

        // require vToken exists
        address vToken = underlyingInfo[underlying].vToken;
        require(vToken != address(0), "vToken must be supported.");

        // checks if trendToken and underlying are both active
        require(trendTokens[trendToken].isActive,"trendToken not active.");
        require(underlyingInfo[underlying].isActive && underlyingInfo[underlying].isVenusActive,"underlying not active.");

        // makes sure Trend Token Oracle and Venus Oracle have similar prices
        //bool isWithinRange = pricesWithinRange(underlying,vToken);
        //require(isWithinRange,"!priceDiscrepancyMax");

        // makes sure repay will bring current borrows closer to desired
        bool borrowDirectionCleared = performBorrowDirectionCheck(trendToken, underlying, 0, repayAmount);
        require(borrowDirectionCleared, "!borrowDirectionCleared.");

        return vToken;
        
    }



}
