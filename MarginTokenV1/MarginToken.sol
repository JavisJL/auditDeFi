// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;

import "./TrendTokenTkn.sol";
import "./Venus.sol";
import "./CompTT.sol";
import "./ICompTT.sol";
import "./MarginTokenStorage.sol";
import "./IncentiveModelSimple.sol";
import "./SignedSafeMath.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";


// ---------- TESTING ---------------- // 

// recent Margin Token deployement: 0xd83309194334eE4DBda11bb0eb06039b5EDB8604

// ---- SETUP --- // 
// MARGINBOT DEPLOY:  0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0xABB5D41B22A1E9d488c9CAF7AC445BA0FEbc1e6f
// SUPPORT IN COMPTT
// PORTFOLIO UPDATE:  [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd],[1000000000000000000],[0],[0]
// INCENTIVE MODEL:   0x0000000000000000000000000000000000000000,0xe24FD0Ba7245c34a82e1D9517CE226307129A599

// ---- TESTING (single token) ---- //
// despositBNB: 10000000000000000   /  0,10000000000000000000000
// approve Trend5 for Portfolio
// redeem(BNB)

// ---- TESTING (two tokens) ---- //
// PORTFOLIO UPDATE:  [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0xA808e341e8e723DC6BA0Bb5204Bafc2330d7B8e4],[1000000000000000000,0],[0,0],[0,0]
// web3 approve BTCB for MarginToken portfolio
// deposit(): 0xA808e341e8e723DC6BA0Bb5204Bafc2330d7B8e4,100000000000000,0,10000000000000000000000


// ----- TESTING (supply to Venus) ----- // 
// configure on CompTT to support venus and borrow for this Trend Token and desired underlying
// supply BNB _updatePortfolio(): [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd],[100000000000000000],[900000000000000000],[0]
// _updatePortfolio(): [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0xA808e341e8e723DC6BA0Bb5204Bafc2330d7B8e4],[1000000000000000000,0],[0,0],[0,0]
// _updatePortfolio(): [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0xA808e341e8e723DC6BA0Bb5204Bafc2330d7B8e4],[0,0],[1000000000000000000,0],[0,0]





// ** complete
// * in progress
// ! skip

// ---- To Do Mar -------- // 
// 1) Add borrow capability
//      - check borrowFactor when borrowing or redeem assets from Venus
// 2) Replace reliance on Dualpools with Venus
//      - how to handle what tokens that can be added? Maybe in CompTT
// 3) Could remove referral reward to save bytes?
// 4)** Subtract borrowed amount from Trend Token price
// 5) Simplify or remove singleSupplyAndRedeemRebalance()
//      Can be done off chain
// 6) Remove ability for manager to supply or redeem as much as possible 
// 7) Ensure enough in contract (not col) to repay loan at any time! 
// 8) Can remove _setContractFactor or replace with something else
// 9) Change requirements when sum of allocations must be between 1-1.5x, add some other conditions
//      _setDesiredAllocationsFresh --> ([longs], usdtBorrow)
//      sum(longs) - usdtBorrow = 1.0 
//      if usdtBorrow > 0, then long USDT must be 0
// 10) Maybe rely on Venus' Oracle? Or compare within a a range? Adapt within Oracle? 
// 11) Allow for tokens outside of Venus, but adapt margin based on this? 
//      [venusLong], [otherLong], venusBorrow
// 12) Allow CompTT to set possible borrowTokens, and allow MarginToken to update one token at a time
// 13) Reduce contract size
//      a) remove referral
//      b) replace contractFactor with maxBorrowFactor, maxLeverage, and borrowToken
//      c) simplify fee model: fees to reserves then one burn function? 
//      d) remove singleSupplyAndRedeemRebalance() and publicSupplyAndRedeemRebalance(), _setReferralReward()
// 14) Need loop through portfolio and get contract, vTokenX, vTokenY, etc
// 15) Move locked to state in CompTT for TRend Token
//      - frees up space and simplifies MarginToken
// 16) Allow manager to make Venus external or not
//      - if not public, then restricted to trading bot! 
// 17) remove Trend Token burn! 
//      - save gas
//      - removed in redeem function, public variable, and adjustable

// Exnternal Funcitons
// 1. change getting prices from Trend Tokens to CompTT


