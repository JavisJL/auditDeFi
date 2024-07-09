// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "./IMarginToken.sol";
import "./IChainlinkOracle.sol";
import "./ICompVenus.sol";
import "./IVBNB.sol";



contract UnitrollerAdminStorage {
    /**
    * @notice Administrator for this contract
    */
    address public admin;

    /**
    * @notice Pending administrator for this contract
    */
    address public pendingAdmin;

    /**
    * @notice Active brains of Unitroller
    */
    address public comptrollerImplementation;

    /**
    * @notice Pending brains of Unitroller
    */
    address public pendingComptrollerImplementation;
}



contract ComptrollerStorage is UnitrollerAdminStorage {

    // --------------- EXTERNAL ADDRESSES -------------------- //

    /**
     * @notice Venus Comptroller Address
     */
    ICompVenus public compVenus;

    /**
     * @notice Oracle which gives the price of any given asset
     */
    IOracle public oracle;

    // --------------- LOCKED WALLET -------------------- //

    /**
     * @notice Wallet that is able to change the state of locked
     */
    address public lockedWallet;

    /**
     * @notice Restrictions actions of admin if locked
     * @dev Adds an extra layer of security
     */
    bool public locked = true;


    // --------------- PAUSE GUARDIAN -------------------- //

    /**
     * @notice The Pause Guardian can pause certain actions as a safety mechanism.
     *  Actions which allow users to remove their own assets cannot be paused.
     *  Liquidation / seizing / transfer can only be paused globally, not by market.
     */
    address public pauseGuardian;


    /**
     * @notice Pause/Unpause whole protocol actions
     */
    bool public protocolPaused;


    // -------------- TREND TOKENS --------------- //

    /**
     * @notice A list of all Trend Tokens
     */
    IMarginToken[] public allTrendTokens;


    /**
     * @notice Official mapping of vTokens -> Market metadata
     * @dev Used e.g. to determine if a market is supported
     */
    mapping(address => TrendToken) public trendTokens;


    struct TrendToken {

        // @notice Prevents manager from making specific changes in Trend Token
        // @dev Changes include compTT, incentiveModel, manager, tradingBot, performanceFee, disableValue, maxSupply
        bool isLocked;

        // @notice Whether or not this Trend Token is active
        // @dev Allows no Trend Token (deposits, redeems, trades) or Venus (supply, redeem, borrow, repay)
        bool isActive;

        // ------------ User-TrendToken Interactions -------------- //

        // @notice Whether or not users can deposit (buy Trend Tokens) with this Trend Token
        // @dev Allows for users to buy Trend Tokens
        bool isDeposit; 

        // @notice Whether or not users can redeem (sell Trend Tokens) with this Trend Token
        // @dev Allows for users to sell Trend Tokens
        bool isRedeem; 
        
        // @notice Whether or not this Trend Token is tradeable
        // @dev Allows for users to swap one token (BTCB) for another (ETH) using Trend Token portfolio
        bool isTrade;

        // @notice The maximum trade fee this Trend Token can have
        uint maxTradeFee;

        // @notice The maximum performance fee this Trend Token can have
        uint maxPerformanceFee;

        // @notice Maximum value (contract and collateral and borrow) to disable token from portfolio
        uint maxDisableValue;

        // @notice Maximum value (contract and collateral and borrow) to disable token from portfolio
        uint maxTradeValue;

        // @notice Maximum value (contract and collateral and borrow) to disable token from portfolio
        uint maxSupply;

        // ------------ TrendToken-Venus Interactions -------------- // 

        // @notice Whether or not this Trend Token can supply to Venus
        // @dev Allows for Trend Token to supply assets to Venus
        bool isSupplyVenus;

        // @notice Whether or not this Trend Token can borrow from Venus
        // @dev Allows for Trend Token to borrow from Venus
        bool isBorrowVenus;

        // @notice Percentage of borrowable (supplied*colFactor) that may be borrowed
        // @dev Safety mechanism to prevent being too close to liquidation
        // @dev borrowFactor 80% with colFactor 80% can go max 2.75x leverage
        // @dev borrowFactor 70% with colFactor 70% can go max 1.95x leverage
        // @dev borrowFactor 60% with colFactor 60% can go max 1.90x leverage
        uint maxBorrowFactor;

        // @notice Maximum leverage that Trend Token can have
        // @dev Value of 1e18 means Trend Token may go 2x
        uint maxMargin;
    }


    // --------------- UNDERLYING ------------------- // 

    /**
     * @notice Address of WBNB
     */
    IERC20 public wbnb;


    /**
     * @notice Address of vBNB
     */
    IVBNB public vbnb;


    /**
     * @notice a list of all supported underlying tokens
     * @dev May be added to Trend Token portfolios
     */
    address[] public supportedUnderlying;


    /**
     * @notice Official mapping of vTokens -> Market metadata
     * @dev Used e.g. to determine if a market is supported
     */
    mapping(address => Underlying) public underlyingInfo;


    /**
     * @notice Settings for this underlying apply to all Trend Tokens
     */
    struct Underlying {

        // @notice Whether or not this Trend Token is active
        // @dev Admin may set Trend Token to inactive to prevent any activity
        // @dev This includes all 'user-trendToken' and 'trendToken-Venus' interactions
        bool isActive;

        // ------------ User-TrendToken Interactions -------------- // 

        // @notice Admin prevent this underlying to be deposited to any trend token
        // @dev Set to false in an emergency (ex, oracle prices is off)
        bool isDeposit;

        // @notice Admin may prevent this underlying to be redeem from any trend token
        // @dev Set to false in an emergency (ex, oracle prices is off)
        bool isRedeem;

        // @notice Admin may prevent this underlying from being traded in any Trend Token
        // @dev Set to false in an emergency (ex, oracle prices is off)
        bool isTrade;

        // ------------ TrendToken-Venus Interactions -------------- // 

        // @notice vToken address for this underlying
        // @dev Zero address is vToken is not supported
        address vToken;

        // @notice No interactions with Venus allowed
        // @dev If active, may always repay or redeem from pool
        bool isVenusActive;

        // @notice Allows public interactions with Venus allowed (only trading bot)
        // @dev If true, public may supply, redeem, repay, and borrow
        bool isVenusOpen;

        // @notice Allows any Trend Token to supply this asset to Venus
        bool isSupplyVenus;

        // @notice Allows any Trend Token to borrow this asset to Venus
        // @dev Usually only USDT (uptrend) or BTC (downtrend)
        bool isBorrowVenus;

    }
    

}

