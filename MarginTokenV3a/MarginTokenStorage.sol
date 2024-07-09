// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "./ITrendTokenTkn.sol";
import "./XTTgov.sol";
import "./ICompTT.sol";
import "./IIncentiveModel.sol";


contract MarginTokenStorage {


    // --------------- EVENTS ----------- // 

    /**
     * @notice Emitted when Trend Token receives BNB
     */
    event RecievedBNB(uint value);

    /**
     * @notice Emitted when Trend Token redeemed for underlying
     */
    event Redeem(uint tokenPrice, uint trendTokenPrice, uint supplyTrendToken, uint protocolFeePerc, int feeOrReward, uint addTrendTokenAmt);


    /**
     * @notice Emitted when Trend Token deposited for underlying
     */
    event Deposit(uint tokenPrice, uint trendTokenPrice, uint supplyTrendToken, uint protocolFeePerc, int feeOrReward);


    /**
     * @notice Emitted when Trend Token price makes new all time high and performance fee charged
     */
    event PerformanceFee(uint trendTokenStart, uint oldTrendTokenATH, uint newTrendTokenATH, uint addTrendTokenAmt);


    /**
     * @notice Emitted when contract addresses changed
     */
    event UpdateIncentiveModel(address oldIncentive, address newIncentive);

    /**
     * @notice Emitted when wallet addresses changed
     */
    event UpdateManagerAndBot(address oldManager, address newManager, address oldTradingBot, address newTradingBot);

    /**
     * @notice Emitted when performance fee changed
     */
    event NewPerformanceFee(uint oldFee, uint newFee);

    /**
     * @notice Emitted when max disable value changed
     */
    event UpdateMaxDisableAndSupply(uint oldMaxDisableValue, uint newMaxDisableValue, uint oldMaxSupply, uint newMaxSupply);

    /**
     * @notice Emitted deposits are disable
     */
    event DepositsDisabled(address underlying, bool oldState, bool newState);

    /**
     * @notice Emitted when allocations changed, as well as when enabling or disabling tokens
     */
    event SetDesiredAllocationsFresh(address[] portfolio, uint[] oldAllocations, uint[] newAllocations);

    /**
     * @notice Emitted when a trade is executed
     */
    event ExecuteTrade(uint amountIn, uint valueIn, uint valueOut, uint amountOut);


    // --------------- ADMIN ADJUSTABLE VARIABLES ----------- // 

    /**
     * @dev Guard variable for re-entrancy checks
     */
    bool internal _notEntered; 

    /**
     * @notice The managers wallet who has special access of Trend Token
     * @dev Access includes fees, factors, change managers, etc
     */
    address payable public manager; 

    /**
     * @notice The trading bot wallet who has special access of Trend Token
     * @dev Access includes portfolios, allocations, and dual pool actions (except trading)
     */
    address public tradingBot; 


    /**
     * @notice The deposit and redeem incentive model
     */
    IIncentiveModel public incentiveModel;


    /**
     * @notice Sets the desired allocations of the portfolio 
     * @dev Allocations are in percents relative to equity
     */
    address[] public portfolioTokens;
    uint[] public contractAllo;
    uint[] public collateralAllo;
    uint[] public borrowAllo;


    /**
     * @notice Allows manager to pause Trend Token
     * @dev Prevents deposits, withdrawals, and borrow rebalances
     */
    bool public trendTokenPaused = false;



    /**
     * @notice Prevents users from minting Trend Tokens beyond this limit
     * @dev Manager is able to adjust this value
     */
    uint public maxSupply = 10000e18;


    /**
     * @notice Percentage of Trend Token price all tiem high gains that goes to fee recipient
     */
    uint public performanceFee = 0.10e18;


    /**
     * @notice Minimum position value allowed to disable token
     * @dev Disabling a token with a large balance would result in trend token price drop
     */
    uint public maxDisableTokenValue = 1e18;


    // --------------- TOKEN VARIABLES ----------- // 

    /**
     * @notice CompTT ensures this variable is true before supporting a Trend Token
     */
    bool public constant isTrendToken = true;


    /**
     * @notice The Trend Token contract address
     */
    ITrendTokenTkn public trendToken;



    // ----------------- FEES AND RESERVES -------------------- // 


    /**
     * @notice Value keeps track of the Trend Token price all time high
     * @dev Any gains above this are subject to performance fee
     */
    uint public trendTokenATH = 1e18; 


    /**
     * @notice Prevents deposits of this token
     */
    mapping(address => bool) public depositsDisabled;



}