contract MarginToken is VenusIntegration, MarginTokenStorage { 

    using SignedSafeMath for int;
    using SafeERC20 for IERC20;


    /**
     * testnet: 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x7b280178C3BC73726FaFFaF90d04aaf81FDf228e
     * mainnet:
     */
    constructor(address _wbnb, address _compTT) 
                VenusIntegration(_wbnb,_compTT) public {
        compTT = ICompTT(_compTT);
        manager = msg.sender;
        tradingBot = msg.sender;
        //feeRecipient = msg.sender;
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
     * @dev Permission from compTT due to high security
     */
    modifier requireUnlocked() {
        require(!compTT.isLockedTrendToken(address(this)),"!locked");
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
     * //param _compVenus The Dual Pool comptroller that governs all dTokens for lend/redeem actions
     * @param _incentiveModel View functions that dictate the deposit and redeem rewarrds 
     */
    function _updateCompAndModels(address _compTT, IIncentiveModelSimple _incentiveModel) onlyManager requireUnlocked external {
        
        address oldCompTT = address(compTT);
        if (_compTT != address(0)) {
            require(ICompTT(_compTT).trendTokenActiveStatus(address(this)),"Inactive TT." );
            compTT = ICompTT(_compTT);
            //emit NewCompTT(oldCompTT, address(compTT));
        }

        address oldIncentive = address(incentiveModel);
        if (address(_incentiveModel) != address(0)) {

            incentiveModel = _incentiveModel;
            //emit NewIncentiveModel(oldIncentive, address(incentiveModel));
        }

        emit UpdateCompAndModels(oldCompTT, address(compTT), oldIncentive, address(incentiveModel));
 
    }


    /**
     * @notice Allows manager to change manager, fee recipient, and trading bot
     * @dev If want unchanged, set parameter to zero address
     * @param _manager Ability to set fees, factors, etc
     * @param _tradingBot Ability to set portfolios, allocations, and some Dual Pool actions
     */
    function _updateManagerAndBot(address payable _manager, address _tradingBot) onlyManager requireUnlocked external {

        address oldManager = address(manager);
        if (_manager != address(0)) {
            manager = _manager;
            //emit NewManager(oldManager, address(manager));
        }

        address oldTradingBot = address(tradingBot);
        if (_tradingBot != address(0)) {
            tradingBot = _tradingBot;
            //emit NewTradingBot(oldTradingBot, address(tradingBot));
        }

        emit UpdateManagerAndBot(oldManager,  address(manager), oldTradingBot,  address(tradingBot));

    }
    

    // -------  MANAGER: UPDATE FEES/REWARDS ------- // 

    
    /** 
     * @notice Updates performance fee 
     * @dev Must send performance fee first 
     * param _performanceFee Percentage of new trend token ATH gains that goes to reserves
     */
    function _updatePerformanceFee(uint _performanceFee) onlyManager requireUnlocked external {

        // ensure desired performance fee is under maxPerformFee
        (,uint maxPerformFee) = compTT.trendTokenMaxFees(address(this));
        requireUnderAmount(_performanceFee, maxPerformFee, "!performanceFee");

        // redeem any outstanding performance fees
        (uint trendTokenPrice, uint mintMBNB) = trendTokenToUSD(); 
        sendPerformanceFee(mintMBNB, trendTokenPrice);

        // emit event
        uint oldFee = performanceFee;
        performanceFee = _performanceFee;
        emit NewPerformanceFee(oldFee, performanceFee);
    }
    

    // -------   MANAGER: UPDATE VALUES ------- // 


    /**
     * @notice Sets the minimum value of a token before it can be removed from the portfolio
     */
    function _updateMaxDisableAndSupply(uint _maxDisableTokenValue, uint _maxSupply) onlyManager requireUnlocked external {

        // max disable values
        uint oldMaxDisableValue = maxDisableTokenValue;
        if (_maxDisableTokenValue>0) {

            // make sure desired maxDisableValue is below limit from compTT
            (uint maxDisableValue,,) =  compTT.trendTokenMaxValues(address(this));
            requireUnderAmount(_maxDisableTokenValue, maxDisableValue, "!maxDisableValue");
            
            maxDisableTokenValue = _maxDisableTokenValue;
            //emit MaxDisableValue(oldValue, maxDisableTokenValue);
        }

        uint oldMaxSupply = maxSupply;
        if (_maxSupply>0) {
            maxSupply = _maxSupply;
            //emit SetMaxSupply(oldSupply, maxSupply);
        }

        emit UpdateMaxDisableAndSupply(oldMaxDisableValue, maxDisableTokenValue, oldMaxSupply, maxSupply);
    }



    // -------- MANAGER: DUAL POOL INTERACTIONS --------------- // 


    // ------- TRADING BOT: UPDATE BOOL --------- //


    /**
     * @notice Allows trading bot to change if Venus is open to public
     * @dev if venusOpen is true, public may rebalance 
     */
    function _updateVenusAndPauseState(bool _isVenusOpen, bool _pauseTrendToken) onlyTradingBot external {
       
       // changes venus open state
        bool oldVenus = venusOpen;
        venusOpen = _isVenusOpen;
        //emit VenusOpen(oldState, venusOpen);

        // changes pause state
        bool oldStatePause = trendTokenPaused;
        trendTokenPaused = _pauseTrendToken;
        //emit PauseTrendToken(oldStatePause, trendTokenPaused);

        emit UpdateVenusAndPauseState(oldVenus, venusOpen, oldStatePause, trendTokenPaused);
    }


    /**
     * @notice Allows trading bot to pause deposits of underlying
     * @dev Used when wanting to disable a token (before disable to prevent more deposits)
     */
    function _depositsDisabled(address underlying, bool _isEnabled) onlyTradingBot external {
        bool oldState = depositsDisabled[underlying];
        depositsDisabled[underlying] = _isEnabled;
        emit DepositsDisabled(underlying, oldState, depositsDisabled[underlying] );
    }



    // ------- TRADING BOT: UPDATE PORTFOLIO --------- //)


    /** 
     * @notice Allows tradingBot to update new portfolio and desired contract, collatera, and borrow allocations
     * @dev All remove tokens (in current portfolio but not _newPortfolio) must have low balances
     * @dev To do this, first _setDesiredAllocations() to 0/0/0 for each token wishing to be removed in this update
     * @dev Tradingbot may need to first add new tokens, set old tokens to 0%,0%,0% before removing the old tokens
     * @dev All _tokens must be supported by comptroller for this trend token
     * @dev All removed tokens (in old portfolio but not new) must have balance values below maxDisableTokenValue
     */
    function _updatePortfolioAndAllocations(address[] calldata _newPortfolio, uint[] calldata _con, uint[] calldata _col, uint[] calldata _bor) onlyTradingBot external {
        

        // checks if any tokens from portfolioTokens have been removed
        // applies conditions to these tokens and disables collateral
        for (uint i=0; i<portfolioTokens.length; i++) {

            address oldToken = portfolioTokens[i];
            bool tokenInNewPortfolio = Lib.addressInList(oldToken, _newPortfolio);

            // if token not in new portfolio
            if (!tokenInNewPortfolio) {
                
                // requires low con+col+bor balance to remove from portfolio
                (,,uint con, uint col, uint bor,) = tokenInfoVal(IERC20(oldToken));
                requireUnderAmount(con.add(col).add(bor), maxDisableTokenValue, "!maxDisableTokenValue.");

                // disable collateral if entered
                IVBep20 vToken = IVBep20(compTT.returnVToken(oldToken));
                bool isEntered = tokenEntered(vToken);
                if (isEntered) {
                    disableCol(vToken);
                }

            }

        }

        // sets net portfolio
        portfolioTokens = _newPortfolio;

        // updates positions based on new portfolio
        // variety of conditions must be met
        _setDesiredAllocationsFresh(_con, _col, _bor);
    }




    /**
     * @notice Allows tradingBot to change contract, collateral, and borrow values without changing portfolio
     * @dev Most common function used by tradingBot (less frequently add or remove a token)
     * @param _con The desired percent of equity in contract
     * @param _col The desired percent of equity in venus collateral
     * @param _bor The desired percent of equity in venus borrow
     */
    function _setDesiredAllocations(uint[] calldata _con, uint[] calldata _col, uint[] calldata _bor) onlyTradingBot external {
        _setDesiredAllocationsFresh(_con, _col, _bor);
    }


    /**
     * @notice Safely changes contract, collateral, and borrow allocations without changing portfolio
     * @dev Ensures the desired allocations are within margin limits and required permission from comptroller
     * @dev If tradingBot would like to disable token, update positions with 0% for token after positions are empty
     * @param _con The desired percent of equity in contract
     * @param _col The desired percent of equity in venus collateral
     * @param _bor The desired percent of equity in venus borrow
     * param _supplyOrBorrowAmounts The amount (in qty) desired to be supplied or borrowed
     */
    function _setDesiredAllocationsFresh(uint[] memory _con, uint[] memory _col, uint[] memory _bor) internal {
        
        // require all lengths are the same as the portfolioTokens 
        require(portfolioTokens.length==_con.length && _con.length==_col.length && _col.length==_bor.length ,"!lengths.");

        uint conTotal = 0;
        uint colTotal = 0;
        uint borTotal = 0;
        uint estBorrowableTotal = 0;

        for (uint i=0; i<portfolioTokens.length; i++) {

            //require(incentiveModel.portfolioTokens[i]);

            address vToken = compTT.returnVToken(portfolioTokens[i]); // may be zero address

            // adds contract totals
            conTotal = conTotal.add(_con[i]);

            // checks supply conditions and enables/disables vToken
            bool isSupply = false;
            bool isTokenEntered = tokenEntered(IVBep20(vToken));
            if (_col[i] > 0) {

                // vToken must be supported
                ensureNonzeroAddress(vToken);

                // enter vToken if it isnt already
                if (!isTokenEntered) {
                    enableSingleCol(vToken);
                }

                // set supply status and add to colTotal
                isSupply = true;
                colTotal = colTotal.add(_col[i]);

            // disable collateral if conditions are met
            }

            // checks borrow conditions
            bool isBorrow = false;
            if (_bor[i] > 0) {
                
                // vToken must be supported
                ensureNonzeroAddress(vToken);

                // set borrow status and add to borTotal
                isBorrow = true;
                borTotal = borTotal.add(_bor[i]);

                // add collateral to estimated liquidity 'estBorrow = estBorrow + col*factor/1e18
                estBorrowableTotal = estBorrowableTotal.add(_col[i].mul(collateralFactor(IVBep20(vToken))).div(1e18)); 
                
            }

            // disables collateral if no desired or current borrow or supply (and vToken exists)
            if (vToken != address(0) && !isBorrow && !isSupply) {
                (,,, uint col, uint bor,) = tokenInfoVal(IERC20(portfolioTokens[i]));
                if (col <= maxDisableTokenValue && bor <= maxDisableTokenValue) {
                    disableCol(IVBep20(vToken));
                }
            }
        
            // ensure permission from comptroller
            bool permission = compTT.permissionPortfolio(address(this), portfolioTokens[i], isSupply, isBorrow);
            require(permission, "!permission.");

        }


        // ensures net equity doesnt exceed 100%
        require(conTotal.add(colTotal).sub(borTotal) == 1e18, "!=100%");

        // ensure desired borrow does not exceed maxBorrowFactor ('borrow'/'borrowable')
        uint estBorrowFactor = 0;
        if (estBorrowableTotal > 0) {
            estBorrowFactor = borTotal.mul(1e18).div(estBorrowableTotal);
        }
        (,uint maxBorrowFactor,) = compTT.trendTokenMaxValues(address(this));
        requireUnderAmount(estBorrowFactor, maxBorrowFactor, "!BorrowFactor.");

        // set inputs to state variables
        contractAllo = _con;
        collateralAllo = _col;
        borrowAllo = _bor;

    }



    // -------------------- MANAGER: REDEEM & REDUCE TREND TOKENS ------------------- // 
    /**
     * @notice Allows manager to redeem Trend Tokens to fee recipient OR redeem for BNB --> XTT --> burn
     */


    /**
     * @notice Mints and sends any performance fees (in Trend Tokens) to this Trend Token contract
     */
    function _redeemPerformanceFee() onlyManager external {
        (uint trendTokenPrice, uint mintMBNB) = trendTokenToUSD(); 
        sendPerformanceFee(mintMBNB, trendTokenPrice);
    }


    /** 
     * @notice Allows manager to redeem Trend Tokens and XVS to manager
     * @param claimXVS Claims the XVS from Venus to this contract
     * @param redeemAmountXVS Sends this amount of XVS in the contract to manager
     * @param redeemAmtTrendToken Sends this amount of Trend Token in the contract to manager
     */
    function _claimFeesAndXVS(bool claimXVS, uint redeemAmountXVS, uint redeemAmtTrendToken) onlyManager external  {

        if (claimXVS) {
            ICompVenus(compTT.compVenus()).claimVenus(address(this));
        }

        if (redeemAmountXVS > 0) {
            requireUnderAmount(redeemAmountXVS, balanceXVS(),"!balXDP");
            xvs.safeTransfer(manager,redeemAmountXVS);
        }
        
        if (redeemAmtTrendToken > 0) {
            uint currentBalance = trendToken.balanceOf(address(this));
            requireUnderAmount(redeemAmtTrendToken, currentBalance, "!balanceTT");
            IERC20(address(trendToken)).safeTransfer(manager,redeemAmtTrendToken);
        }
    }


    // ------- TRADING BOT: REDEEM & DISTRIBUTE XDP --------- //

    /** 
     * @notice Claims XDP from Dual Pools and sends _redeemAmountXDP to Fee Recipoient
     * @dev The remainder of XDP stays in the pool 
     
    function _redeemXVStoManager(bool claim, uint _redeemAmountXVS) onlyManager external  {
        if (claim) {
            ICompVenus(compTT.compVenus()).claimVenus(address(this));
        }
        requireUnderAmount(_redeemAmountXVS, balanceXVS(),"!balXDP");
        xvs.safeTransfer(manager,_redeemAmountXVS);
    }*/


    // ------ EXTERNAL VIEW FUNCTIONS ------------- //


    /**
     * @notice Returns the underlying price of dToken externally
     */
    //function priceExt(IVBep20 _vToken) external view returns(uint) {
    //    return compTT.priceBEP20(_vToken);
    //}


    /**
     * @notice Returns the price of trend token (in USD) externally
     
    function trendTokenToUSDext() external view returns(uint, uint) {
        return trendTokenToUSD();
    }*/


    /** 
     * @param trendTokenIn True if trendTokenInCalculations else trendTokenOutCalculations
     * @return (uint price, uint trendTokenPrice, uint mintMBNB, uint trendTokenAmt, uint protocolFeePerc, int feeOrReward)
     
    function trendTokenExternal(IERC20 _bep20, uint _amount, bool trendTokenIn) 
        external view returns(uint, uint, uint, uint, uint, int)  {
            if (trendTokenIn) {
                return trendTokenInCalculations(_bep20, _amount);
            } else {
                return trendTokenOutCalculations(_bep20, _amount);
            }
    }*/ 


    /**
     * @notice External function for stored equity
     */
    function storedEquityExternal() external view returns(address[] memory,uint[] memory,uint[] memory,uint[] memory,uint[] memory,uint) {
        return storedEquity();
    }


    /**
     * @notice Fetches (int priorDelta, int postDelta, uint priceToken, uint equity) for given token deposit or redeem
     
    function tokenInfoExternal(IERC20 _token, uint depositAmt, uint redeemAmt) external view returns(int, int, uint, uint) {
        return tokenInfo(_token, depositAmt, redeemAmt);
    }*/ 


    /**
     * @notice Calculates the value out after selling tokenInOut[0] for tokenInOut[1]
     
    function swapInfoExt(IERC20[] calldata tokenInOut, uint valueIn) external view returns(uint) {
        return swapInfo(tokenInOut, valueIn);
    }*/


    /**
     * @notice Gives the values for a trend token
     * @return (address(_token), price, collateralVal, contractVal, borrowVal, tokenNetEquity)
     
    function tokenInfoValExt(IERC20 _token) external view returns(address, uint, uint, uint, uint, int) {
        return tokenInfoVal(_token);
    }*/



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
    function balanceXVS() internal view returns(uint balance) {
        balance = xvs.balanceOf(address(this));
    }


    /**
     * @notice Fetches this Trend Tokens balance of an underlying token
     * @param _token The dToken to get balance of 
     * @return The balance of _token
     */
    function contractBal(IERC20 _token) internal view returns(uint) {
        if (_token == wbnb) { 
            return address(this).balance;
        } else { 
            return _token.balanceOf(address(this));
        }
    }


    /**
     * @notice Fetches key information for a single token
     * @dev Used in storedEquity() and _updatePortfolio()
    */
    function tokenInfoVal(IERC20 _token) internal view returns(address, uint, uint, uint, uint, int) {

        // empty value sums
        uint assetValSum = 0;
        uint borrowValSum = 0;
            
        // store prices
        uint price = compTT.priceBEP20(_token);
        
        // store conVals
        uint contractVal = Lib.getValue(contractBal(_token),price);
        uint collateralVal;
        uint borrowVal;

        // store colVals and borVals
        address vToken = compTT.returnVToken(address(_token));
        if (vToken != address(0)) {

            // get vToken data
            (uint tokenBal, uint borrowBal, uint rate) = screenshot(IVBep20(vToken));

            // collateral values
            uint collateralAmt = Lib.getValue(tokenBal,rate);
            collateralVal = Lib.getValue(collateralAmt,price);

            // borrow values
            borrowVal = Lib.getValue(borrowBal,price);

            // add contract and venus values to totals
            assetValSum = assetValSum.add(contractVal).add(collateralVal);
            borrowValSum = borrowValSum.add(borrowVal);

        } else {

            // add contract values to totals
            assetValSum = assetValSum.add(contractVal);

        }

        int tokenNetEquity = int(assetValSum).sub(int(borrowValSum));

        return (address(_token), price, contractVal, collateralVal, borrowVal, tokenNetEquity);    

    }



    // actually can loop through general list
    // the order general list can roughly match dTokens? 
    //      could be a headache to ensure same match, so make a robust system
    // 
    function storedEquity() internal view returns(address[] memory,uint[] memory,uint[] memory,uint[] memory,uint[] memory,uint) {  // returns current balances (uint)

        // creates return variables
        address[] memory tokens = portfolioTokens;
        uint[] memory prices = new uint[](tokens.length);
        uint[] memory conVals = new uint[](tokens.length);
        uint[] memory colVals = new uint[](tokens.length);
        uint[] memory borVals = new uint[](tokens.length);
        uint assetVal;
        uint borVal;

        for (uint i = 0; i < tokens.length; i++) {
  
            int tokenEquity;
            (tokens[i], 
            prices[i], 
            conVals[i], 
            colVals[i], 
            borVals[i], 
            tokenEquity) = tokenInfoVal(IERC20(tokens[i]));

            // add token equity to total (wait... 
            if (tokenEquity>=0) {
                assetVal = assetVal.add(uint(tokenEquity));
            } else {
                uint borrowValue = uint(-tokenEquity);
                borVal = borVal.add(borrowValue);
            }   

        }

        // calculate net equity 'equity = assets - borrows'
        // assumes will always be positive
        uint netEquity = assetVal.sub(borVal);

        return (tokens,prices,conVals,colVals,borVals,netEquity);

    }


    /**
     * @notice Publicly returns this Trend Tokens price in USD
     */
    function trendTokenToUSD() internal view returns(uint,uint) {
        (,,,,,uint equity) = storedEquity();
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


    function desiredAllocation(uint tokenIndex) internal view returns(int) {
        return int(contractAllo[tokenIndex]).add(int(collateralAllo[tokenIndex])).sub(int(borrowAllo[tokenIndex]));
    }



    /**
     * @notice Fetches data required for deposit/redeem incentives for a specific token
     * @dev Used by trendTokenOutCalculations() and trendTokenInCalculations() for incentive model 
     * @param _token The spefific token to get information on (e.g 0xbb..)
     * @return allocationDelata Difference between desired and current percent allocations
     *         price The price of _token, 
     *         equity The total Trend Token equity in contract and Venus
     *         Positive allocation delta if desire more of the asset
     */
    function tokenInfo(IERC20 _token, uint depositAmt, uint redeemAmt) internal view returns(int priorDelta, int postDelta, uint price, uint equity) {
        require(Lib.addressInList(address(_token),portfolioTokens),"!portfolio.");
        
        (address[] memory tokens, // 0x00 in placeholder for all tokens except _dToken
        uint[] memory prices,
        uint[] memory conVals,
        uint[] memory colVals,
        uint[] memory borVals,
        uint netEquity) = storedEquity(); 

        for (uint i=0; i < tokens.length; i++) {

            if (tokens[i] == address(_token)) {

                price = prices[i];
                equity = netEquity;
                uint depositVal = Lib.getValue(depositAmt,price);
                uint redeemVal = Lib.getValue(redeemAmt,price);

                // calculates desired % allocation of netEquity 'contract + collateral - borrow' => can be negative if borrow
                //int desiredAllocations = desiredAllocation(i);

                if (netEquity>0) {

                    int tokenEquity = int(conVals[i]).add(int(colVals[i])).sub(int(borVals[i]));
                    int priorAllocations = tokenEquity.mul(1e18).div(int(netEquity));
                    priorDelta = desiredAllocation(i).sub(priorAllocations);

                    // require some settings
                    //requireUnderAmount(supplyTrendToken , maxSupply,"!maxSupply"); // did not edit
                    require(tokenEquity > int(redeemVal) && netEquity > redeemVal,"insufficient redeem");

                    int tokenEquityPost = tokenEquity.add(int(depositVal)).sub(int(redeemVal));
                    int postAllocation = tokenEquityPost.mul(1e18).div(int(netEquity.add(depositVal).sub(redeemVal)));
                    postDelta = desiredAllocation(i).sub(int(postAllocation));

                // starting conditions
                } else { 

                    require(redeemVal==0,"redeem=0.");
                    priorDelta = desiredAllocation(i);
                    postDelta = int(1e18);
                     
                }
                
            }
        
        }

        require(price>0,"!tokenInPortfolio");

    }





    // ------------ DEPOSIT FUNCTION -------------- //
    /**
     * @notice Allows users to supply any asset in the portfolio for Trend Tokens
     * @dev Rewards for supplying assets the Trend Token desires, fees for supplying other assets
     */


    /**
     * @notice Sends referralReward% of protocolFeePerc to referral and referralReward% to referrer
     
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

    }*/


    /**
     * @notice Calculates the fees and trend token amounts out upon deposit
     * @dev Calls the Incentive Model contract to fetch base protocol fee and fee/reward incentive
     */
    function trendTokenOutCalculations(IERC20 _depositBep20, uint _sellAmtBEP20) 
        internal view returns(uint price, uint trendTokenPrice, uint mintMBNB, uint trendTokenAmt, uint protocolFeePerc, int feeOrReward)  {

        (int priorDelta, int postDelta, uint priceToken, uint equity) = tokenInfo(_depositBep20,_sellAmtBEP20,0);
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
    function depositFresh(IERC20 _depositBep20, uint _sellAmtBEP20, uint _minTrendTokenOut) internal pausedTrendToken returns(uint)  {
        
        // Requirements
        compTT.permissionDepositTT(address(this),address(_depositBep20),_sellAmtBEP20); // above zero, unpaused, trend token active
        require(!depositsDisabled[address(_depositBep20)], "deposits disabled");  // checks deposits arent disabled

        // Calculate prices, fees, and amounts
        (uint priceToken,
        uint trendTokenPrice,, 
        uint trendTokenAmt, 
        uint protocolFeePerc, 
        int feeOrReward) = trendTokenOutCalculations(_depositBep20, _sellAmtBEP20);

        // Send fees and Trend Token to user
        //sendPerformanceFee(mintTrendTokenAmt,trendTokenPrice); // MAYBE REMOVE FOR TAX REASONS? 
        //require(trendTokenAmt >= _minTrendTokenOut,"!minOut");
        requireUnderAmount(_minTrendTokenOut, trendTokenAmt,"!minOut");
        trendToken.mint(msg.sender, trendTokenAmt);// mint and send Margin Token to Trader (after fees)

        // Require max supply isnt exceeded
        uint supplyTrendToken = trendToken.totalSupply();
        requireUnderAmount(supplyTrendToken , maxSupply,"!maxSupply");
        //require(supplyTrendToken <= maxSupply,"!maxSupply.");

        // Sends 40/40 of protocolFeePerc to referrer/referral instead of going to Pool
        /**
        if (_referrer != address(0)) {
            distributeReferralReward(_depositBep20, _sellAmtBEP20, protocolFeePerc, _referrer);
        }*/

        emit Deposit(priceToken, trendTokenPrice, supplyTrendToken, protocolFeePerc, feeOrReward);

        return trendTokenAmt;

    }


    /**
    *   Payable function for buying Trend Tokens with BNB
    */
    function depositBNB(uint _minTrendTokenOut, uint _deadline) external nonReentrant ensureDeadline(_deadline) payable {
        depositFresh(wbnb, msg.value, _minTrendTokenOut);
    }


    /**
    *   Payable function for buying Trend Tokens with BNB
    */
    function deposit(IERC20 _depositBep20, uint _sellAmtBEP20, uint _minTrendTokenOut, uint _deadline) external nonReentrant ensureDeadline(_deadline) {
        uint balanceBefore = _depositBep20.balanceOf(address(this));
        _depositBep20.safeTransferFrom(msg.sender, address(this), _sellAmtBEP20);
        uint balanceAfter = _depositBep20.balanceOf(address(this));
        uint actualTransferredAmount = balanceAfter.sub(balanceBefore);
        depositFresh(_depositBep20, actualTransferredAmount,_minTrendTokenOut);
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
    function sendUnderlyingOut(IERC20 _underlying, uint _amount) internal {
        requireUnderAmount(_amount,contractBal(_underlying),"insufficent bal");

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
    function trendTokenInCalculations(IERC20 _redeemBep20, uint _redeemAmt) 
        internal view returns(uint price, uint trendTokenPrice, uint mintMBNB, uint trendTokenInAmt, uint protocolFeePerc, int feeOrReward)  {

        (int priorDelta, int postDelta, uint priceToken, uint equity) = tokenInfo(_redeemBep20,0,_redeemAmt);
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
        compTT.permissionRedeemTT(address(this), address(_redeemBep20), _redeemAmt);
        
        (uint price, 
        uint trendTokenPrice,, 
        uint trendTokenInAmt, 
        uint protocolFeePerc, 
        int feeOrReward) = trendTokenInCalculations(_redeemBep20, _redeemAmt);

        // Receive Trend Tokens and send Performance Fee
        requireUnderAmount(trendTokenInAmt,_maxTrendTokenIn,"!maxIn");
        trendToken.transfersFrom(msg.sender, address(this), trendTokenInAmt); 

        // Add Trend Tokens to rerve and burn the rest
        uint trendTokenFee = Lib.getValue(trendTokenInAmt,protocolFeePerc);

        // Redeem and send underlying
        sendUnderlyingOut(_redeemBep20, _redeemAmt);

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
     * @notice Performs intermediary calculations for tradeInfo()
     * @return tokenEquityInOut The equity of tokenIn and tokenOut
     * @notice desiredAllos The desired allocations of tokenIn and tokenOut
     * @notice netEquity The net equity of the entire portfolio

     */
    function swapInfoFresh(IERC20[] memory tokensInOut) internal view returns(int[] memory, int[] memory, uint) {

        // create local return variables (negative if borrow)
        int[] memory tokenEquityInOut = new int[](2);
        int[] memory desiredAllos = new int[](2);

        // requires all tokens for netEquity value
        (address[] memory tokens,,
        uint[] memory conVals,
        uint[] memory colVals,
        uint[] memory borVals,
        uint netEquity) = storedEquity();

        for (uint i=0; i < tokens.length; i++) {

            if (IERC20(tokens[i]) == tokensInOut[0]) { // dTokenIn: sell

                tokenEquityInOut[0] = int(conVals[i].add(colVals[i])).sub(int(borVals[i]));
                desiredAllos[0] = int(contractAllo[i].add(collateralAllo[i])).sub(int(borrowAllo[i])); 

            } else if (IERC20(tokens[i]) == tokensInOut[1]) { // dTokenOut: buy

                tokenEquityInOut[1] = int(conVals[i].add(colVals[i])).sub(int(borVals[i]));
                desiredAllos[1] = int(contractAllo[i].add(collateralAllo[i])).sub(int(borrowAllo[i])); 
                
            }
        
        }

        return (tokenEquityInOut, desiredAllos, netEquity);

    }

    /** 
     * @notice Calculates the value of tokenOut to send back to the user
     * @dev Used in executeTrade()
     * @param tokenInOut An array of [tokenIn, tokenOut]
     * @param valueIn The value of tokenIn sent by user
     */
    function swapInfo(IERC20[] memory tokenInOut, uint valueIn) internal view returns(uint valOutAfterBuy)  {

        // helper function gets equity of tokenInOut, desired allocations, and total portfolio
        (int[] memory tokenEquityInOut, int[] memory desiredAllos, uint netEquity) = swapInfoFresh(tokenInOut);

        // ensures tokenIn and tokenOut are not zero address or the same token, and are only 2 tokens
        require(netEquity>0 && address(tokenInOut[0]) != address(0) && tokenInOut[0] != tokenInOut[1] &&  tokenInOut.length == 2, "equity !> 0");

        // local variables to store prior and post delta (difference in desired-current allocations) for tokenIn and tokenOut
        int[] memory priorPostDeltaIn = new int[](2);
        int[] memory priorPostDeltaOut = new int[](2);

        // calculates the value (USD) of token being sold
        uint equityAfterSellIn = netEquity.add(valueIn); // should always be positive
        int tokenInEquityAfterSell = tokenEquityInOut[0].add(int(valueIn)); // may be negative (if borrow)
        priorPostDeltaIn[0] = desiredAllos[0].sub(tokenEquityInOut[0].mul(1e18).div(int(netEquity))); // 1 - 13/30 = 56%
        priorPostDeltaIn[1] = desiredAllos[0].sub(tokenInEquityAfterSell).mul(1e18).div(int(equityAfterSellIn)); // 1 - (13+1)/ 31 = 54%        
        uint valAfterSellOut = incentiveModel.valueOutAfterSell(tokenInOut[0], valueIn, priorPostDeltaIn[0], priorPostDeltaIn[1], xtt.balanceOf(msg.sender));

        // calculates the value (USD) of token being purchased
        priorPostDeltaOut[0] = desiredAllos[1].sub(tokenEquityInOut[1].mul(1e18).div(int(equityAfterSellIn))); // 0 - 17/31 = -55%
        uint equityAfterSellOut = equityAfterSellIn.sub(valAfterSellOut);
        int tokenOutEquityAfterSell = tokenEquityInOut[1].sub(int(valAfterSellOut));
        priorPostDeltaOut[1] = desiredAllos[1].sub(tokenOutEquityAfterSell.mul(1e18).div(int(equityAfterSellOut))); // 0 - (17-1)/(31-1) = -47%
        valOutAfterBuy = incentiveModel.valueOutAfterBuy(tokenInOut[1], valAfterSellOut, priorPostDeltaOut[0], priorPostDeltaOut[1]);

    }

    
    /**
     * @notice Executes desired trade
     * @param tokenInOut List of [tokenSell, tokenBuy]
     * @param sellAmt The amount of tokenSell to sell
     */
    function executeTrade(IERC20[] memory tokenInOut, uint sellAmt, uint _minOut, uint _deadline) internal pausedTrendToken  ensureDeadline(_deadline) {
        compTT.permissionTrade(address(this), address(tokenInOut[0]),  address(tokenInOut[1]), sellAmt);
        require(Lib.addressInList(address(tokenInOut[0]), portfolioTokens) && 
                Lib.addressInList(address(tokenInOut[1]), portfolioTokens),"!portfolio.");
        

        uint valueIn = Lib.getValue(sellAmt,compTT.priceBEP20(tokenInOut[0]));
        uint valOutAfterBuy = swapInfo(tokenInOut,valueIn);
        uint outUnderlying = Lib.getAssetAmt(valOutAfterBuy,compTT.priceBEP20(tokenInOut[1]));
        require(outUnderlying >= _minOut,"!minOut");
        
        sendUnderlyingOut(tokenInOut[1], outUnderlying);

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
        require(tokenInOut[0] == wbnb, "!BNB");
        executeTrade(tokenInOut,msg.value,minOut,_deadline);
    }


    // ------------------------------ VENUS INTERACTIONS ---------------------------- // 

    /**
     * @notice If Venus not open then only tradingBot can execute trades
     */
    function checkVenusOpen() internal view {
        if (!venusOpen) {
            require(msg.sender == tradingBot,"!venusOpen");
        }
    }

    /**
     * @notice Borrows USDT from Venus
     */
    function executeBorrow(IERC20 underlying, uint borrowAmount, uint repayAmount) external nonReentrant {
        // limit to tradingBot if Venus not open
        checkVenusOpen();

        if (borrowAmount>0) {

            // checks if permission from comptroller (checks borrowFactor and active status)
            // checks borrow factor, borrow direction, and active status
            address vToken = compTT.permissionBorrow(address(this), address(underlying), borrowAmount);
            borrowVenus(IVBep20(vToken), borrowAmount); 
        }

        if (repayAmount>0) {

            // checks if permission from comptroller (checks active status) 
            // checks supply direction and and active status
            address vToken =  compTT.permissionRepay(address(this), address(underlying), repayAmount);
            repayVenus(underlying, IVBep20(vToken), repayAmount);

        }

    }


    /**
     * @notice Supplies asset to market
     */
    function executeSupply(IERC20 underlying, uint supplyAmount, uint redeemAmount) external nonReentrant {
        // limit to tradingBot if Venus not open
        checkVenusOpen();

        if (supplyAmount > 0) {

            // checks if permission from comptroller (checks activity)
            // checks supply direction and active status
            address vToken = compTT.permissionSupply(address(this), address(underlying), supplyAmount);
            collateralSupply(underlying, IVBep20(vToken), supplyAmount);
        }

        if (redeemAmount > 0) {
            // checks if permission from comptroller (checks borrowFactor)
            // checks borrow factor, borrow direction, and active status
            address vToken = compTT.permissionRedeem(address(this), address(underlying), redeemAmount);
            collateralRedeem(IVBep20(vToken), redeemAmount);
        }

    } 


}


