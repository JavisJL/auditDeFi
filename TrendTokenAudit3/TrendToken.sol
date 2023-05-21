// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;

import "./TrendTokenTkn.sol";
import "./DualPool.sol";
import "./CompTT.sol";
import "./ICompTT.sol";
import "./TrendTokenStorage.sol";
import "./IncentiveModelSimple.sol";
import "./SignedSafeMath.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";




// Deploy Addresses (testnet):
// XTT: 0x4D0E7Cd2A4f6D45d72B7936DDb8652aa3216A51e (verified)


// apr 22: 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x491ca17fDd1028D470Bb4e527935f092B86E41b9,0x022d21035c00594bdFBdAf77bEF76BBCe597d876,0xd99d1c33f9fc3444f8101754abc46c52416550d1

// ** complete
// * in progress
// ! skip


// ---- To Do Mar -------- // 
// 1) Trade referral program? - no, just deposits
// 4)** Remove performance fee distribution from deposit/redeem
// 5)** Trade: Add minOutput
// 6)** Can remove borVals from storedEquity() 
// 7)**  Add Deadline to deposit/redeem/swap functions?
// 8)** Require approval of tradingBot and manager for some functions
//      - _updateCompAndModels, _updateManagerRecipientAndBot, _maxDisableValue 
//      - could have variable changeable = false by default
//        and must be True for manager to make changes! 
//          - tradingBot OR lock can update changeable 
//      - tradingBot live, safeLock in ON, manager in AB
//      - for compTT, could do something similar but with a timelock 
//          that can be triggered by lockSafe 

