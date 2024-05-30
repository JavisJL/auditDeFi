// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.0;

import "./TrendTokenTkn.sol";
import "./Venus.sol";
import "./CompTT.sol";
import "./ICompTT.sol";
import "./MarginTokenStorage.sol";
import "./IncentiveModel.sol";
import "./SafeERC20.sol";


contract MarginToken is VenusIntegration, MarginTokenStorage { 

    using SafeERC20 for IERC20;

    constructor(address _compTT) VenusIntegration(_compTT) {
        manager = payable(msg.sender);
        tradingBot = msg.sender;
        TrendTokenTkn _trendToken = new TrendTokenTkn("MarginToken10","MARGIN10");
        trendToken = ITrendTokenTkn(address(_trendToken));
        _notEntered = true;
    }


    /**
     * @notice Allows for the deposit of BNB to this contract
     * @dev Required to receive BNB from users or Venus
     */
    receive() external payable {
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
     * @notice Prevents a contract from calling itself, directly or indirectly (re-entrancy attack)
     */
    modifier nonReentrant() {
        require(_notEntered, "re-entered");
        _notEntered = false;
        _;
        _notEntered = true; // get a gas-refund post-Istanbul
    }


    /**
     * @notice Prevents depsoit, redeem, swap, and venus actions if trendTokenPaused
     */
    modifier pausedTrendToken() {
        require(!trendTokenPaused, "!paused");
        _;
    }

    /**
     * @notice Prevents Manager from executing highly secure operations
     * @dev Including _updateIncentiveModel, _updateManagerAndBot, _updatePerformanceFee 
     * @dev CompTT must give permission to this Trend Tokens manager for making such high secure changes
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
     * @dev Saves byte size over repeating similar require statements
     */
    function requireUnderAmount(uint value, uint max, string memory message) internal pure {
        require(value<=max, message);
    }

    // ---------------   ADMIN FUNCTIONS & VARIABLES ----------------- //

    
    // -------  MANAGER: UPDATE ADDRESSES ------- // 


    /**
     * @notice Sets new Trend Token incentive model
     * @dev If want unchanged, set parameter to zero address when calling function
     * @param _incentiveModel View functions that dictate the deposit and redeem rewarrds 
     */
    function _updateIncentiveModel(IIncentiveModel _incentiveModel) onlyManager requireUnlocked external {

        address oldIncentive = address(incentiveModel);
        if (address(_incentiveModel) != address(0)) {
            incentiveModel = _incentiveModel;
        }

        emit UpdateIncentiveModel(oldIncentive, address(incentiveModel));
 
    }


    /**
     * @notice Allows manager to change its manager address and tradingBot address
     * @dev If want unchanged, set parameter to zero address when calling function
     * @param _manager The managers address than can update compTT, incentiveModel, performance fee, max supply, etc
     * @param _tradingBot Ability to set portfolios, allocations, and some Venus actions
     */
    function _updateManagerAndBot(address payable _manager, address _tradingBot) onlyManager requireUnlocked external {

        address oldManager = address(manager);
        if (_manager != address(0)) {
            manager = _manager;
        }

        address oldTradingBot = address(tradingBot);
        if (_tradingBot != address(0)) {
            tradingBot = _tradingBot;
        }

        emit UpdateManagerAndBot(oldManager,  address(manager), oldTradingBot,  address(tradingBot));

    }
    

    // -------  MANAGER: UPDATE FEES/REWARDS ------- // 

    
    /** 
     * @notice Updates performance fee 
     * @dev The outstanding performance fees are accrued and distributed before changing
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
     * @notice Sets a new maxDisableTokenValue and maxSupply
     * @dev If want unchanged, set parameter to zero address when calling function
     * @param _maxDisableTokenValue The maximum amount a token can hold in 'contract + collateral + borrow' before being removed from portfolio
     * @param _maxSupply The maximum supply of Trend Tokens that can be in supply
     */
    function _updateMaxDisableAndSupply(uint _maxDisableTokenValue, uint _maxSupply) onlyManager requireUnlocked external {

        (uint maxDisableValue, ,uint maxSupplyComp) =  compTT.trendTokenMaxValuesAndSupply(address(this));

        // max disable values
        uint oldMaxDisableValue = maxDisableTokenValue;
        if (_maxDisableTokenValue>0) {
            requireUnderAmount(_maxDisableTokenValue, maxDisableValue, "!maxDisableValue");
            maxDisableTokenValue = _maxDisableTokenValue;
        }

        // max Trend Token supply
        uint oldMaxSupply = maxSupply;
        if (_maxSupply>0) {
            requireUnderAmount(_maxSupply, maxSupplyComp, "!maxSupply");
            maxSupply = _maxSupply;
        }

        emit UpdateMaxDisableAndSupply(oldMaxDisableValue, maxDisableTokenValue, oldMaxSupply, maxSupply);
    }



    // -------- MANAGER: DUAL POOL INTERACTIONS --------------- // 


    // ------- TRADING BOT: UPDATE BOOL --------- //


    /**
     * @notice Allows trading bot to change if Venus is open to public
     * @dev Events removed to save contract byte size
     * param _isVenusOpen If true then public may supply, redeem, borrow, and repay. Otherwise only tradingBot
     * @param _pauseTrendToken If true then pause state of Trend Token
     */ // bool _isVenusOpen, 
    function _updateVenusAndPauseState(bool _pauseTrendToken) onlyTradingBot external {
        //venusOpen = _isVenusOpen;
        trendTokenPaused = _pauseTrendToken;
    }



    /**
     * @notice Allows trading bot to pause deposits of underlying
     * @dev Required before updating allocations to prevent sandwich attack
     * @dev May be used when desired to remove a token from portfolio to prevent future deposits of it
     */
    function _updateDepositsDisabled(address[] calldata _tokens, bool _isDisabled) onlyTradingBot external {
        for (uint i=0; i<_tokens.length; i++) {
            address token = _tokens[i];
            depositsDisabled[token] = _isDisabled;
        }
    }


    // ------- TRADING BOT: UPDATE PORTFOLIO --------- //)

    /**
     * @notice Safely changes contract, collateral, and borrow allocations without changing portfolio
     * @dev Ensures the desired allocations are within margin limits and required permission from comptroller
     * @dev If tradingBot would like to disable token, update positions with 0% then disable deposits
     * @param _con The desired percent of equity in contract for existing portfolio
     * @param _col The desired percent of equity in venus collateral for existing portfolio
     * @param _bor The desired percent of equity in venus borrow for existing portfolio
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

            // fetches vToken from compTT
            address vToken = compTT.returnVToken(portfolioTokens[i]); // may be zero address

            // adds contract totals
            conTotal = conTotal + _con[i];

            // checks supply conditions and enables/disables vToken
            bool isSupply = false;
            if (_col[i] > 0) {

                // vToken must be supported
                ensureNonzeroAddress(vToken);

                // enter vToken if it isnt already
                if (!tokenEntered(IVBep20(vToken))) {
                    enableSingleCol(vToken);
                }

                // set supply status and add to colTotal
                isSupply = true;
                colTotal = colTotal + _col[i];

                // add collateral to estimated liquidity 'estBorrow = estBorrow + col*factor/1e18
                estBorrowableTotal = estBorrowableTotal + (_col[i] * collateralFactor(IVBep20(vToken)) / 1e18); 
            }

            // checks borrow conditions
            bool isBorrow = false;
            if (_bor[i] > 0) {
                
                // vToken must be supported
                ensureNonzeroAddress(vToken);

                // set borrow status and add to borTotal
                isBorrow = true;
                borTotal = borTotal + _bor[i];
                
            }

            // disables collateral if no desired or current borrow or supply (and vToken exists)
            if (vToken != address(0) && !isBorrow && !isSupply) {
                (,,, uint col, uint bor,) = tokenInfoVal(IERC20(portfolioTokens[i]));
                if (col <= maxDisableTokenValue && bor <= maxDisableTokenValue) {
                    disableCol(IVBep20(vToken));
                }
            }
        
            // ensure permission from comptroller
            // ensures underlying is disabled, trend token and underlying are active
            bool permission = compTT.permissionPortfolio(address(this), portfolioTokens[i], isSupply, isBorrow);
            require(permission, "!permission.");

        }


        // ensures net equity doesnt exceed 100% and at least 1% is in contract to allow for immediate withdrawals
        require(conTotal + colTotal - borTotal == 1e18 && conTotal >= 0.01e18, "!=100%||con<1%");

        // check borrow requirements
        if (borTotal>0) {
            
            // ensure maxBorrowFactor is not exceeded
            uint estBorrowFactor = 1e18; // 100% if estBorrowTotal not greater than 0
            if (estBorrowableTotal>0) {
                estBorrowFactor = borTotal * 1e18 / estBorrowableTotal;
            }

            // fetch maximum borrow values from Comptroller
            (uint maxBorrowFactor, uint maxMargin) = compTT.trendTokenMaxBorrowValues(address(this));
            requireUnderAmount(estBorrowFactor, maxBorrowFactor, "!BorrowFactor.");
            requireUnderAmount(borTotal, maxMargin, "!maxMargin.");

        }


        // set inputs to state variables
        contractAllo = _con;
        collateralAllo = _col;
        borrowAllo = _bor;

    }


    /** 
     * @notice Allows tradingBot to update new portfolio and desired contract, collateral, and borrow allocations
     * @dev All remove tokens (in current portfolio but not _newPortfolio) must have values below maxDisableTokenValue
     * @dev To do this, first _setDesiredAllocations() to 0/0/0 for each token wishing to be removed in this update and pause deposits for it
     * @param _newPortfolio The desired new portfolio. Input [] if no change to portfolio desired
     * @param _con The desired percent of equity in contract for new portfolio
     * @param _col The desired percent of equity in venus collateral for new portfolio
     * @param _bor The desired percent of equity in venus borrow for new portfolio
     */
    function _updatePortfolioAndAllocations(address[] calldata _newPortfolio, uint[] calldata _con, uint[] calldata _col, uint[] calldata _bor) onlyTradingBot external {

        // only make changes if _newPortfolio is not empty
        if (_newPortfolio.length > 0) {

            // checks if any tokens from portfolioTokens have been removed
            // applies conditions to these tokens and disables collateral
            for (uint i=0; i<portfolioTokens.length; i++) {

                address oldToken = portfolioTokens[i];
                bool tokenInNewPortfolio = Lib.addressInList(oldToken, _newPortfolio);

                // if token not in new portfolio
                if (!tokenInNewPortfolio) {
                    
                    // requires low con+col+bor balance to remove from portfolio
                    (,,uint con, uint col, uint bor,) = tokenInfoVal(IERC20(oldToken));
                    requireUnderAmount(con + col + bor, maxDisableTokenValue, "!maxDisableValue.");

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

        }


        // updates positions based on new portfolio
        // variety of conditions must be met
        _setDesiredAllocationsFresh(_con, _col, _bor);
    }




    // -------------------- MANAGER: REDEEM & REDUCE TREND TOKENS ------------------- // 


    /** 
     * @notice Allows manager to redeem Trend Tokens and XVS to manager
     * @param claimXVS Claims the XVS from Venus and sends to manager
     * @param claimPerformanceFee Mints outstanding performance fees and sends to manager
     * @param redeemAmtTrendToken Sends this amount of Trend Token in the contract to manager (performance and trade fees)
     */
    function _claimXVSandFees(bool claimXVS, bool claimPerformanceFee, uint redeemAmtTrendToken) onlyManager external  {

        // claims XVS and sends to manager
        if (claimXVS) {
            IERC20 xvs = compTT.getXVSAddress();
            uint balBeforeXVS = balanceHolder(xvs,address(this));
            ICompVenus(compTT.compVenus()).claimVenus(address(this));
            uint balChangeXVS = balanceHolder(xvs,address(this)) - balBeforeXVS;
            if (balChangeXVS > 0) {
                xvs.safeTransfer(manager, balChangeXVS);
            }
        }

        // mints any outstanding performance fees and holds in this contract
        if (claimPerformanceFee) {
            (uint trendTokenPrice, uint mintMBNB) = trendTokenToUSD(); 
            sendPerformanceFee(mintMBNB, trendTokenPrice);
        }
        
        // redeems trend tokens held by contract to manager, will fail if insufficient supply
        if (redeemAmtTrendToken > 0) {
            IERC20(address(trendToken)).safeTransfer(manager,redeemAmtTrendToken);
        }
    }


    // ------ EXTERNAL VIEW FUNCTIONS ------------- //
    // @notice Often used by frontend and monitoring

    /**
     * @notice Returns the price of trend token (in USD) externally
     */
    function trendTokenToUSDext() external view returns(uint, uint) {
        return trendTokenToUSD();
    }


    /**
     * @notice External function for stored equity
     */
    function storedEquityExternal() external view returns(address[] memory,uint[] memory,uint[] memory,uint[] memory,uint[] memory,uint) {
        return storedEquity();
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
        uint gainATH = trendTokenPrice - trendTokenATH; // (3e18 - 1.5e18) = 1.5e18
        uint feeAmt = Lib.getValue(gainATH,performanceFee); // 1.5e18 * 20% = = 0.30e18
        uint targetPrice = trendTokenPrice - feeAmt; // 3e18 - 0.30e18 = 2.7e18 (price after fee)
        uint mintPercent = Lib.getAssetAmt(trendTokenPrice,targetPrice) - 1e18;// (3.0e18*1e18/2.7e18) - 1e18 = 0.1111e18
        uint mintTrendTokenAmt = Lib.getValue(trendTokenSupply,mintPercent); // 100e18 * 0.1111e18 / 1e18 = 11.111...e18 mBNB 
        return mintTrendTokenAmt;
    }


    /**
     * @notice Mints and sends trend token performance fees to this contract
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
    // @notice Key internal view functions to supply and redeem Trend Tokens


    /**
     * @notice Returns the balance of _token for _holder
     */
    function balanceHolder(IERC20 _token, address _holder) internal view returns(uint) {
        if (_token == wbnb) { 
            return _holder.balance;
        } else { 
            return _token.balanceOf(_holder);
        }
    }


    /**
     * @notice Fetches key information for a single token
     * @dev Used in storedEquity() and _updatePortfolio()
     * @param _token The token to get information on (address, token, values)
    */
    function tokenInfoVal(IERC20 _token) internal view returns(address, uint, uint, uint, uint, int) {

        // empty value sums
        uint assetValSum = 0;
        uint borrowValSum = 0;
            
        // store prices
        uint price = compTT.priceBEP20(_token);
        
        // store conVals
        uint contractVal = Lib.getValue(balanceHolder(_token,address(this)),price);
        uint collateralVal = 0; 
        uint borrowVal = 0; 

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
            assetValSum = assetValSum + contractVal + collateralVal;
            borrowValSum = borrowValSum + borrowVal;

        } else {

            // add contract values to totals
            assetValSum = assetValSum + contractVal;

        }

        int tokenNetEquity = int(assetValSum) - int(borrowValSum);

        return (address(_token), price, contractVal, collateralVal, borrowVal, tokenNetEquity);    

    }



    /**
     * @notice Fetches key information for a entire portfolioTokens
     * @dev Used in calculating Trend Token price and buy or sell Trend Tokens and swapping
    */
    function storedEquity() internal view returns(address[] memory,uint[] memory,uint[] memory,uint[] memory,uint[] memory,uint) { 

        // creates return variables
        address[] memory tokens = portfolioTokens;
        uint[] memory prices = new uint[](tokens.length);
        uint[] memory conVals = new uint[](tokens.length);
        uint[] memory colVals = new uint[](tokens.length);
        uint[] memory borVals = new uint[](tokens.length);
        uint assetVal = 0;
        uint borVal = 0;

        // loops though portfolio and stores key information
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
                assetVal = assetVal + uint(tokenEquity);
            } else {
                uint borrowValue = uint(-tokenEquity);
                borVal = borVal + borrowValue;
            }   

        }

        // calculate net equity 'equity = assets - borrows'
        require(assetVal>borVal,"borVal>>");
        uint netEquity = assetVal - borVal;

        return (tokens,prices,conVals,colVals,borVals,netEquity);

    }


    /**
     * @notice Calculates the price of a Trend Token 
     */
    function trendTokenToUSD() internal view returns(uint,uint) {
        (,,,,,uint equity) = storedEquity();
        return trendTokenToUSD(equity);
    }


    /**
    * @notice Calculate the Trend Token Price in USD after accepting equity value of portfolio
    * @dev Formula 'equity/(trend token supply + outstanding performance fees)' 
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

            price = Lib.getAssetAmt(_equityInUSD,supplyTrendToken + mintTrendToken);
        }

        return (price,mintTrendToken);

    }


    /**
     * @notice Returns the desired allocations of a token based on index
     * @dev May be negative if desired borrow exceeds desired contract and collateral
     * @param tokenIndex The index of token in portfolioTokens
     */
    function desiredAllocation(uint tokenIndex) internal view returns(int) {
        return int(contractAllo[tokenIndex]) + int(collateralAllo[tokenIndex]) - int(borrowAllo[tokenIndex]);
    }


    /**
     * @notice Fetches data required for deposit/redeem incentives for a specific token
     * @dev Used by trendTokenOutCalculations() and trendTokenInCalculations() for incentive model 
     * @param _token The spefific token to get information on (e.g 0xbb..)
     * @return priorDelta The differences between desired and current allocations prior to deposit or redeem of _token
     * @return postDelta The differences between desired and current allocations post deposit or redeem of _token
     * @return price The price of _token, 
     * @return equity The total Trend Token equity in contract and Venus for entire portfolioTokens
     */
    function tokenInfo(IERC20 _token, uint depositAmt, uint redeemAmt) internal view returns(int priorDelta, int postDelta, uint price, uint equity) {
        
        // requires _token is in portfolio
        require(Lib.addressInList(address(_token),portfolioTokens),"!portfolio.");
        
        (address[] memory tokens, 
        uint[] memory prices,
        uint[] memory conVals,
        uint[] memory colVals,
        uint[] memory borVals,
        uint netEquity) = storedEquity(); 

        for (uint i=0; i < tokens.length; i++) {

            if (tokens[i] == address(_token)) {

                // stores USD values
                price = prices[i];
                equity = netEquity;
                uint depositVal = Lib.getValue(depositAmt,price);
                uint redeemVal = Lib.getValue(redeemAmt,price);

                // calculates desired % allocation of netEquity 'contract + collateral - borrow' => can be negative if borrow

                if (netEquity>0) {

                    // get delta prior to action 'desired allocation - current allocation' 
                    int tokenEquity = int(conVals[i]) + int(colVals[i]) - int(borVals[i]);
                    int priorAllocations = tokenEquity * 1e18 / int(netEquity);
                    priorDelta = desiredAllocation(i) - priorAllocations;

                    // require redeem value does not exceed net portfolio equity or token contract values
                    require(redeemVal < netEquity && redeemVal <= conVals[i],"insufficient redeem");

                    // get delta post action 'desired allocation - calculated allocation after deposit or redeem'
                    int tokenEquityPost = tokenEquity + int(depositVal) - int(redeemVal);
                    int postAllocation = tokenEquityPost * 1e18 / (int(netEquity + depositVal - redeemVal));
                    postDelta = desiredAllocation(i) - int(postAllocation);

                
                } else { // starting conditions

                    require(redeemVal==0,"redeem=0.");
                    priorDelta = desiredAllocation(i);
                    postDelta = int(1e18);
                     
                }

                break;
                
            }
        
        }

        require(price>0,"!tokenInPortfolio");

    }



    // ------------ DEPOSIT FUNCTION -------------- //
    // @notice Allows users to supply any asset in the portfolio for Trend Tokens


    /**
     * @notice Calculates the fees and trend token amounts out upon deposit
     * @dev Calls the Incentive Model contract to fetch base protocol fee and fee/reward incentive
     */
    function trendTokenOutCalculations(IERC20 _depositBep20, uint _sellAmtBEP20) 
        internal view returns(uint price, uint trendTokenPrice, uint mintMBNB, uint trendTokenAmt, uint protocolFeePerc, int feeOrReward)  {

        // calculates the difference between desired and actual positions before and after user deposit
        (int priorDelta, int postDelta, uint priceToken, uint equity) = tokenInfo(_depositBep20,_sellAmtBEP20,0);
        uint inValue = Lib.getValue(_sellAmtBEP20,priceToken);
        equity = equity - inValue; // equityprior

        // calculates the value user deposited after subtracting fees from incentiveModel (fee or reward)
        (feeOrReward, protocolFeePerc,,) = incentiveModel.totalDepositFee(_depositBep20, inValue, priorDelta, postDelta, priceToken, balanceHolder(compTT.getXTTAddress(),msg.sender)); 
        uint inValueMinusFees = Lib.getValue(inValue, uint(int(1e18) - feeOrReward));

        // calculates trend token amount out based on price and fees
        (trendTokenPrice, mintMBNB) = trendTokenToUSD(equity); 
        trendTokenAmt = Lib.getAssetAmt(inValueMinusFees,trendTokenPrice);
        price = priceToken;

    }


    /**
     * @notice Allows the deposit of BNB/BEP20 for Trend Tokens
     * @dev Keeps protocolFeePerc in Trend Token Portfolio to increase price of Trend Tokens
     */
    function depositFresh(IERC20 _depositBep20, uint _sellAmtBEP20, uint _minTrendTokenOut) internal pausedTrendToken returns(uint)  {
        
        // token deposits cannot be disabled
        require(!depositsDisabled[address(_depositBep20)], "depositsDisabled");  // checks deposits arent disabled

        // Calculate prices, fees, and amounts
        (uint priceToken,
        uint trendTokenPrice,, 
        uint trendTokenAmt, 
        uint protocolFeePerc, 
        int feeOrReward) = trendTokenOutCalculations(_depositBep20, _sellAmtBEP20);

        // Require permission from comptroller and deposit of token not disabled by this manager
        compTT.permissionDepositTT(address(this),address(_depositBep20),_sellAmtBEP20,feeOrReward); // above zero, unpaused, trend token active

        // Send fees and Trend Token to user
        requireUnderAmount(_minTrendTokenOut, trendTokenAmt,"!minOut");
        trendToken.mint(msg.sender, trendTokenAmt);// mint and send Margin Token to Trader (after fees)

        // Require max supply isnt exceeded
        uint supplyTrendToken = trendToken.totalSupply();
        requireUnderAmount(supplyTrendToken , maxSupply,"!maxSupply");

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
        
        // accept BEP20 deposit from user and calculate actual amount transferred
        uint balanceBefore = _depositBep20.balanceOf(address(this));
        _depositBep20.safeTransferFrom(msg.sender, address(this), _sellAmtBEP20);
        uint balanceAfter = _depositBep20.balanceOf(address(this));
        uint actualTransferredAmount = balanceAfter - balanceBefore;

        // call depositFresh function with actual transferred amount
        depositFresh(_depositBep20, actualTransferredAmount,_minTrendTokenOut);
    }


    // --- REDEEM FUNCTIONS  --- //
    // @notice Allows users to redeem Trend Tokens for any underlying asset, if it has a sufficient balance


    /**
     * @notice Sends underlying to user after depositing Trend Tokens
     * @dev Redeems from Dual Pools if contract balance isnt great enough
     *      Amount is updated as exact amount redeemed may vary from _amount
     */
    function sendUnderlyingOut(IERC20 _underlying, uint _amount) internal {
        requireUnderAmount(_amount,balanceHolder(_underlying,address(this)),"insufficentBal");

        if (_underlying == wbnb) {

            payable(msg.sender).transfer(_amount); 

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
        
        // fetch key token infromation
        (int priorDelta, int postDelta, uint priceToken, uint equity) = tokenInfo(_redeemBep20,0,_redeemAmt);
        uint outValueEst = Lib.getValue(_redeemAmt,priceToken); 

        // calculate value to send to user including fees
        (feeOrReward, protocolFeePerc,,) = incentiveModel.totalRedeemFee(_redeemBep20, outValueEst, priorDelta, postDelta, priceToken, balanceHolder(compTT.getXTTAddress(),msg.sender));
        uint outValueAddFees = Lib.getValue(outValueEst, uint(int(1e18) + feeOrReward)); 

        // store key variables
        (trendTokenPrice, mintMBNB) = trendTokenToUSD(equity);  
        trendTokenInAmt = Lib.getAssetAmt(outValueAddFees,trendTokenPrice); 
        price = priceToken;

    }


    /**
     * @notice Allows for the deposit of Trend Tokens to redeem an underlying asset of redeemers choice out of current portfolio assets
     * @param _redeemBep20 The token the redeemer wishes to redeem
     * @param _redeemAmt The amount of underlying to be redeemed
     * @param _maxTrendTokenIn Maximum amount of Trend Tokens to be redeemed for _redeemAmt of _redeemBep20
     * @return The amount of underlying sent to redeemer
     */
    function redeemFresh(IERC20 _redeemBep20, uint _redeemAmt, uint _maxTrendTokenIn) internal pausedTrendToken returns(uint) { // change back to external
        
        (uint price, 
        uint trendTokenPrice,, 
        uint trendTokenInAmt, 
        uint protocolFeePerc, 
        int feeOrReward) = trendTokenInCalculations(_redeemBep20, _redeemAmt);

        // Requires permission from compTT to redeem Trend Tokens
        compTT.permissionRedeemTT(address(this), address(_redeemBep20), _redeemAmt, feeOrReward);

        // Receive Trend Tokens and send Performance Fee
        requireUnderAmount(trendTokenInAmt,_maxTrendTokenIn,"!maxIn");
        trendToken.transferFrom(msg.sender, address(this), trendTokenInAmt); 

        // Burn deposited tokens but leave trendTokenFee in contract
        uint trendTokenFee = Lib.getValue(trendTokenInAmt,protocolFeePerc);
        trendToken.burn(trendTokenInAmt - trendTokenFee);

        // Redeem and send underlying
        sendUnderlyingOut(_redeemBep20, _redeemAmt);

        // Events
        emit Redeem(price, trendTokenPrice, trendToken.totalSupply(), protocolFeePerc, feeOrReward,trendTokenFee);

        return trendTokenInAmt;

    }


    /**
     * @notice External function redeemer interacts with to redeem Trend Tokens
     */
    function redeem(IERC20 _redeemBep20, uint _redeemAmt, uint _maxTrendTokenIn, uint _deadline) external nonReentrant  ensureDeadline(_deadline) {
        redeemFresh(_redeemBep20, _redeemAmt, _maxTrendTokenIn);
    }


    // --------------- TRADE FUNCTIONALITY ----------------- // 


    /**
     * @notice Performs intermediary calculations for tradeInfo()
     * @return tokenEquityInOut The equity of tokenIn and tokenOut
     * @return desiredAllos The desired allocations of tokenIn and tokenOut
     * @return netEquity The net equity of the entire portfolio

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

            // collects information for tokenIn (tokensInOut[0]) and tokenOut (tokensInOut[1])
            bool isTokenIn = IERC20(tokens[i]) == tokensInOut[0];
            if (isTokenIn || IERC20(tokens[i]) == tokensInOut[1]) {

                int tokenEquity = int(conVals[i] + colVals[i]) - int(borVals[i]);
                int desiredAllo = int(contractAllo[i] + collateralAllo[i]) - int(borrowAllo[i]); 

                if (isTokenIn) { 

                    tokenEquityInOut[0] = tokenEquity;
                    desiredAllos[0] = desiredAllo;

                } else {  // then must be tokenOut

                    tokenEquityInOut[1] = tokenEquity;
                    desiredAllos[1] = desiredAllo; 
                    
                }

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
        require(netEquity>0 && address(tokenInOut[0]) != address(0) && tokenInOut[0] != tokenInOut[1] &&  tokenInOut.length == 2, "equity!>0");

        // local variables to store prior and post delta (difference in desired-current allocations) for tokenIn and tokenOut
        int[] memory priorPostDeltaIn = new int[](2);
        int[] memory priorPostDeltaOut = new int[](2);

        // calculates the value (USD) of token being sold
        uint equityAfterSellIn = netEquity + valueIn; // should always be positive
        int tokenInEquityAfterSell = tokenEquityInOut[0] + int(valueIn); // may be negative (if borrow)
        priorPostDeltaIn[0] = desiredAllos[0] - (tokenEquityInOut[0] * 1e18 / int(netEquity)); // 1 - 13/30 = 56%
        priorPostDeltaIn[1] = desiredAllos[0] - (tokenInEquityAfterSell) * 1e18 / int(equityAfterSellIn); // 1 - (13+1)/ 31 = 54%        
        uint valAfterSellOut = incentiveModel.valueOutAfterSell(tokenInOut[0], valueIn, priorPostDeltaIn[0], priorPostDeltaIn[1], balanceHolder(compTT.getXTTAddress(),msg.sender));

        // calculates the value (USD) of token being purchased
        priorPostDeltaOut[0] = desiredAllos[1] - (tokenEquityInOut[1] * 1e18 / int(equityAfterSellIn)); // 0 - 17/31 = -55%
        uint equityAfterSellOut = equityAfterSellIn - valAfterSellOut;
        int tokenOutEquityAfterSell = tokenEquityInOut[1] - int(valAfterSellOut);
        priorPostDeltaOut[1] = desiredAllos[1] - (tokenOutEquityAfterSell * 1e18 / int(equityAfterSellOut)); // 0 - (17-1)/(31-1) = -47%
        valOutAfterBuy = incentiveModel.valueOutAfterBuy(tokenInOut[1], valAfterSellOut, priorPostDeltaOut[0], priorPostDeltaOut[1]);

    }

    
    /**
     * @notice Executes desired trade
     * @param tokenInOut List of [tokenSell, tokenBuy]
     * @param sellAmt The amount of tokenSell to sell
     */
    function executeTrade(IERC20[] memory tokenInOut, uint sellAmt, uint _minOut, uint _deadline) internal pausedTrendToken  ensureDeadline(_deadline) {

        require(!depositsDisabled[address(tokenInOut[0])],"!depositsDisabled");
        require(Lib.addressInList(address(tokenInOut[0]), portfolioTokens) && 
                Lib.addressInList(address(tokenInOut[1]), portfolioTokens),"!portfolio.");
        
        uint valueIn = Lib.getValue(sellAmt,compTT.priceBEP20(tokenInOut[0]));
        uint valOutAfterBuy = swapInfo(tokenInOut,valueIn);
        uint outUnderlying = Lib.getAssetAmt(valOutAfterBuy,compTT.priceBEP20(tokenInOut[1]));
        require(outUnderlying >= _minOut,"!minOut");

        // require permission from CompTT
        compTT.permissionTrade(address(this), address(tokenInOut[0]),  address(tokenInOut[1]), valueIn, valOutAfterBuy);
        
        sendUnderlyingOut(tokenInOut[1], outUnderlying);

        emit ExecuteTrade(sellAmt, valueIn, valOutAfterBuy, outUnderlying);
    }


    /**
     * @notice Allows user to swap one underlying (USDT) for another (BTCB)
     */
    function swapExactTokensForTokens(uint sellAmt, uint minOut, IERC20[] calldata tokenInOut, uint _deadline) external nonReentrant {
        tokenInOut[0].safeTransferFrom(msg.sender, address(this), sellAmt);
        executeTrade(tokenInOut,sellAmt,minOut,_deadline);
    }


    /**
     * @notice Allows user to swap BNB for another token (BTCB)
     */
    function swapExactETHForTokens(uint minOut, IERC20[] calldata tokenInOut, uint _deadline) external nonReentrant payable {
        require(tokenInOut[0] == wbnb, "!BNB");
        executeTrade(tokenInOut,msg.value,minOut,_deadline);
    }


    // ------------------------------ VENUS INTERACTIONS ---------------------------- // 


    /**
     * @notice Allows Margin Token to borrow or repay assets to Venus
     * @dev Assets must be held in contract to repay, borrowed assets go to contract
     */
    function executeBorrow(IERC20 underlying, uint borrowAmount, uint repayAmount) external pausedTrendToken nonReentrant {

        if (borrowAmount>0) {

            // checks if permission from comptroller (checks borrowFactor and active status)
            // checks borrow factor, borrow direction, and active status
            address vToken = compTT.permissionBorrow(address(this), address(underlying), borrowAmount);
            borrowVenus(IVBep20(vToken), borrowAmount); 
        
        } else if (repayAmount>0) {

            // checks if permission from comptroller (checks active status) 
            // checks supply direction and and active status
            address vToken =  compTT.permissionRepay(address(this), address(underlying), repayAmount);
            repayVenus(underlying, IVBep20(vToken), repayAmount);

        }

    }


    /**
     * @notice Allows Margin Token to supply or redeem assets from Venus
     * @dev Assets must be held in contract to supply
     */
    function executeSupply(IERC20 underlying, uint supplyAmount, uint redeemAmount) external pausedTrendToken nonReentrant {

        if (supplyAmount > 0) {

            // checks if permission from comptroller (checks activity)
            // checks supply direction and active status
            address vToken = compTT.permissionSupply(address(this), address(underlying), supplyAmount);
            collateralSupply(underlying, IVBep20(vToken), supplyAmount);

        } else if (redeemAmount > 0) {

            // checks if permission from comptroller (checks borrowFactor)
            // checks borrow factor, borrow direction, and active status
            address vToken = compTT.permissionRedeem(address(this), address(underlying), redeemAmount);
            collateralRedeem(IVBep20(vToken), redeemAmount);

        }

    } 


}


