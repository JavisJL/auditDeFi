// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;

import "./IERC20.sol";
import "./ICompTT.sol";
import "./IChainlinkOracle.sol";
import "./CompStorageTT.sol";
import "./UniTT.sol";
import "./SafeMath.sol";
import "./SignedSafeMath.sol";



contract CompTT is ComptrollerStorage {

    using SignedSafeMath for int;
    using SafeMath for uint;

    /// @notice Emitted when an admin supports a market
    event TrendTokenListed(IMarginToken trendToken);

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

    /// @notice Emitted when lockedWallet address is updated
    event UpdateAdmin(address oldWallet, address lockedWallet);

    //// @notice Emitted when compVenus address is updated
    event NewCompVenus(address oldCompVenus, address compVenus);

    //// @notice Emmited when wBNB and vBNB addresses are set
    event NewSetBNB(address oldBNB, address oldVBNB, address newBNB, address newVBNB);



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

    function ensureLockedWallet() private view {
        require(msg.sender == lockedWallet, "!lockedWallet");
    }


    function ensureNonzeroAddress(address someone) private pure {
        require(someone != address(0), "!zeroAddress");
    }


    modifier onlySupportedTrendTokens(address trendToken) {
        require(trendTokenSupported(IMarginToken(trendToken)), "!TrendToken");
        _;
    }

    modifier onlySupportedUnderlyins(address underlying) {
        require(isUnderlyingSupported(underlying), "!Underlying");
        _;
    }

    /**
     * @notice Allows for state of CompTT to be paused or unpaused
     */
    modifier validPauseState(bool state) {
        require(msg.sender == pauseGuardian || msg.sender == admin, " pauseGuardian||admin");
        require(msg.sender == admin || state, "only admin can unpause");
        _;
    }


    /**
     * @notice Prevents admin from executing highly secure operations
     * @dev lockedWallet must unlock before admin has permission to make changes
     */
    modifier requireUnlocked() {
        require(!locked,"!locked");
        _;
    }


    // ---------- EXTERNAL VIEW FUNCTIONS (LENS) ----------- // 

    /**
     * @notice Return the address of the XVS Venus token
     * @dev Used to redeem earned XVS in Margin Tokens
     */
    function getXVSAddress() external view returns (address) {
        return compVenus.getXVSAddress();
    }


    /**
     * @notice Return the address of the XTT token
     * @dev Used to calculate fee discounts in Margin Tokens
     * @dev Must update for mainnet or testnet deployements 
     */
    function getXTTAddress() external pure returns(address) {
        return 0x3fF5f7ca6257E29deD56180f12Dd668c4D4b8ad3;
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
     * @dev Must be in valid pause state as determined by modofier validPauseState
     */
    function _setProtocolPaused(bool state) external validPauseState(state) returns(bool) {
        protocolPaused = state;
        emit ActionProtocolPaused(state);
        return state;
    }


    /**
     * @notice Allows lockedWallet to lock state of CompTT to prevent admin changes
     * @dev Provides layer of security if CompTT keys comprimised
     */
    function _updateLockedState(bool _state) external {
        ensureLockedWallet();
        bool oldState = locked;
        locked = _state;
        emit Locked(oldState, locked);
    }


    /**
     * @notice Allows lockedWallet to change address
     * @param _newWallet Address of new wallet, must be nonzero
     */
    function _updateLockedWallet(address _newWallet) external {

        // admin must set locked wallet initially
        if (lockedWallet == address(0)) {
            ensureAdmin();
        } else {
            ensureLockedWallet();
        }

        ensureNonzeroAddress(_newWallet);
        address oldWallet = lockedWallet;
        lockedWallet = _newWallet;
        emit UpdateLockedWallet(oldWallet, lockedWallet);
    }


    /**
     * @notice Allows lockedWallet to change address
     * @param _newWallet Address of new wallet, must be nonzero
     */
    function _updateAdmin(address _newWallet) external {
        ensureAdmin();
        ensureNonzeroAddress(_newWallet);
        address oldWallet = lockedWallet;
        admin = _newWallet;
        emit UpdateAdmin(oldWallet, lockedWallet);

    }

    /**
      * @notice Allows admin to set a new price oracle for the comptroller
      * @dev Price oracle plays a vital role in the entire Margin Token ecosystem
      * @param newOracle Address of new oracle, must be nonzero
      * @return true if successful, otherwise error message from require statements
      */
    function _setPriceOracle(IOracle newOracle) external requireUnlocked returns (bool) {
        // Check caller is admin
        ensureAdmin();

        // Require oracle has compTT set to this comptroller
        require(newOracle.compTT() == address(this),"!compTT");

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
      * @notice Allows admin to set a new Venus Comptroller
      * @dev Venus comptroller plays a vital role when Margin Tokens interact with Venus
      * @param _compVenus Address of new comptroller, must be nonzero
      * @return true if successful, otherwise error message from require statements
      */
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


    /** 
      * @notice Allows admin to set wbnb and vbnb addresses
      * @dev Required because wBNB and vBNB are handled different than non-payable tokens
      *      For example, cannot get vBNB.underlying() as it does not exist
      * @param _wbnb Address of wrapped BNB
      * @param _vbnb Address of venus vBNB
      * @return true if successful, otherwise error message from require statements
      */
    function _setBNB(address _wbnb, address _vbnb) external requireUnlocked returns(bool) {
        
        ensureAdmin();
        
        require(address(wbnb) == address(0),"wbnb already set");

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
     * @notice Allows admin to change pauseGaurdian address
     * @dev pauseGaurdian can pause the state of entire ecosystem in an emergency
     * @param newPauseGuardian Address of new pauseGaurdian
     * @return true if successful, otherwise error message from require statements
     */
    function _setPauseGuardian(address newPauseGuardian) external requireUnlocked returns (bool) {
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


    // ------------------------- TREND TOKENS SUPPORT ---------------------- // 


    /**
     * @notice Returns true if Trend Token is already supported
     * @dev Many actions require the trendToken to be supported
     * @param trendToken Address of Trend Token to check if it is supported
     * @return true if Trend Token is supported, otherwise false
     */
    function trendTokenSupported(IMarginToken trendToken) internal view returns(bool) {
        for (uint i = 0; i < allTrendTokens.length; i ++) {
            if (allTrendTokens[i] == trendToken) {
                return true;
            }
        }
        return false;
    }


    /**
      * @notice Allows admin to support a new Trend Token
      * @dev Default conditions may vary from testnet to live  
      * @param trendToken The address of the Trend Token to support
      * @return true, if successfully supported, otherwise error message from require statements
      */
    function _supportTrendToken(IMarginToken trendToken) external requireUnlocked returns (bool) {
        
        ensureAdmin();

        // make sure trendToken is a trend token
        require(trendToken.isTrendToken(),"!isTrendToken"); // sanity check

        // Trend Token cannot already be supported
        bool isSupported = trendTokenSupported(trendToken);
        require(!isSupported,"trendToken already supported.");

        // Set default values for newly supported Trend Token
        trendTokens[address(trendToken)] = TrendToken({ isLocked: false, // allows manager to make key changes
                                                        isActive: true, // trend token is active
                                                        isDeposit: true, // users may deposit to Trend Token
                                                        isRedeem: true, // users may redeem from Trend Token
                                                        isTrade: true, // users may swap one underlying for another
                                                        maxTradeFee: 0.01e18, // max trade fee of 5%
                                                        maxPerformanceFee: 0.30e18, // max performance fee of 50% (extreme case)
                                                        maxDisableValue: 100e18, // token may be removed from portfolio with balances max $100
                                                        maxTradeValue: 10000e18, // maximum amount a user can deposit, redeem, or swap
                                                        maxSupply: 1000000e18, // maximum Trend Token supply of Margin Token
                                                        isSupplyVenus: false, // trend token cannot supply to venus
                                                        isBorrowVenus: false, // trend token cannot borrow from venus
                                                        maxBorrowFactor: 0.5e18, // trend token may borrow maximum 0% of borrowable   
                                                        maxMargin: 0.5e18}); // trend token cannot apply margin 'borrow/equity'

        allTrendTokens.push(trendToken);

        emit TrendTokenListed(trendToken);

        return true;
    }


    // --------------- Trend Token Update ------------------ // 


    /**
     * @notice Allows admin to lock or unlock Trend Token
     * @dev Locked state prevents manager of Trend Token to make key changes such as change CompTT
     */
    function _updateTrendTokenLocked(address trendToken, bool _isLocked) external requireUnlocked onlySupportedTrendTokens(trendToken) {
        ensureAdmin();
        trendTokens[trendToken].isLocked = _isLocked;
    } 

    /**
     * @notice Allows pauseGaurdian or admin to change Trend Token active state
     * @dev Permission granted to pauseGaurdian for quick action in case of emergency
     * @param trendToken The trend token to change the active status of
     * @param _isInactive False sets Trend Token to paused (cannot deposit, redeem, or public rebalance)
     */
    function _updateTrendTokenActiveStatus(address trendToken, bool _isInactive) external validPauseState(_isInactive) onlySupportedTrendTokens(trendToken) {
        trendTokens[trendToken].isActive = !_isInactive;

    } 

    /**
     * @notice Allows admin to change Trend Token user actions
     * @dev User actions include buying and selling Trend Tokens, and swaping one underlying for another
     * @param _isDeposit False prevents users from buying new trend tokens with tokens (ex, BTCB)
     * @param _isRedeem False prevents users from selling trend tokens for tokens (ex, BTCB)
     * @param _isTrade False prevents users from swapping one token (ex, BTCB) for another (ex, BNB) using Trend Token portfolio assets 
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
     * @param _isSupplyVenus False prevents Trend Token from being able to supply assets to Venus, but can still redeem
     * @param _isBorrowVenus False prevents Trend Token from being able to borrow assets from Venus, but can still repay 
     */
    function _updateTrendTokenVenusActions(address trendToken, bool _isSupplyVenus, bool _isBorrowVenus) external requireUnlocked onlySupportedTrendTokens(trendToken) {
        ensureAdmin();
        trendTokens[trendToken].isSupplyVenus = _isSupplyVenus;
        trendTokens[trendToken].isBorrowVenus = _isBorrowVenus;
    } 


    /**
     * @notice Allows admin to change maximum deposit/redeem/swap fees and performance fees for a Trend Token
     * @dev _maxTradeFee Maximum trade fee when depositing or redeeming Trend Tokens, or swapping
     * @dev _maxPerformanceFee The maximum performance fee Trend Token manager can set
     */
    function _updateTrendTokenMaxFees(address trendToken, uint _maxTradeFee, uint _maxPerformanceFee) external requireUnlocked onlySupportedTrendTokens(trendToken) {
        ensureAdmin();
        // maxTradeFees must be below 5% and max performance fees below 50%
        require(_maxTradeFee <= 0.05e18 && _maxPerformanceFee <= 0.50e18,"!max fees.");
        
        if (_maxTradeFee > 0) {
            trendTokens[trendToken].maxTradeFee = _maxTradeFee;
        }

        if (_maxPerformanceFee>0) {
            trendTokens[trendToken].maxPerformanceFee = _maxPerformanceFee;
        }
        
    } 


    /**
     * @notice Allows admin to change maxDisableValue, maxTradeValues, and maxSupply
     * @param _maxDisableValue The maximum values a token can hold in a Margin Token for it to be removed from portfolio
     * @param _maxTradeValues The maximum amount of value that a user can deposit, redeem, or swap with Trend Token portfolio
     * @param _maxSupply The maximum supply of Trend Tokens a Trend Token portfolio can have
     */
    function _updateMaxValuesAndSupply(address trendToken, uint _maxDisableValue, uint _maxTradeValues, uint _maxSupply) external requireUnlocked onlySupportedTrendTokens(trendToken) {
        ensureAdmin();

        // used when tradingBot removes a token from portfoliio
        if (_maxDisableValue>0) {
            // value of token in portfolio must be below $1000 for it to be removed
            require(_maxDisableValue <= 1000e18,"!maxDisableValue");
            trendTokens[trendToken].maxDisableValue = _maxDisableValue;
        }

        // used when depositing, redeeming, or swapping
        if (_maxTradeValues>0) {
            // maximum trade that can possible be done is $100,000
            require(_maxTradeValues <= 100000e18,"!maxTradeValue");
            trendTokens[trendToken].maxTradeValue = _maxTradeValues;
        }

        // used when depositing to not exceed Trend Token AUM
        if (_maxSupply>0) {
            // maximum supply of Trend Tokens is 100 million total supply
            require(_maxSupply <= 100000000e18,"!maxSupply");
            trendTokens[trendToken].maxSupply = _maxSupply;
        }

    } 



    /**
     * @notice Allows admin to set max risk of Margin Token portfolio
     * @dev Used when tradingBot updates Margin Token portfolio and when assets are borrowed or redeemed from Venus
     * @param _maxBorrowFactor The maximum amount Trend Token can borrow relative to total borrowable 
     *                         Total borrowable is the sum of collateral * collateral factor)
     *                         Value of 0.90e18 means 90% of total borrowable may be borrowed
     * @param _maxMargin The maximum amount that can be borrowed relative 'borrow/equity'
     *                   Value of 2.0e18 means 3x leverage (1x is spot)
     */
    function _updateTrendTokenBorrowLimits(address trendToken, uint _maxBorrowFactor, uint _maxMargin) external requireUnlocked onlySupportedTrendTokens(trendToken) {
        ensureAdmin();
        require(_maxBorrowFactor <= 0.90e18 && _maxMargin<= 2.0e18,"!borrow limits.");
        trendTokens[trendToken].maxBorrowFactor = _maxBorrowFactor;
        trendTokens[trendToken].maxMargin = _maxMargin;     

    } 


    // ----------------- Trend Token Display -------------------- // 


    /**
     * @notice Checks if trendToken is supported
     */
    function isSupportedTrendToken(IMarginToken trendToken) external view onlyProtocolAllowed returns(bool) {
        return trendTokenSupported(trendToken);
    }


    /**
     * @notice Checks if trendToken is locked
     */
    function isLockedTrendToken(IMarginToken trendToken) external view onlyProtocolAllowed returns(bool) {
        return trendTokens[address(trendToken)].isLocked;
    }


    /**
     * @notice Checks if trendToken is has an active status
     */
    function trendTokenActiveStatus(address trendToken) external view onlyProtocolAllowed returns(bool) {
        return trendTokens[address(trendToken)].isActive;
    }


    /**
     * @notice Checks Trend Tokens user action status
     * @return (isDeposit, isRedeem, isTrade)
     */
    function trendTokenUserActions(address trendToken) external view onlyProtocolAllowed returns(bool,bool,bool) {
        return (trendTokens[trendToken].isDeposit,
                trendTokens[trendToken].isRedeem, 
                trendTokens[trendToken].isTrade);
    }



    /**
     * @notice Checks Trend Tokens venus action status
     * @return (isSupply, isBorrow)
     */
    function trendTokenVenusActions(address trendToken) external view onlyProtocolAllowed returns(bool, bool) {
        return (trendTokens[address(trendToken)].isSupplyVenus, 
                trendTokens[address(trendToken)].isBorrowVenus);
    }


    /**
     * @notice Checks Trend Token max fees
     * @return (maxTradeFee, maxPerformanceFee)
     */
    function trendTokenMaxFees(address trendToken) external view onlyProtocolAllowed returns(uint,uint) {
        return (trendTokens[address(trendToken)].maxTradeFee, 
                trendTokens[address(trendToken)].maxPerformanceFee);
    }



    /**
     * @notice Checks the maximum values (disable and trade) and max supply for a Trend Token
     * @return (maxDisableValue, maxTradeValue, maxSupply)
     */
    function trendTokenMaxValuesAndSupply(address trendToken) external view onlyProtocolAllowed returns(uint,uint,uint) {
        return (trendTokens[address(trendToken)].maxDisableValue, 
                trendTokens[address(trendToken)].maxTradeValue,
                trendTokens[address(trendToken)].maxSupply);
    }


    /**
     * @notice Checks the max risk tolerance for Margin Token
     * @return (maxBorrowFactor, maxMargin)
     */
    function trendTokenMaxBorrowValues(address trendToken) external view onlyProtocolAllowed returns(uint,uint) {
        return (trendTokens[address(trendToken)].maxBorrowFactor,
                trendTokens[address(trendToken)].maxMargin);
        
    }


    // --------------------- UNDERLYING SUPPORT----------------------- // 


    /**
     * @notice Fetches the price of underlying from this Chainlink oracle
     * @dev May be zero if token not added or maxStalePeriod exceeded
     */
    function priceUnderlyingFresh(IERC20 _underlying) internal view returns(uint256) { 
        uint price = oracle.getPriceFromAddress(address(_underlying));
        require(price != 0, "!price");
        return price;
    }


    /**
     * @notice Checks if underlying is already added to supported
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
     * @return True if successfully added, else error message from require statements
     */
    function _supportUnderlying(address underlying) external requireUnlocked returns(bool) {
        ensureAdmin();
        
        // require underlying has a price in oracle (will revert if price is zero)
        priceUnderlyingFresh(IERC20(underlying));

        // require token not already added
        bool alreadySupported = isUnderlyingSupported(underlying);
        require(!alreadySupported, "already supported");

        // require 18 decimals
        require(IERC20(underlying).decimals() == uint8(18),"!18 decimals.");

        // set default values for underlying
        underlyingInfo[underlying] = Underlying({   isActive: true, // underlying is active (may be added to Trend Tokens)
                                                    isDeposit: true, // users may deposit underlying from Trend Tokens
                                                    isRedeem: true, // users may redeem underlying from Trend Tokens
                                                    isTrade: true, // users may swap one underlying for another
                                                    vToken: address(0), // no vToken
                                                    isVenusActive: false, // underlying cannot supply, redeem, borrow, or repay to Venus
                                                    isSupplyVenus: false, // underlying cannot be supplied to Venus
                                                    isBorrowVenus: false}); // underlying cannot be borrowed from Venus

        // add to list of underlying
        supportedUnderlying.push(underlying);

        return true;
    }


    // --------------- UNDERLYING UPDATE ------------------ //


    /**
     * @notice Allows pauseGaurdian or admin to change active status for underlying
     * @dev Permission granted to pauseGaurdian for quick action in case of emergency
     * @dev This includes all 'user-trendToken' and 'trendToken-Venus' interactions with this underlying
     */
    function _updateUnderlyingActiveStatus(address underlying, bool _isInactive) external validPauseState(_isInactive) onlySupportedUnderlyins(underlying) {
        underlyingInfo[underlying].isActive = !_isInactive;
    }


    /** 
     * @notice Allows admin to change the settings for an underlying for User - Trend Token interactions
     * @param _isDeposit False prevents users from depositing this token for Trend Tokens
     * @param _isRedeem False prevents users from redeeming this token from Trend Tokens
     * @param _isTrade False prevents users from trading this token with Trend Token Portfolio
     */
    function _updateUnderlyingForUserActions(address underlying, bool _isDeposit, bool _isRedeem, bool _isTrade) external requireUnlocked onlySupportedUnderlyins(underlying)  {

        // Only admin may support a new vToken
        ensureAdmin();

        // Set new variables
        underlyingInfo[underlying].isDeposit = _isDeposit;
        underlyingInfo[underlying].isRedeem = _isRedeem;
        underlyingInfo[underlying].isTrade = _isTrade;
    }


    /** 
     * @notice Allows admin to support vToken for underlying 
     * @dev Required for this underlying token to interact with Venus
     */
    function _supportVToken(address underlying, address _vToken) external requireUnlocked onlySupportedUnderlyins(underlying) {

        // only admin may support a new vToken
        ensureAdmin();

        // ensures vToken not already supported
        require(underlyingInfo[underlying].vToken == address(0), "vToken already supported.");

        // ensure vTokens underlying is same as underlying input
        if (underlying == address(wbnb)) {
            require(_vToken == address(vbnb), "vToken != wbnb.");
        } else {
            address vTokenUnderlying = IVBep20(_vToken).underlying();
            require(underlying == vTokenUnderlying, "underlying != vToken.underlying.");
        }

        // assigns _vToken to underlyingInfo
        underlyingInfo[underlying].vToken = _vToken;
    }


    /** 
     * @notice Allows admin to change the settings for an underlying for User - Trend Token interactions
     * @param _isVenusActive False prevents any deposit, redeem, borrow, and supplies
     * @param _isSupplyVenus False prevents any supplies of this token to Venus
     * @param _isBorrowVenus False prevents any borrows of this token from Venus
     */
    function _updateUnderlyingForVenusActions(address underlying, bool _isVenusActive, bool _isSupplyVenus, bool _isBorrowVenus) external requireUnlocked onlySupportedUnderlyins(underlying) {

        // Only admin may support a new vToken
        ensureAdmin();

        // ensure a vToken
        require(underlyingInfo[underlying].vToken != address(0), "vToken not supported.");

        // Set new variables
        underlyingInfo[underlying].isVenusActive = _isVenusActive;
        underlyingInfo[underlying].isSupplyVenus = _isSupplyVenus;
        underlyingInfo[underlying].isBorrowVenus = _isBorrowVenus;
    }


    // ----------------- UNDERLYING EXTERNAL ------------------- //

    // ------------ User-TrendToken Interactions -------------- // 


    /**
     * @notice Fetch prices of tokens from Chainlink price oracle
     * @param _underlying The underlying assets to get price of
     * @return Price of underlying asset
     */
    function priceBEP20(IERC20 _underlying) external view onlyProtocolAllowed returns(uint256) { 
        return priceUnderlyingFresh(_underlying);
    }


    /**
     * @notice Checks if this underlying is currently supported 
     * @return True if underlying is supported
     */
    function underlyingSupported(address underlying) external view onlyProtocolAllowed returns(bool) {
        return isUnderlyingSupported(underlying);
    }


    /**
     * @notice Checks if underlying is currently active
     * @return isActive
     */
    function underlyingActiveStatus(address underlying) external view onlyProtocolAllowed returns(bool) {
        return underlyingInfo[underlying].isActive;
    }


    /**
     * @notice Checks the vToken for a given underlying
     * @dev Returns zero address if vToken has not been supported for underlying
     * @return vToken
     */
    function returnVToken(address underlying) external view onlyProtocolAllowed returns(address) {
        return underlyingInfo[underlying].vToken;
    }


    /**
     * @notice Returns the actions users are allowed to take with underlying across all Trend Tokens
     * @return (isDeposit, isRedeem, isTrade)
     */
    function underlyingForUserActions(address underlying) external view onlyProtocolAllowed returns(bool,bool,bool) {
        return (underlyingInfo[underlying].isDeposit, 
                underlyingInfo[underlying].isRedeem, 
                underlyingInfo[underlying].isTrade);
    }


    /**
     * @notice Returns whether or not underlying is active on Venus and allowed to supply and borrow
     */
    function underlyingForVenusActions(address underlying) external view onlyProtocolAllowed returns(bool,bool,bool) {
        return (underlyingInfo[underlying].isVenusActive,
                underlyingInfo[underlying].isSupplyVenus,
                underlyingInfo[underlying].isBorrowVenus);
    }


    // --------- SUPPORT TREND TOKEN AND UPDATE PARAMETERS -------------- //

    // ------ Permission for Trend Token Interactions -------- //


    /**
     * @notice Gives permission to trendToken to add underlying to portfolio with ability to isSupply and isBorrow if applicable
     */
    function permissionPortfolio(address trendToken, address underlying, bool isSupply, bool isBorrow) external view onlyProtocolAllowed onlySupportedTrendTokens(trendToken) returns(bool) {
    
        // check Trend Token and underlying are active
        require(trendTokens[trendToken].isActive && underlyingInfo[underlying].isActive,"trendToken not active.");

        // @notice Deposits must be disabled before updating underlying positions to prevent sandwich attack
        require(IMarginToken(trendToken).depositsDisabled(underlying),"!depositsDisabled");

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
     * @notice Ensures amount is above 0 and value is below maxTradeValue
     * @dev Checks when depositing or redeeming Trend Tokens, or swapping
     */
    function checkTradeValue(address trendToken, address underlying, uint amount) internal view  {
        
        // amount must be greater than zero
        require(amount>0,"amount must be greater than 0");

        // @notice ensure redeemValue is not exceeded
        uint price = priceUnderlyingFresh(IERC20(underlying));
        uint valueOut = amount.mul(price).div(1e18);
        require(valueOut < trendTokens[trendToken].maxTradeValue,"maxTradeValue exceeded.");
    }


    /**
     * @notice Ensures trend token and underlying are active
     * @dev These conditions are checked together frequently
     */
    function checkIsActive(address trendToken, address underlying) internal view {
        require(trendTokens[trendToken].isActive && underlyingInfo[underlying].isActive,"!permission active");
    }


    /**
     * @notice Ensures totalFee calculated by IncentiveModel is below maximum set by CompTT
     * @param totalFee The total fee including fee to protocol and fee or reward to user
     */
    function checkTradeFee(address trendToken, int totalFee) internal view {
        uint maxTradeFee = trendTokens[trendToken].maxTradeFee;
        require(totalFee<int(maxTradeFee) && totalFee > -int(maxTradeFee),"maxTradeFee");
    }


    /**
     * @notice Gives permission for users to deposit undelerlyingIn to trendToken
     * @dev Checks if amount greater than zero, trendToken and underlyingIn are active and deposits enabled
     * @dev Trend Token will also have criteria such as token is part of portfolio and enabled
     * @return True if allowed, otherwise error message from require statement
     */
    function permissionDepositTT(address trendToken, address underlyingIn, uint amount, int totalFeePerc) external view onlyProtocolAllowed onlySupportedTrendTokens(trendToken) returns(bool) {

        // reverts if amount too small or too large
        checkTradeValue(trendToken, underlyingIn, amount);

        // reverts if trend token or underlying are not active
        checkIsActive(trendToken, underlyingIn);

        // reverts if totalFeePerc is above maxTradeFee or below -maxTradeFee
        checkTradeFee(trendToken,totalFeePerc);

        // checks if trendToken and underlying allows deposits
        require(underlyingInfo[underlyingIn].isDeposit && trendTokens[trendToken].isDeposit,"!isDeposit.");

        return true;
        
    }


    /**
     * @notice Gives permission for users to redeem undelerlyingOut from trendToken
     * @dev Checks if amount greater than zero, trendToken and underlyingOut are active and redeems enabled
     * @dev Trend Token will also have criteria such as token is part of portfolio, enabled, and sufficient supply in contract
     * @return True if allowed, otherwise error message from require statement
     */
    function permissionRedeemTT(address trendToken, address underlyingOut, uint amount, int totalFeePerc) external view onlyProtocolAllowed onlySupportedTrendTokens(trendToken) returns(bool) {

        // reverts if amount too small or too large
        checkTradeValue(trendToken, underlyingOut, amount);

        // reverts if trend token or underlying are not active
        checkIsActive(trendToken, underlyingOut);

        // reverts if totalFeePerc is above maxTradeFee
        checkTradeFee(trendToken,totalFeePerc);

        // checks if trendToken and underlying allows deposits
        require(underlyingInfo[underlyingOut].isRedeem,"underlying redeems disabled.");

        return true;
        
    }


    /**
     * @notice Gives permission to trendToken to make a trade between underlyingIn and underlyingOut of amount
     * @dev Value, fees, and active status are checked before giving permission
     * @return True if allowed, otherwise error message from require statement
     */
    function permissionTrade(address trendToken, address underlyingIn, address underlyingOut, uint valueIn, uint valueOut) external view onlyProtocolAllowed onlySupportedTrendTokens(trendToken) returns(bool) {

        // reverts if amount too small or too large
        require(valueIn>0,"must be >0");
        require(valueOut < trendTokens[trendToken].maxTradeValue,"maxTradeValue exceeded.");

        // reverts if trade fee too large
        uint maxTradeFee = trendTokens[trendToken].maxTradeFee;
        require(valueOut < valueIn.mul(uint(1e18).add(maxTradeFee)).div(1e18) && 
                valueOut > valueIn.mul(uint(1e18).sub(maxTradeFee)).div(1e18),
                "!maxTradeFee");

        // tokens cannot be the same
        require(underlyingIn != underlyingOut,"tokens are the same");

        // check activity
        require(trendTokens[trendToken].isActive,"trend token not active.");
        require(underlyingInfo[underlyingIn].isActive && underlyingInfo[underlyingOut].isActive,"underlying not active.");

        // check status
        require(underlyingInfo[underlyingOut].isTrade,"underlying redeems disabled.");


        return true;

    }


    // ------ Permission for Venus Interactions -------- //


    /**
     * @notice External function for performSupplyDirectionCheck
     */
    function performSupplyDirectionCheckExt(address trendToken, address underlying, uint supplyAmount, uint redeemAmount) external view returns(bool) {
        return performSupplyDirectionCheck(trendToken, underlying, supplyAmount, redeemAmount);

    }


    /**
     * @notice Fetches the index of underlying in addrs
     * @dev Make sure Trend Token has underlying in portfolio
     * @dev Returns index if it exsits, otherwise error message "no index"
     */
    function getTokenIndex(address[] memory addrs, address underlying) internal pure returns(uint) {
        for (uint i = 0; i < addrs.length; i ++) {
            if (addrs[i] == underlying) {
                return i;
            }
        }
        revert("no index.");
    }


    /**
     * @notice Checks if supply or redeem action brings current supplied asset closer or farther from desired
     * @dev Used in permissionSupply() and permissionRedeem() in order to give permission for actions
     * @return true if supply or redeem brings current supplies closer to desired, otherwise false
     */
    function performSupplyDirectionCheck(address trendToken, address underlying, uint supplyAmount, uint redeemAmount) internal view returns(bool) {

        // get trendToken information
        (address[] memory addrs,
        uint[] memory prices,,
        uint[] memory col,, 
        uint equity) = IMarginToken(trendToken).storedEquityExternal();

        // fetch underlying's index
        uint underlyingIndex = getTokenIndex(addrs, underlying);

        // get underlying price
        uint price = prices[underlyingIndex];
        require(price>0,"!price");

        // get before supply amount
        uint currentSupplyAmount = col[underlyingIndex].mul(1e18).div(price);
        require(redeemAmount <= currentSupplyAmount, "redeem exceeded supply amount.");
        uint afterSupplyAmount = currentSupplyAmount.add(supplyAmount).sub(redeemAmount); // invalid repayAmount if negative (error)

        // get desired supply amount
        uint desiredSupplyPercent = IMarginToken(trendToken).collateralAllo(underlyingIndex);
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
        } else if (redeemAmount > 0) {
            // check if redeem is desireable
            if (afterSupplyAmount >= desiredSupplyAmount) { // users repay would bring closer to desired borrow
                return true;
            } else { // repay too much
                return false;
            }
        }  
        
    }


    /**
     * @notice Ensures vToken is supported, trend token is active, and underlying in active venus state
     * @return vToken supported and active, otherwise error message based on require statement
     */
    function checkSupportedAndActive(address trendToken, address underlying) internal view returns(address) {

        // require vToken exists
        address vToken = underlyingInfo[underlying].vToken;
        require(vToken != address(0), "vToken must be supported.");

        // checks if trendToken and underlying are both active
        require(trendTokens[trendToken].isActive,"trendToken not active.");
        require(underlyingInfo[underlying].isActive && underlyingInfo[underlying].isVenusActive,"underlying not active.");

        return vToken;

    }


    /**
     * @notice Gives permission for trend token to supply underlying of amount to Venus
     * @return vToken if permission is granted, otherwise zero address
     */
    function permissionSupply(address trendToken, address underlying, uint supplyAmount) external view onlyProtocolAllowed onlySupportedTrendTokens(trendToken) returns(address) {

        // reverts if vToken not supported or trend token and underlying not in active venus state
        address vToken = checkSupportedAndActive(trendToken, underlying);

        // checks if trendToken and underlying are allowed to supply
        require(trendTokens[trendToken].isSupplyVenus && underlyingInfo[underlying].isSupplyVenus,"!supply");

        // makes sure supply brings current redeems closer to desired
        bool supplyDirectionCheck = performSupplyDirectionCheck(trendToken, underlying, supplyAmount, 0);
        require(supplyDirectionCheck, "!supplyDirectionCheck.");

        // make sure token is entered
        bool tokenEntered = compVenus.checkMembership(trendToken, vToken);
        require(tokenEntered,"vToken must be entered.");

        return vToken;
        
    }


    /**
     * @notice Gives permission for trend token to redeem underlying of amount from Venus
     * @return vToken if permission is granted, otherwise zero address
     */
    function permissionRedeem(address trendToken, address underlying, uint redeemAmount) external view onlyProtocolAllowed onlySupportedTrendTokens(trendToken) returns(address) {

        // reverts if vToken not supported or trend token and underlying not in active venus state
        address vToken = checkSupportedAndActive(trendToken, underlying);

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
     * @notice External function for getStoredBorrowsTotal
     */
    function getStoredBorrowsTotalExt(address trendToken) external view returns(uint) {
        return getStoredBorrowsTotal(trendToken);
    }


    /**
     * @notice External function for getHypoAccountLiquidity
     */
    function getHypoAccountLiquidityExt(address trendToken, address vToken, uint redeemAmount, uint borrowAmount) external view returns(uint, uint) {
        return getHypoAccountLiquidity(trendToken, vToken, redeemAmount, borrowAmount);
    }


    /**
     * @notice External function for performBorrowFactorCheck
     */
    function performBorrowFactorCheckExt(address trendToken, address underlying, address vToken, uint redeemAmount, uint borrowAmount) external view returns(bool) {
        return performBorrowFactorCheck(trendToken, underlying, vToken, redeemAmount, borrowAmount);
    }


    /**
     * @notice External function for performBorrowDirectionCheck
     */
    function performBorrowDirectionCheckExt(address trendToken, address underlying, uint borrowAmount, uint repayAmount) external view returns(bool) {
        return performBorrowDirectionCheck(trendToken, underlying, borrowAmount, repayAmount);
    }


    /**
     * @notice Calculates the total borrows (USD) the trendToken has on Venus
     * @dev Used to perform current BorrowFactor check
     */
    function getStoredBorrowsTotal(address trendToken) internal view returns(uint) {

        uint storedBorrows;
        address[] memory vTokens = compVenus.getAssetsIn(trendToken);

        for (uint i = 0; i < vTokens.length; i ++) {

            IVBep20 vToken = IVBep20(vTokens[i]);
            storedBorrows = storedBorrows.add(vToken.borrowBalanceStored(trendToken));
        }

        return storedBorrows;

    }


    /**
     * @notice Calculates the hypothetical account liquidity after action redeemAmount or borrowAmount for vToken by trendToken
     * @dev Used by performBorrowFactorCheck to give permission to redeem or borrow (increase risk) with Venus
     * @return (afterLiquidity, shortfall)
     */
    function getHypoAccountLiquidity(address trendToken, address vToken, uint redeemAmount, uint borrowAmount) internal view returns(uint, uint) {

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
     * @dev A borrowFactor of 90% means 90% of what can be borrowed is currently borrowed
     * @param redeemAmount The amount of underlying to redeem
     * @param borrowAmount The amount of underlying to borrow
     * @return True if borrowFactor after action is below maxBorrowFactor, otherwise false
     */
    function performBorrowFactorCheck(address trendToken, address underlying, address vToken, uint redeemAmount, uint borrowAmount) internal view returns(bool) {

        // afterLiquidity is liquidity after redeem or borrow. Shortfall is positive if protocol in the negative
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
     * @dev Performed when Trend Token borrows or repays assets to Venus
     * @return True if action brings current closer to desired, otherwise false
     */
    function performBorrowDirectionCheck(address trendToken, address underlying, uint borrowAmount, uint repayAmount) internal view returns(bool) {

        // get trendToken information
        (address[] memory addrs,
        uint[] memory prices,,,
        uint[] memory bor, 
        uint equity) = IMarginToken(trendToken).storedEquityExternal();

        // fetch underlying's index
        uint underlyingIndex = getTokenIndex(addrs, underlying);

        // get underlying price
        uint price = prices[underlyingIndex];
        require(price>0,"!price");

        // get desired borrow amount
        uint desiredBorrowPercent = IMarginToken(trendToken).borrowAllo(underlyingIndex);
        uint desiredBorrowAmount = desiredBorrowPercent.mul(equity).div(price);

        // get before borrow amount
        uint currentBorrowAmount = bor[underlyingIndex].mul(1e18).div(price);
        require(repayAmount <= currentBorrowAmount.add(borrowAmount), "repay > borrow amount");
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
        } else if (repayAmount > 0) {
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
     * @return vToken if permission is granted, otherwise zero address
     */
    function permissionBorrow(address trendToken, address underlying, uint borrowAmount) external view onlyProtocolAllowed onlySupportedTrendTokens(trendToken) returns(address) {

        // reverts if vToken not supported or trend token and underlying not in active venus state
        address vToken = checkSupportedAndActive(trendToken, underlying);

        // check if Trend Token and Underlying has permissions to borrow
        require(trendTokens[trendToken].isBorrowVenus && underlyingInfo[underlying].isBorrowVenus,"!borrow");

        // makes sure borrow will bring current borrows closer to desired
        bool borrowDirectionCleared = performBorrowDirectionCheck(trendToken, underlying, borrowAmount, 0);
        require(borrowDirectionCleared, "!borrowDirectionCleared.");

        // makes sure borrow will not exceed maxBorrowFactor (call compTT)
        bool borrowFactorCleared = performBorrowFactorCheck(trendToken, underlying, vToken, 0, borrowAmount);
        require(borrowFactorCleared, "!maxBorrowFactor");

        return vToken;

    }


    /**
     * @notice Gives permission for trend token to repay underlying of repayAmount
     * @dev May not be able to repay if Venus does not allow (such as nothing to repay)
     * @return vToken if permission is granted, otherwise zero address
     */
    function permissionRepay(address trendToken, address underlying, uint repayAmount) external view onlyProtocolAllowed onlySupportedTrendTokens(trendToken) returns(address) {

        // reverts if vToken not supported or trend token and underlying not in active venus state
        address vToken = checkSupportedAndActive(trendToken, underlying);

        // makes sure repay will bring current borrows closer to desired
        bool borrowDirectionCleared = performBorrowDirectionCheck(trendToken, underlying, 0, repayAmount);
        require(borrowDirectionCleared, "!borrowDirectionCleared.");

        return vToken;
        
    }


}