contract TrendToken is DualPoolIntegration, TrendTokenStorage { 

    using SignedSafeMath for int;
    using SafeERC20 for IERC20;

    // -------- CONSTRUCTOR ------------- //   

    // Mar 25: 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x20e0827B4249588236E31ECE4Fe99A29a0Ec40bA,0x022d21035c00594bdFBdAf77bEF76BBCe597d876,0xd99d1c33f9fc3444f8101754abc46c52416550d1
    // Apr 23: 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x491ca17fDd1028D470Bb4e527935f092B86E41b9,0x022d21035c00594bdFBdAf77bEF76BBCe597d876
    // May 8 trend token: 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x8825E9B3d875E8468444E70a7779C0e342c40E35,0x022d21035c00594bdFBdAf77bEF76BBCe597d876
    // May 8 incentive: 0x04b2840AaF73f7358b5bE325F71385Cf2e6De916
    // enable bnb, busd, btcb: [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47,0xA808e341e8e723DC6BA0Bb5204Bafc2330d7B8e4],[0,1000000000000000000,0]
   // enable bnb, busd, btcb: [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47,0xA808e341e8e723DC6BA0Bb5204Bafc2330d7B8e4],[340000000000000000,330000000000000000,330000000000000000]
    // enable bnb, busd: [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47],[500000000000000000,500000000000000000]
    // enable bnb, busd: [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47],[1000000000000000000,0]
    // USDT: 0xA11c8D9DC9b66E209Ef60F0C8D969D3CD988782c

    // trade: [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47],0
    // trade: 331117962966515488,0,[0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47,0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd]

    // tradeInfo (busd->bnb): [0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47,0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd],[0x2a98C6E2BD140513df99FFCC710902a2faFb3bb7,0x243fF2E429B4676d37085E7b5a1e1576f11508f3],1000000000000000000
    // tradeinfo (bnb->busd): [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47],[0x243fF2E429B4676d37085E7b5a1e1576f11508f3,0x2a98C6E2BD140513df99FFCC710902a2faFb3bb7],1000000000000000000

    // swap BNB->BUSD: ["0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd","0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47"]
    // swap BUSD->BNB: ["0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47","0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd"]

    // XTT: 0x4D0E7Cd2A4f6D45d72B7936DDb8652aa3216A51e
    // compTT: 0x20e0827B4249588236E31ECE4Fe99A29a0Ec40bA
    // TrendToken: 0xb07d446fCFD123939d0a4B38Ba5725c61c43e290
    // IncentiveModel: 0xc2b0706227D1c991D508AAE81b86253E86DeF30B
    // zeroAddress: 0x0000000000000000000000000000000000000000

    // May
    // compTT: 0x9c2b3dC41eb3d4D272B16F2bd9F52806D14C7dE6
    // Tren5: 0x24418EDAB489Ec5Aa52503f703Ef0F6Ecba66170

    constructor(address _wbnb, address _compTT, address _compDP) 
                DualPoolIntegration(_wbnb,_compTT,_compDP) public {
        compTT = ICompTT(_compTT);
        manager = msg.sender;
        tradingBot = msg.sender;
        feeRecipient = msg.sender;
        TrendTokenTkn _trendToken = new TrendTokenTkn("TrendToken Top5","Top5");
        trendToken = ITrendTokenTkn(address(_trendToken));
        wbnb = IERC20(_wbnb);
        _notEntered = true;
        
    }


    /**
     * @notice Allows for the deposit of BNB to this contract
     */
    function () external payable {
        //emit RecievedBNB(msg.value);
    }


    /**
     * @notice Used for contract byte size savings
     */
    function onlyModifiers(address _owner, string memory message) view internal {
        require(msg.sender == _owner, message);
    }


    /**
     * @notice Restricts actions to manager
     */
    modifier onlyManager() {
        onlyModifiers(manager,"!manager");
        _;
    } 


    /**
     * @notice Restricts actions to tradingBot
     */
    modifier onlyTradingBot() {
        onlyModifiers(tradingBot,"!tradingBot");
        _;
    } 


    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     */
    modifier nonReentrant() {
        require(_notEntered, "re-entered");
        _notEntered = false;
        _;
        _notEntered = true; // get a gas-refund post-Istanbul
    }


    /**
     * @notice Prevents mint, redeem, and borrow rebalance if Trend Tokens are paused
     */
    modifier pausedTrendToken() {
        require(!trendTokenPaused, "!paused");
        _;
    }

    /**
     * @notice Prevents Manager from executing highly secure operations
     * @dev Including _updateCompAndModels, _updateManagerRecipientAndBot, _maxDisableValue, _adjustCollateral 
     */
    modifier requireUnlocked() {
        require(!locked,"!locked");
        _;
    }

    /**
     * @notice Ensures deadline is not exceeded upon deposit, redeem, or swap
     */
    modifier ensureDeadline(uint _deadline) {
        require(_deadline >= block.timestamp, "!timestamp");
        _;
    }

    /**
     * @notice Checks wheter or not value is equal to or less than max, else gives message
     * @dev Saves byte size over repreating similar require statements
     */
    function requireUnderAmount(uint value, uint max, string memory message) internal pure {
        require(value<=max, message);
    }


    // ---------------   ADMIN FUNCTIONS & VARIABLES ----------------- //

    
    // -------  MANAGER: UPDATE ADDRESSES ------- // 


    /**
     * @notice Sets new Trend Token comptroller, Dual Pool comptroller, and incentive model
     * @dev If want unchanged, set parameter to zero address
     * @param _compTT The Trend Token comptroller that governs all Trend Tokens
     * @param _compDP The Dual Pool comptroller that governs all dTokens for lend/redeem actions
     * @param _incentiveModel View functions that dictate the deposit and redeem rewarrds 
     */
    function _updateCompAndModels(address _compTT, address _compDP, IIncentiveModelSimple _incentiveModel) onlyManager requireUnlocked external {
        
        if (_compTT != address(0)) {
            address oldCompTT = address(compTT);
            require(ICompTT(_compTT).trendTokenIsActive(address(this)),"Inactive TT." );
            compTT = ICompTT(_compTT);
            emit NewCompTT(oldCompTT, address(compTT));
        }

        if (_compDP != address(0)) {
            address oldCompDP = address(compDP);
            compDP = ICompDP(_compDP);
            emit NewCompDP(oldCompDP, address(compDP));
        }

        if (address(_incentiveModel) != address(0)) {
            address oldIncentive = address(incentiveModel);
            incentiveModel = _incentiveModel;
            emit NewIncentiveModel(oldIncentive, address(incentiveModel));
        }
 
    }


    /**
     * @notice Allows manager to change manager, fee recipient, and trading bot
     * @dev If want unchanged, set parameter to zero address
     * @param _manager Ability to set fees, factors, etc
     * @param _feeRecipient Address where deposit, redeem, performance, and XDP earnings go
     * @param _tradingBot Ability to set portfolios, allocations, and some Dual Pool actions
     */
    function _updateManagerRecipientAndBot(address _manager, address payable _feeRecipient, address _tradingBot) onlyManager requireUnlocked external {

        if (_manager != address(0)) {
            address oldManager = address(manager);
            manager = _manager;
            emit NewManager(oldManager, address(manager));
        }

        if (_feeRecipient != address(0)) {
            address oldFeeRecipient = address(feeRecipient);
            feeRecipient = _feeRecipient;
            emit NewFeeRecipient(oldFeeRecipient, address(feeRecipient));
        }

        if (_tradingBot != address(0)) {
            address oldTradingBot = address(tradingBot);
            tradingBot = _tradingBot;
            emit NewTradingBot(oldTradingBot, address(tradingBot));
        }

    }
    

    // -------  MANAGER: UPDATE FEES/REWARDS ------- // 

    
    /** 
     * @notice Updates performance fee 
     * @dev Must send performance fee first 
     * param _performanceFee Percentage of new trend token ATH gains that goes to reserves
     */
    function _newPerformanceFee(uint _performanceFee) onlyManager requireUnlocked external {
        requireUnderAmount(_performanceFee, compTT.trendTokenMaxPerformanceFee(address(this)), "!performanceFee");
        (uint trendTokenPrice, uint mintMBNB) = trendTokenToUSD(); 
        sendPerformanceFee(mintMBNB, trendTokenPrice);
        uint oldFee = performanceFee;
        performanceFee = _performanceFee;
        emit NewPerformanceFee(oldFee, performanceFee);
    }
    

    /**
     * @notice Updates the fee distribution to Fee Receipient
     * @param _trendTokenRedeemBurn Percentage of redeem trend token fees that get burned (instead of going to reserves)
     *                               which increases the value of Trend Tokens
     */
    function _updateTrendTokenBurn(uint  _trendTokenRedeemBurn) external onlyManager {
        requireUnderAmount(_trendTokenRedeemBurn, 1e18, "exceeded 100%.");
        uint oldTrendToken = trendTokenRedeemBurn;
        trendTokenRedeemBurn = _trendTokenRedeemBurn;
        emit UpdateTrendTokenBurn(oldTrendToken, trendTokenRedeemBurn);
    }


    /**
     * @notice Allows manager to set the referralReward
     */
    function _setReferralReward(uint _referralReward) onlyManager external {
        requireUnderAmount(_referralReward, 0.50e18, "!_setReferralReward");
        uint oldReward = referralReward;
        referralReward = _referralReward;
        emit SetReferralReward(oldReward, referralReward);
    }


    // -------   MANAGER: UPDATE VALUES ------- // 


    /**
     * @notice Sets the minimum value of a token before it can be removed from the portfolio
     */
    function _maxDisableValue(uint _maxDisableTokenValue) onlyManager requireUnlocked external {
        requireUnderAmount(_maxDisableTokenValue, compTT.trendTokenMaxDisableValue(address(this)), "!maxDisableValue");
        uint oldValue = maxDisableTokenValue;
        maxDisableTokenValue = _maxDisableTokenValue;
        emit MaxDisableValue(oldValue, maxDisableTokenValue);
    }


    /**
     * @notice Allows manager to set the maximum Trend Token supply
     * @param _maxSupply The new Trend Token max supply 
     */
    function _setMaxSupply(uint _maxSupply) onlyManager external {
        uint oldSupply = maxSupply;
        maxSupply = _maxSupply;
        emit SetMaxSupply(oldSupply, maxSupply);
    }


    /**
     * @notice Allows manager to set amount of equity to be held in contract (remainder held in Dual Pools)
     */
    function setContractFactor(uint _contractFactor) internal {
        requireUnderAmount(_contractFactor, 1e18, "!max");
        uint oldFactor = contractFactor;
        contractFactor = _contractFactor;
        emit SetContractFactor(oldFactor, contractFactor);
    }


    /**
     * @notice Allows manager to set amount of equity to be held in contract (remainder held in Dual Pools)
     */
    function _setContractFactor(uint _contractFactor) onlyManager external {
        setContractFactor(_contractFactor);
    }


    // -------- MANAGER: DUAL POOL INTERACTIONS --------------- // 

    /**
     * @notice Allows admin to supply or redeem collateral from contract holdings
     */
    function _adjustCollateral(IERC20 _bep20, uint _supplyAmt, uint _redeemAmt) onlyManager requireUnlocked external {
        IVBep20 dToken = dTokenSupportedRequire(_bep20);
        if (_supplyAmt > 0) {
            collateralSupply(_bep20,dToken, _supplyAmt);
        } else if (_redeemAmt > 0) {
            collateralRedeem(_bep20,dToken,_redeemAmt);
        }
    }


    // ------- TRADING BOT: UPDATE BOOL --------- //


    /**
     * @notice Allows trading bot to change state of locked
     * @dev if locked is true, manager actions are limited (higher security) 
     *      as a result, some actions require permission of both
     */
    function _updateLocked(bool _state) onlyTradingBot external {
        bool oldState = locked;
        locked = _state;
        emit Locked(oldState, locked);
    }


    /**
     * @notice Allows trading bot to pause deposits of underlying
     * @dev Used when wanting to disable a token
     */
    function _depositsDisabled(address underlying, bool _state) onlyTradingBot external {
        bool oldState = depositsDisabled[underlying];
        depositsDisabled[underlying] = _state;
        emit DepositsDisabled(underlying, oldState, depositsDisabled[underlying] );
    }


    /**
     * @notice Allows manager to pause Trend Token
     * @dev Pauses mint/redeem/borrowRebalance of this Trend Token
     * @param _pause True if this Trend Token is to be paused
     */
    function _pauseTrendToken(bool _pause) onlyTradingBot external {
        bool oldState = trendTokenPaused;
        trendTokenPaused = _pause;
        emit PauseTrendToken(oldState, trendTokenPaused);
    }



    // ------- TRADING BOT: UPDATE PORTFOLIO --------- //


    /**
     * @notice Requires dToken for _bep20 to exist
     */
    function dTokenSupportedRequire(IERC20 _bep20) internal view returns(IVBep20) {
        IVBep20 dToken = IVBep20(compTT.returnDToken(address(_bep20))); 
        require(address(dToken) != address(0), "!dToken");
        return dToken;
    }


    /**
     * @notice Changes deposit weights of portfolio
     * @dev Weights must equal 1e18 and be same length as entered portfolio on Dual Pools
     * @param _allocations The desired supply and contract equity positions (>100% when leverage long)
     */
    function _setDesiredAllocationsFresh(uint[] memory _allocations) internal {
        uint allocationTotal = 0;
        for (uint i=0; i<_allocations.length; i++) {
            allocationTotal = allocationTotal.add(_allocations[i]);
        }
        require(allocationTotal == 1e18 && _allocations.length == getMarkets().length, "allocation!=100% or !length");
        uint[] memory oldAllocations = desiredAllocations;
        desiredAllocations = _allocations;
        emit SetDesiredAllocationsFresh(getMarkets(), oldAllocations, desiredAllocations);
    }


    /**
     * @notice Allows manager to change deposit weights without changing portfolio
     * @param _allocations The desired supply and contract equity positions (>100% when leverage long)
     * param _borrows The desired borrow borrow positions (>0% USD when long, >0% other when short)
     */
    function _setDesiredAllocations(uint[] calldata _allocations) onlyTradingBot external {
        _setDesiredAllocationsFresh(_allocations);
    }


    /** 
    *   Enables tokens market (borrow or collateral)
    *   Requires tokens is listed in venusTokens 
    *   requires slippage on pancake is below threshold (commented out for isolated test)
    */
    function _enableTokens(address[] calldata _tokens, uint[] calldata _allocations) onlyTradingBot external {
        address[] memory dTokens = new address[](_tokens.length);
        for (uint i=0; i<_tokens.length; i++) {
            address token = _tokens[i];
            address dToken = address(dTokenSupportedRequire(IERC20(token)));
            dTokens[i] = dToken; 
        }
        enableCol(dTokens);
        _setDesiredAllocationsFresh(_allocations);
    }


    /**
    * @notice Requires the dToken has been enabled on Dual Pools
    * @dev All enabled tokens are also listed and active on CompTT
    */
    function checkActiveToken(IVBep20 _dToken) internal view {
        require(address(_dToken) != address(0) && tokenEntered(_dToken),"!enabled");
    }


    /** 
    *   Disables token market (cant borrow or collateral)
    *   Requires token is currently enabled
    *   Requires total value (contract, collateral, borrow) is below minTradeVal
    *       otherwise Equity will drop and therefore price of Trend Token
    */
    function _disableToken(IERC20 _bep20, uint[] calldata _allocations) onlyTradingBot external {
        IVBep20 dToken = dTokenSupportedRequire(_bep20);
        require(_bep20 != wbnb && tokenEquityVal(dToken) < maxDisableTokenValue,"!BNB or !maxVal");
        checkActiveToken(dToken);
        compDP.claimXDP(address(this));
        disableCol(dToken);
        _setDesiredAllocationsFresh(_allocations);
    }


    // -------------------- MANAGER: REDEEM & REDUCE TREND TOKENS ------------------- // 
    /**
     * @notice Allows manager to redeem Trend Tokens to fee recipient OR redeem for BNB --> XTT --> burn
     */


    /**
     * @notice Sends performance fee (in Trend Tokens) to this Trend Token contract
     */
    function _redeemPerformanceFee() onlyManager external {
        (uint trendTokenPrice, uint mintMBNB) = trendTokenToUSD(); 
        sendPerformanceFee(mintMBNB, trendTokenPrice);
    }


    /** 
     * @notice Allows manager to redeem Trend Tokens to fee recipient wallet
     */
    function _reduceTrendTokenReservesToRecipient(uint redeemAmtTrendToken) onlyManager external  {
        uint currentBalance = trendToken.balanceOf(address(this));
        requireUnderAmount(redeemAmtTrendToken, currentBalance, "!balanceTT");
        IERC20(address(trendToken)).safeTransfer(feeRecipient,redeemAmtTrendToken);
    }


    // ------- TRADING BOT: REDEEM & DISTRIBUTE XDP --------- //

    /** 
     * @notice Claims XDP from Dual Pools and sends _redeemAmountXDP to Fee Recipoient
     * @dev The remainder of XDP stays in the pool 
     */
    function _redeemXDPtoRecipient(bool claim, uint _redeemAmountXDP) onlyManager external  {
        if (claim) {
            compDP.claimXDP(address(this));
        }
        requireUnderAmount(_redeemAmountXDP, balanceXDP(),"!balXDP");
        xdp.safeTransfer(feeRecipient,_redeemAmountXDP);
    }


    // ------ EXTERNAL VIEW FUNCTIONS ------------- //


    /**
     * @notice Returns the underlying price of dToken externally
     */
    function priceExt(IVBep20 _dToken) external view returns(uint) {
        return priceBEP20(_dToken) ;
    }


    /**
     * @notice Returns the price of trend token (in USD) externally
     */
    function trendTokenToUSDext() external view returns(uint, uint) {
        return trendTokenToUSD();
    }


    /** 
     * @param trendTokenIn True if trendTokenInCalculations else trendTokenOutCalculations
     * @return (uint price, uint trendTokenPrice, uint mintMBNB, uint trendTokenAmt, uint protocolFeePerc, int feeOrReward)
     */
    function trendTokenExternal(IERC20 _bep20, IVBep20 _dToken, uint _amount, bool trendTokenIn) 
        external view returns(uint, uint, uint, uint, uint, int)  {
            if (trendTokenIn) {
                return trendTokenInCalculations(_bep20, _dToken, _amount);
            } else {
                return trendTokenOutCalculations(_bep20, _dToken, _amount);
            }
    }


    /**
     * @notice External function for stored equity
     */
    function storedEquityExternal() external view returns(address[] memory,uint[] memory,uint[] memory,uint[] memory,uint) {
        return storedEquity();
    }


    /**
     * @notice External function for token information
     */
    function tokenInfoExternal(IVBep20 _dToken, uint depositAmt, uint redeemAmt) external view returns(int, int, uint, uint) {
        return tokenInfo(_dToken, depositAmt, redeemAmt);
    }


    /**
     * @notice Calculates the value out after selling tokenInOut[0] for tokenInOut[1]
     */
    function tradeInfoExt(IERC20[] calldata tokenInOut, IVBep20[] calldata dTokensInOut, uint valueIn) external view returns(uint) {
        return tradeInfo(tokenInOut, dTokensInOut, valueIn);
    }



    // ----- PROTOCOL DEPOSITS AND WITHDRAWALS   ------ //

    // --------- PERFORMANCE FEE ---------- // 


    /**
     * @notice Calculates outstanding performance fee
     * @param trendTokenPrice The current price of a Trend Token
     * @param trendTokenSupply The current Trend Token supply
     * @return The amount of Trend Tokens desired to be minted and sent to fee recipient
     */
    function calculatePerformanceFee(uint trendTokenPrice, uint trendTokenSupply) internal view returns(uint) {
        uint gainATH = trendTokenPrice.sub(trendTokenATH); // (3e18 - 1.5e18) = 1.5e18
        uint feeAmt = Lib.getValue(gainATH,performanceFee); // 1.5e18 * 20% = = 0.30e18
        uint targetPrice = trendTokenPrice.sub(feeAmt); // 3e18 - 0.30e18 = 2.7e18 (price after fee)
        uint mintPercent = Lib.getAssetAmt(trendTokenPrice,targetPrice) - 1e18;// (3.0e18*1e18/2.7e18) - 1e18 = 0.1111e18
        uint mintTrendTokenAmt = Lib.getValue(trendTokenSupply,mintPercent); // 100e18 * 0.1111e18 / 1e18 = 11.111...e18 mBNB 
        return mintTrendTokenAmt;
    }


    /**
     * @notice Mints and sends trend token performance fees to reserves
     * @param _mintTrendTokenAmt The number of Trend Tokens desired to be minted
     * @param _trendTokenPrice The current Trend Token price in USD
     */
    function sendPerformanceFee(uint _mintTrendTokenAmt, uint _trendTokenPrice) internal {
        if (_mintTrendTokenAmt>0) {
            trendToken.mint(address(this), _mintTrendTokenAmt); // mint and send 10.52e18 margin tokens to owner (decreasing value 1.041%)
            uint oldTrendTokenATH = trendTokenATH;
            trendTokenATH = _trendTokenPrice; // update 
            emit PerformanceFee(_trendTokenPrice,oldTrendTokenATH,trendTokenATH, _mintTrendTokenAmt);
        }
    }


    // --------- BALANCES, EQUITY, TREND TOKEN PRICE ---------- // 
    /**
     * @notice Key internal view functions to supply and redeem Trend Tokens
     */


    /**
     * @notice Fetches the balance of XDP of this Trend Token
     */
    function balanceXDP() internal view returns(uint balance) {
        balance = xdp.balanceOf(address(this));
    }


    /**
     * @notice Fetches this Trend Tokens balance of an underlying token
     * @param _dToken The dToken to get balance of 
     * @return The balance of _token
     */
    function contractBal(IVBep20 _dToken) internal view returns(uint) {
        if (_dToken == dBNB) { 
            return address(this).balance;
        } else { 
            return IERC20(_dToken.underlying()).balanceOf(address(this));
        }
    }


    /**
     * @notice Fetchs the current balance of Trend Token and calculates total equity
     * @dev Total Equity is the value of call contract and collateral positons
    */
    function storedEquity() internal view returns(address[] memory,uint[] memory,uint[] memory,uint[] memory,uint) {  // returns current balances (uint)

        address[] memory dTokens = getMarkets();
        uint[] memory prices = new uint[](dTokens.length);
        uint[] memory conVals = new uint[](dTokens.length);
        uint[] memory colVals = new uint[](dTokens.length);
        uint assetValSum = 0; 

        for (uint i = 0; i < dTokens.length; i++) {

            // fetch token and price
            IVBep20 dToken = IVBep20(dTokens[i]);
            uint tokenToUSD = priceBEP20(dToken);
            prices[i] = tokenToUSD;
            (uint tokenBal,, uint rate) = screenshot(dToken);

            // contract balances
            uint contractVal = Lib.getValue(contractBal(dToken),tokenToUSD);
            conVals[i] = contractVal;

            // collateral values
            uint collateralAmt = Lib.getValue(tokenBal,rate);
            uint collateralVal = Lib.getValue(collateralAmt,tokenToUSD);
            colVals[i] = collateralVal;
            
            assetValSum = assetValSum.add(contractVal.add(collateralVal));

        }

        uint netEquity = assetValSum;
        return (dTokens,prices,conVals,colVals,netEquity);

    }


    /**
     * @notice Publicly returns this Trend Tokens price in USD
     */
    function trendTokenToUSD() internal view returns(uint,uint) {
        (,,,,uint equity) = storedEquity();
        return trendTokenToUSD(equity);
    }


    /**
    * @notice Calculate the Trend Token Price in USD
    * @dev Deducts any outstanding performance fees and adds value of XDP if the price exists   
    * @param _equityInUSD The current equity value of portfolio
    * @return Price of Trend Token, number of outstand performance fee Trend Tokens
    */
    function trendTokenToUSD(uint _equityInUSD) internal view returns(uint,uint) {  

        uint price = 1e18; // starting condition
        uint supplyTrendToken = trendToken.totalSupply();
        uint mintTrendToken = 0; 

        if (supplyTrendToken > 0) {

            price = Lib.getAssetAmt(_equityInUSD,supplyTrendToken);

            if (price > trendTokenATH) { // account for outstading performance fee
                mintTrendToken = calculatePerformanceFee(price, supplyTrendToken);
            }

            price = Lib.getAssetAmt(_equityInUSD,supplyTrendToken.add(mintTrendToken));
        }

        return (price,mintTrendToken);

    }


    /**
     * @notice Fetches data required for deposit/redeem incentives for a specific token
     * @param _dToken The spefific token to get information on
     * @return allocationDelata Difference between desired and current percent allocations
     *         price The price of _token, 
     *         equity The total Trend Token equity in contract and Dual Pools
     *         Positive allocation delta if desire more of the asset
     */
    function tokenInfo(IVBep20 _dToken, uint depositAmt, uint redeemAmt) internal view returns(int priorDelta, int postDelta, uint price, uint equity) {
        
        (address[] memory dTokens, // 0x00 in placeholder for all tokens except _dToken
        uint[] memory prices,
        uint[] memory conVals,
        uint[] memory colVals,
        uint netEquity) = storedEquity(); // !!!!!!!!!!!!!!!!!!! change to a array of single token (or tokenInfo input paramet

        for (uint i=0; i < dTokens.length; i++) {

            if (IVBep20(dTokens[i]) == _dToken) {

                price = prices[i];
                equity = netEquity;
                uint depositVal = Lib.getValue(depositAmt,price);
                uint redeemVal = Lib.getValue(redeemAmt,price);

                if (netEquity>0) {

                    uint tokenEquity = conVals[i].add(colVals[i]);
                    uint priorAllocation = Lib.getAssetAmt(tokenEquity,netEquity);
                    priorDelta = int(desiredAllocations[i]).sub(int(priorAllocation));

                    require(tokenEquity >= redeemVal && netEquity >= redeemVal,"not enough to redeem");

                    uint postAllocation = Lib.getAssetAmt(tokenEquity.add(depositVal).sub(redeemVal),netEquity.add(depositVal).sub(redeemVal));
                    postDelta = int(desiredAllocations[i]).sub(int(postAllocation));

                } else {

                    require(redeemVal==0,"redeem=0.");
                    priorDelta = int(desiredAllocations[i]);
                    postDelta = int(1e18);
                     
                }
                
            }
        
        }

    }


    /**
     * @notice Calculates the equity (in USD) of underlying associated with _dToken
    */
    function tokenEquityVal(IVBep20 _dToken) internal view returns(uint) {
        
        address[] memory _dTokens = getMarkets();

        for (uint i=0; i < _dTokens.length; i++) {

            if (IVBep20(_dTokens[i]) == _dToken) {

                // get info
                uint tokenPrice = priceBEP20(IVBep20(_dTokens[i]));
                (uint tokenBal,, uint rate) = screenshot(IVBep20(_dTokens[i]));

                // get contract value
                uint contractVal = Lib.getValue(contractBal(IVBep20(_dTokens[i])),tokenPrice);

                // get collateral value
                uint collateralVal = Lib.getValue(Lib.getValue(tokenBal,rate),tokenPrice);

                return contractVal.add(collateralVal);

            }
        
        }

    }


    // ------------ DEPOSIT FUNCTION -------------- //
    /**
     * @notice Allows users to supply any asset in the portfolio for Trend Tokens
     * @dev Rewards for supplying assets the Trend Token desires, fees for supplying other assets
     */


    /**
     * @notice Sends referralReward% of protocolFeePerc to referral and referralReward% to referrer
     */
    function distributeReferralReward(IERC20 _token, uint _sellAmtBEP20, uint _protocolFeePerc, address payable referrer) internal {
        
        uint totalProtocolFeeAmt = Lib.getValue(_sellAmtBEP20,_protocolFeePerc);
        uint distributeAmount = Lib.getValue(totalProtocolFeeAmt,referralReward);

        if (_token == wbnb) {

            msg.sender.transfer(distributeAmount); 
            referrer.transfer(distributeAmount); 

        } else {

            _token.safeTransfer(msg.sender, distributeAmount); 
            _token.safeTransfer(referrer, distributeAmount); 


        }

    }


    /**
     * @notice Calculates the fees and trend token amounts out upon deposit
     * @dev Calls the Incentive Model contract to fetch base protocol fee and fee/reward incentive
     */
    function trendTokenOutCalculations(IERC20 _depositBep20, IVBep20 _dToken, uint _sellAmtBEP20) 
        internal view returns(uint price, uint trendTokenPrice, uint mintMBNB, uint trendTokenAmt, uint protocolFeePerc, int feeOrReward)  {

        (int priorDelta, int postDelta, uint priceToken, uint equity) = tokenInfo(_dToken,_sellAmtBEP20,0);
        uint inValue = Lib.getValue(_sellAmtBEP20,priceToken);
        equity = equity.sub(inValue); // equityprior

        (feeOrReward, protocolFeePerc,,) = incentiveModel.totalDepositFee(_depositBep20, inValue, priorDelta, postDelta, priceToken, xtt.balanceOf(msg.sender)); 
        uint inValueMinusFees = Lib.getValue(inValue, uint(int(1e18).sub(feeOrReward)));

        (trendTokenPrice, mintMBNB) = trendTokenToUSD(equity); 
        trendTokenAmt = Lib.getAssetAmt(inValueMinusFees,trendTokenPrice);
        price = priceToken;

    }


    /**
     * @notice Allows the deposit of BNB/BEP20 for Trend Tokens
     * @dev Keeps protocolFeePerc in Pool (no longer sent to admin)
     */
    function depositFresh(IERC20 _depositBep20, uint _sellAmtBEP20, uint _minTrendTokenOut, address payable _referrer) internal pausedTrendToken returns(uint)  {
        
        // Requirements
        compTT.depositOrRedeemAllowed(address(this),_sellAmtBEP20); // above zero, unpaused, trend token active
        IVBep20 dToken = IVBep20(compTT.returnDToken(address(_depositBep20)));
        require(!depositsDisabled[address(_depositBep20)], "deposits disabled");  // checks deposits arent disabled
        checkActiveToken(dToken); // checks this Trend Token is an enabled dToken

        // Calculate prices, fees, and amounts
        (uint priceToken,
        uint trendTokenPrice,, 
        uint trendTokenAmt, 
        uint protocolFeePerc, 
        int feeOrReward) = trendTokenOutCalculations(_depositBep20, dToken, _sellAmtBEP20);

        // Send fees and Trend Token to user
        //sendPerformanceFee(mintTrendTokenAmt,trendTokenPrice); // MAYBE REMOVE FOR TAX REASONS? 
        require(trendTokenAmt >= _minTrendTokenOut,"!minOut");
        trendToken.mint(msg.sender, trendTokenAmt);// mint and send Margin Token to Trader (after fees)

        // Require max supply isnt exceeded
        uint supplyTrendToken = trendToken.totalSupply();
        require(supplyTrendToken <= maxSupply,"!maxSupply.");

        // Sends 40/40 of protocolFeePerc to referrer/referral instead of going to Pool
        if (_referrer != address(0)) {
            distributeReferralReward(_depositBep20, _sellAmtBEP20, protocolFeePerc, _referrer);
        }

        emit Deposit(priceToken, trendTokenPrice, supplyTrendToken, protocolFeePerc, feeOrReward);

        return trendTokenAmt;

    }


    /**
    *   Payable function for buying Trend Tokens with BNB
    */
    function depositBNB(uint _minTrendTokenOut, uint _deadline, address payable _referrer) external nonReentrant ensureDeadline(_deadline) payable {
        depositFresh(wbnb, msg.value, _minTrendTokenOut,_referrer);
    }


    /**
    *   Payable function for buying Trend Tokens with BNB
    */
    function deposit(IERC20 _depositBep20, uint _sellAmtBEP20, uint _minTrendTokenOut, address payable _referrer, uint _deadline) external nonReentrant ensureDeadline(_deadline) {
        uint balanceBefore = _depositBep20.balanceOf(address(this));
        _depositBep20.safeTransferFrom(msg.sender, address(this), _sellAmtBEP20);
        uint balanceAfter = _depositBep20.balanceOf(address(this));
        uint actualTransferredAmount = balanceAfter.sub(balanceBefore);
        depositFresh(_depositBep20, actualTransferredAmount,_minTrendTokenOut,_referrer);
    }


    // --- REDEEM FUNCTIONS  --- //
    /**
     * @notice Allows users to redeem Trend Tokens for any underlying asset, if it has a sufficient balance
     * @dev Rewards for redeeming assets the Trend Token does not want, fees for redeeming other assets
     */


    /**
     * @notice Sends underlying to user after depositing Trend Tokens
     * @dev Redeems from Dual Pools if contract balance isnt great enough
     *      Amount is updated as exact amount redeemed may vary from _amount
     */
    function sendUnderlyingOut(IERC20 _underlying, IVBep20 _dToken, uint _amount) internal {
        //require(_amount <= contractBal(_dToken),"insufficent bal");
        requireUnderAmount(_amount,contractBal(_dToken),"insufficent bal");

        if (_underlying == wbnb) {

            msg.sender.transfer(_amount); 

        } else {

            _underlying.safeTransfer(msg.sender, _amount); 

        }
    }


    /**
     * @notice Calculates the amount of underlying to send to manager after deposit of Trend Tokens
     * @dev Takes into account the redeem fee calculation from incentive model
     */
    function trendTokenInCalculations(IERC20 _redeemBep20, IVBep20 _dToken, uint _redeemAmt) 
        internal view returns(uint price, uint trendTokenPrice, uint mintMBNB, uint trendTokenInAmt, uint protocolFeePerc, int feeOrReward)  {

        (int priorDelta, int postDelta, uint priceToken, uint equity) = tokenInfo(_dToken,0,_redeemAmt);
        uint outValueEst = Lib.getValue(_redeemAmt,priceToken); // 1 * $1 = $1

        (feeOrReward, protocolFeePerc,,) = incentiveModel.totalRedeemFee(_redeemBep20, outValueEst, priorDelta, postDelta, priceToken, xtt.balanceOf(msg.sender));
        uint outValueAddFees = Lib.getValue(outValueEst, uint(int(1e18).add(feeOrReward))); // $1 * 1-0.0035 = 0.9965

        (trendTokenPrice, mintMBNB) = trendTokenToUSD(equity);  // 1.002
        trendTokenInAmt = Lib.getAssetAmt(outValueAddFees,trendTokenPrice); // $10, assume Trend price is $2
        price = priceToken;

    }


    /**
     * @notice Allows for the deposit of Trend Tokens to redeem an underlying asset of redeemers choice
     * @param _redeemBep20 The token the redeemer wishes to redeem
     * @param _redeemAmt The amount of underlying to be redeemed
     * @return The amount of underlying sent to redeemer
     */
    function redeemFresh(IERC20 _redeemBep20, uint _redeemAmt, uint _maxTrendTokenIn) internal pausedTrendToken returns(uint) { // change back to external
        
        // Requirements
        compTT.depositOrRedeemAllowed(address(this), _redeemAmt); // above zero, unpaused, trend token listed
        IVBep20 dToken = IVBep20(compTT.returnDToken(address(_redeemBep20))); 
        checkActiveToken(dToken); // checks this Trend Token enabled dToken (must be listed)

        (uint price, 
        uint trendTokenPrice,, 
        uint trendTokenInAmt, 
        uint protocolFeePerc, 
        int feeOrReward) = trendTokenInCalculations(_redeemBep20, dToken, _redeemAmt);

        // Receive Trend Tokens and send Performance Fee
        //require(trendTokenInAmt <= _maxTrendTokenIn, "!maxIn");
        requireUnderAmount(trendTokenInAmt,_maxTrendTokenIn,"!maxIn");
        trendToken.transfersFrom(msg.sender, address(this), trendTokenInAmt); 

        // Add Trend Tokens to rerve and burn the rest
        uint trendTokenFee = Lib.getValue(trendTokenInAmt,protocolFeePerc);
        uint trendTokenToReservesPerc = Lib.getValue(trendTokenFee,uint(1e18).sub(trendTokenRedeemBurn));
        trendToken.burn(trendTokenInAmt.sub(trendTokenToReservesPerc));

        // Redeem and send underlying
        sendUnderlyingOut(_redeemBep20, dToken, _redeemAmt);

        // Events
        emit Redeem(price, trendTokenPrice, trendToken.totalSupply(), protocolFeePerc, feeOrReward,trendTokenFee);

        return trendTokenInAmt;

    }


    /**
     * @notice External function redeemer interacts with to redeem Trend Tokens
     * @dev Disabled if Trend Token is paused
     */
    function redeem(IERC20 _redeemBep20, uint _redeemAmt, uint _maxTrendTokenIn, uint _deadline) external nonReentrant  ensureDeadline(_deadline) {
        redeemFresh(_redeemBep20, _redeemAmt, _maxTrendTokenIn);
    }


    // --------------- TRADE FUNCTIONALITY ----------------- // 

    /**
     * @notice Calculates the value of underlying to send back to the user
     */
    function tradeInfo(IERC20[] memory tokenInOut, IVBep20[] memory dTokensInOut, uint valueIn) internal view returns(uint valOutAfterBuy)  {

        (address[] memory dTokens,, // dToken (not underlying)
        uint[] memory conVals,
        uint[] memory colVals,
        uint netEquity) = storedEquity();

        require(netEquity>0 && address(dTokensInOut[0]) != address(0) && address(dTokensInOut[1]) != address(0) &&
               dTokensInOut[0] != dTokensInOut[1] &&  tokenInOut.length == 2, "equity !> 0");

        int[] memory priorPostDeltaIn = new int[](2);
        int[] memory priorPostDeltaOut = new int[](2);
        uint[] memory tokenEquityInOut = new uint[](2);
        uint[] memory desiredAllos = new uint[](2);

        for (uint i=0; i < dTokens.length; i++) {

            if (IVBep20(dTokens[i]) == dTokensInOut[0]) { // dTokenIn: sell

                tokenEquityInOut[0] = conVals[i].add(colVals[i]);
                desiredAllos[0] = desiredAllocations[i];

            } else if (IVBep20(dTokens[i]) == dTokensInOut[1]) { // dTokenOut: buy

                tokenEquityInOut[1] = conVals[i].add(colVals[i]);
                desiredAllos[1] = desiredAllocations[i];
                
            }
        
        }

        uint equityAfterSell = netEquity.add(valueIn); // 30 + 1 = 31
        priorPostDeltaIn[0] = int(desiredAllos[0]).sub(int(Lib.getAssetAmt(tokenEquityInOut[0],netEquity))); // 1 - 13/30 = 56%
        priorPostDeltaIn[1] = int(desiredAllos[0]).sub(int(Lib.getAssetAmt(tokenEquityInOut[0].add(valueIn),equityAfterSell))); // 1 - (13+1)/ 31 = 54%

                                                            // BNB, 1000000000000000000, 560000000000000000, 530000000000000000, 10000000000000000000000000
                                                            // output ==> 1000000000000000000
        uint valAfterSell = incentiveModel.valueOutAfterSell(tokenInOut[0], valueIn, priorPostDeltaIn[0], priorPostDeltaIn[1], xtt.balanceOf(msg.sender));

        priorPostDeltaOut[0] = int(desiredAllos[1]).sub(int(Lib.getAssetAmt(tokenEquityInOut[1],equityAfterSell))); // 0 - 17/31 = -55%
        priorPostDeltaOut[1] = int(desiredAllos[1]).sub(int(Lib.getAssetAmt(tokenEquityInOut[1].sub(valAfterSell),equityAfterSell.sub(valAfterSell)))); // 0 - (17-1)/(31-1) = -47%
        
                                                            // BUSD, 1000000000000000000, -550000000000000000, -470000000000000000
        valOutAfterBuy = incentiveModel.valueOutAfterBuy(tokenInOut[1], valAfterSell, priorPostDeltaOut[0], priorPostDeltaOut[1]);

    }

    
    /**
     * @notice Executes desired trade
     * @param tokenInOut List of [tokenSell, tokenBuy]
     * @param sellAmt The amount of tokenSell to sell
     */
    function executeTrade(IERC20[] memory tokenInOut, uint sellAmt, uint _minOut, uint _deadline) internal pausedTrendToken  ensureDeadline(_deadline) {
        compTT.tradeAllowed(address(this), sellAmt); 
        
        IVBep20[] memory dTokensInOut = new IVBep20[](2);
        dTokensInOut[0] = IVBep20(compTT.returnDToken(address(tokenInOut[0]))); 
        dTokensInOut[1] = IVBep20(compTT.returnDToken(address(tokenInOut[1]))); 

        uint valueIn = Lib.getValue(sellAmt,priceBEP20(dTokensInOut[0]));
        uint valOutAfterBuy = tradeInfo(tokenInOut,dTokensInOut,valueIn);
        uint outUnderlying = Lib.getAssetAmt(valOutAfterBuy,priceBEP20(dTokensInOut[1]));
        require(outUnderlying >= _minOut,"!minOut");
        
        sendUnderlyingOut(tokenInOut[1], dTokensInOut[1], outUnderlying);

        emit ExecuteTrade(sellAmt, valueIn, valOutAfterBuy, outUnderlying);
    }

    /**
     * @notice Allows user to swap one underlying (BUSD) for another (BTCB)
     */
    function swapExactTokensForTokens(uint sellAmt, uint minOut, IERC20[] calldata tokenInOut, uint _deadline) external nonReentrant {
        tokenInOut[0].safeTransferFrom(msg.sender, address(this), sellAmt);
        executeTrade(tokenInOut,sellAmt,minOut,_deadline);
    }


    /**
     * @notice Allows user to swap BNB for an underlying (BUSD)
     */
    function swapExactETHForTokens(uint minOut, IERC20[] calldata tokenInOut, uint _deadline) external nonReentrant payable {
        require(tokenInOut[0] == wbnb, "input must be BNB");
        executeTrade(tokenInOut,msg.value,minOut,_deadline);
    }


    // ----------------- SUPPLY REBLANCE ------------------- //
    /**
     * @notice Allows the public to supply or redeem portfolio tokens according to contractFactor
     */


    /**
     * @notice Returns the underlying token for inputted dToken
     * @dev If dToken is dBNB then wbnb will be returned
     */
    function returnUnderlying(IVBep20 dToken) internal view returns(IERC20 addr) {
        addr = wbnb;
        if (dToken != dBNB) {
            addr = IERC20(dToken.underlying());
        }
    }


    /**
     * @notice Supplies or redeems dToken according to contractFactor
     * @dev If dToken is not in dTokens, it will be skipped
     * @param dToken The dToken to be supplied/redeemed
     * @param _contractFactor The percentage of token equity desired to be in contract (not supplied)
     */
    function singleSupplyAndRedeemRebalance(IVBep20 dToken, uint _contractFactor) internal {

        (address[] memory dTokens,
        uint[] memory prices,
        uint[] memory conVals,
        uint[] memory colVals,) = storedEquity();

        for (uint i=0; i < dTokens.length; i++) {

            if (address(dToken) == dTokens[i]) {

                uint tokenEquity = conVals[i].add(colVals[i]);

                if (tokenEquity > 0) {

                    IERC20 underlying = returnUnderlying(dToken);
                    uint currentContractFactor = Lib.getAssetAmt(conVals[i], tokenEquity);

                    // requires supplying (too much contract balance) 
                    if (currentContractFactor > _contractFactor) {

                        uint supplyDelta = currentContractFactor.sub(_contractFactor);
                        uint supplyValue = Lib.getValue(supplyDelta, tokenEquity);
                        uint supplyAmt = Lib.getAssetAmt(supplyValue,prices[i]);
                        collateralSupply(underlying, dToken, supplyAmt); 


                    } 

                    // requires redeeming (not enough contract balance)
                    else if (currentContractFactor < _contractFactor) {

                        uint redeemDelta = _contractFactor.sub(currentContractFactor);
                        uint redeemValue = Lib.getValue(redeemDelta,tokenEquity);
                        uint redeemAmt = Lib.getAssetAmt(redeemValue,prices[i]);
                        collateralRedeem(underlying, dToken, redeemAmt); 

                    }
                }
            }
        }
    }
    


    /** 
     * @notice Allows the public to rebalance borrows
     * @dev Repays or borrows assets as needed, may redeem if required
     * input _tokens List of underlying tokens to rebalance
     */
    function publicSupplyAndRedeemRebalance(address[] calldata _tokens) external pausedTrendToken {

        bool allowedDualPools = compTT.trendTokenAllowedDualPools(address(this));

        if (!allowedDualPools) {
            setContractFactor(1e18);
        }

        for (uint i=0; i < _tokens.length; i++) {
            IVBep20 dToken = IVBep20(compTT.returnDToken(address(_tokens[i])));
            require(tokenEntered(dToken), "!entered");
            singleSupplyAndRedeemRebalance(dToken, contractFactor);
        }
    }
    


}

