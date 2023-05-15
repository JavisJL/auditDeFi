// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;

import "./ITrendToken.sol";
import "./IChainlinkOracle.sol";



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

    /**
     * @notice Oracle which gives the price of any given asset
     */
    IOracle public oracle;


    /**
     * @notice Per-account mapping of "assets you are in", capped by maxAssets
     */
    mapping(address => ITrendToken[]) public accountAssets;


    struct TrendToken {

        // @notice Whether or not this Trend Token is listed 
        bool isListed;

        // @notice Whether or not this Trend Token is active
        // @dev Admin may set Trend Token to inactive to prevent any activity
        bool isActive;

        // @notice Whether or not this Trend Token is tradeable
        // @dev Admin may set Trend Token to isTrade to prevent any trade activity
        bool isTrade;

        // @notice Whether or not this Trend Token can interact with Dual Pools
        bool allowedDualPools;

        // @notice The maximum trade fee this Trend Token can have
        uint maxTradeFee;

        // @notice The maximum performance fee this Trend Token can have
        uint maxPerformanceFee;

        // @notice Maximum value (contract and collateral) to disable token from portfolio
        uint maxDisableValue;

    }


    /**
     * @notice Official mapping of vTokens -> Market metadata
     * @dev Used e.g. to determine if a market is supported
     */
    mapping(address => TrendToken) public trendTokens;


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


    /**
     * @notice Sets a specific Trend Token to paused
     * @dev Does not allow for deposit or redeems
     */
    mapping(address => bool) public mintGuardianPaused;


    /**
     * @notice A list of all Trend Tokens
     */
    ITrendToken[] public allTrendTokens;

    /**
     * @notice a list of all supported underlying tokens
     * @dev May be added to Trend Token portfolios
     */
    address[] public supportedTokens;

    /**
     * @notice Mapping of underlying:dTokens
     */
    mapping(address => address) public tokenToDToken;


    /**
     * @notice Wallet that is able to change the state of locked
     */
    address lockedWallet;

    /**
     * @notice Restrictions actions of admin if locked
     * @dev Adds an extra layer of security
     */
    bool locked = true;


}

