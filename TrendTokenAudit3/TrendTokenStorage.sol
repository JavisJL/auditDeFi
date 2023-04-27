// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;

import "./ITrendTokenTkn.sol";
import "./XTTgov.sol";
import "./ICompTT.sol";
import "./IIncentiveModelSimple.sol";


contract TrendTokenStorage {


    // --------------- EVENTS ----------- // 
    

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
    event NewIncentiveModel(address oldIncentiveModel, address newIncentiveModel);
    event NewCompTT(address oldCompTT, address newCompTT);
    event NewCompDP(address oldCompDP, address newCompDP);

    /**
     * @notice Emitted when wallet addresses changed
     */
    event NewManager(address oldManager, address newManager);
    event NewFeeRecipient(address oldFeeRecipient, address newFeeRecipient);
    event NewTradingBot(address oldTradingBot, address newTradingBot);

    /**
     * @notice Emitted when performance fee changed
     */
    event NewPerformanceFee(uint oldFee, uint newFee);

    /**
     * @notice Emitted when fee distribution changed
     */
    event UpdateFeeDistribution(uint oldTrendToken,uint newTrendToken, uint oldXDP, uint newXDP);


    /**
     * @notice Emitted when max disable value changed
     */
    event MaxDisableValue(uint oldValue, uint newValue);


    /**
     * @notice Emitted when max supply changed
     */
    event SetMaxSupply(uint oldSupply, uint newSupply);


    /**
     * @notice Emitted when contract factor changed
     */
    event SetContractFactor(uint oldFactor, uint newFactor); 

    /**
     * @notice Emitted deposits are disable
     */
    event DepositsDisabled(address underlying, bool oldState, bool newState);

    /**
     * @notice Emitted when Trend Token is paused
     */
    event PauseTrendToken(bool oldState, bool newState);   

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
     * @notice Will redeem assets from Dual Pools if percentage of token equity in contract falls below this value
     * @dev This keeps a float of assets in the contract for low gas cost Trend Token deposits and redeems
     */
    uint public contractFactor = 0.90e18;


    /**
     * @notice Sets the desired allocations of the portfolio 
     * @dev Allocations are in percents relative to equity
     */
    uint[] public desiredAllocations;


    /**
     * @notice Prevents users from minting Trend Tokens beyond this limit
     * @dev Manager is able to adjust this value
     */
    uint public maxSupply = 1000e18;


    /**
     * @notice The managers wallet who has special access of Trend Token
     * @dev Access includes fees, factors, change managers, etc
     */
    address public manager; 

    /**
     * @notice The trading bot wallet who has special access of Trend Token
     * @dev Access includes portfolios, allocations, and dual pool actions (except trading)
     */
    address public tradingBot; 


    /**
     * @notice Wallet that can receive deposit fees, reserves, and XTT
     */
    address payable public feeRecipient;


    /**
     * @notice The deposit and redeem incentive model
     */
    IIncentiveModelSimple public incentiveModel;


    /**
     * @notice Allows manager to pause Trend Token
     * @dev Prevents deposits, withdrawals, and borrow rebalances
     */
    bool public trendTokenPaused = false;


    /**
     * @notice Reward for referrer and referrer upon purchase of Trend Token
     */
    uint public referralReward = 0.40e18;


    /**
     * @notice Percentage of Trend Token price all tiem high gains that goes to fee recipient
     */
    uint public performanceFee = 0.10e18;


    /**
     * @notice Percentage of trend tokens fees from redeems that are burned (increase price
     * @dev Increases the price of Trend Tokens
     */
    uint public trendTokenRedeemBurn = 0.50e18;


    /**
     * @notice Percentage of protocol earned XDP that goes to fee recipient
     * @dev Does not increase the price of Trend Tokens
     */
    uint public accruedXDPtoFeeRecipient = 0.50e18;


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


    /**
     * @notice Address for Trend Tokens XTT Utility Token
     * @dev Distributed when users hold Trend Tokens in Vaults
     *      PancakeSwap XTT-BNB pair created
     */
    IXTT public xtt = IXTT(0xd8C1C6fa863226aC68f8c925A18E3B43F512B590); 
    
    
    /** note: 
     * @notice Address for Dual Pools XDP Utility token
     * @dev Earned by Trend Tokens when they borrow/supply to Dual Pools
     *      PancakeSwap XDP-BNB pair created
     */
    IERC20 public xdp = IERC20(0x4EaB863A16fFf3190ACbF0b2043fc25A113C7ef7);//IERC20(0xf79c28eB5bd0cC10B58F04DfF7c34d0c8D39BdE6);


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


