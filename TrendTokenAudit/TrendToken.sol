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

// Deploy Instructions
// 1. Deploy Trend Token
// 2. Support Trend Token in Comptroller TT


// 3. Allow to add any token

// Deploy Addresses (testnet):
// XTT: 0x4D0E7Cd2A4f6D45d72B7936DDb8652aa3216A51e (verified)


// update CompTT, CompStorageTT, IncentiveModelSimple, 


// ** complete
// * in progress
// ! skip


// ---- To Do Mar -------- // 
// 1) Trade referral program? 
// 2) Change pool/recipient distribution?
//      - depending on tax consequences
// 3) Look over trendTokenToReservesPerc
// 4)** Remove performance fee distribution from deposit/redeem
// 5)** Trade: Add minOutput
// 6) Can remove borVals from storedEquity() 


contract TrendToken is DualPoolIntegration, TrendTokenStorage { 

    using SignedSafeMath for int;

    // -------- CONSTRUCTOR ------------- //   

    // Mar 25: 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x20e0827B4249588236E31ECE4Fe99A29a0Ec40bA,0x022d21035c00594bdFBdAf77bEF76BBCe597d876,0xd99d1c33f9fc3444f8101754abc46c52416550d1
    // enable bnb, busd, btcb: [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47,0xA808e341e8e723DC6BA0Bb5204Bafc2330d7B8e4],[0,1000000000000000000,0]
    // enable bnb, busd: [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47],[500000000000000000,500000000000000000]
    // enable bnb, busd: [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47],[1000000000000000000,0]
    // USDT: 0xA11c8D9DC9b66E209Ef60F0C8D969D3CD988782c

    // trade: [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47],0
    // trade: 1000000000000000000,0,[0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47,0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd]

    

    // XTT: 0x4D0E7Cd2A4f6D45d72B7936DDb8652aa3216A51e
    // compTT: 0x20e0827B4249588236E31ECE4Fe99A29a0Ec40bA
    // TrendToken: 0xb07d446fCFD123939d0a4B38Ba5725c61c43e290
    // IncentiveModel: 0xc2b0706227D1c991D508AAE81b86253E86DeF30B
    // zeroAddress: 0x0000000000000000000000000000000000000000


    constructor(address _wbnb, address _compTT, address _compDP, address _pancakeRouter) 
                DualPoolIntegration(_wbnb,_compTT,_compDP) public {
        compTT = ICompTT(_compTT);
        manager = msg.sender;
        tradingBot = msg.sender;
        feeRecipient = msg.sender;
        TrendTokenTkn _trendToken = new TrendTokenTkn("TrendToken Top5","Top5");
        trendToken = ITrendTokenTkn(address(_trendToken));
        wbnb = IERC20(_wbnb);
        pancakeRouter = IPancakeRouter(_pancakeRouter);
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


    // ---------------   ADMIN FUNCTIONS & VARIABLES ----------------- //

    
    // -------  MANAGER: UPDATE ADDRESSES ------- // 


    /**
     * @notice Sets new Trend Token comptroller, Dual Pool comptroller, and incentive model
     * @dev If want unchanged, set parameter to zero address
     * @param _compTT The Trend Token comptroller that governs all Trend Tokens
     * @param _compDP The Dual Pool comptroller that governs all dTokens for lend/redeem actions
     * @param _incentiveModel View functions that dictate the deposit and redeem rewarrds 
     */
    function _updateContracts(address _compTT, address _compDP, IIncentiveModelSimple _incentiveModel) onlyManager external {

        if (_compTT != address(0)) {
            address oldCompTT = address(compTT);
            require(ICompTT(_compTT).trendTokenIsActive(address(this)),"Inactive Trend Token." );
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
    function _updateAddresses(address _manager, address payable _feeRecipient, address _tradingBot) onlyManager external {

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
    function _newPerformanceFee(uint _performanceFee) onlyManager external {
        require(_performanceFee<=1e18 && _performanceFee <= compTT.trendTokenMaxPerformanceFee(address(this)),"!performanceFee");
        (uint trendTokenPrice, uint mintMBNB) = trendTokenToUSD(); 
        sendPerformanceFee(mintMBNB, trendTokenPrice);
        performanceFee = _performanceFee;
    }
    


    /**
     * @notice Updates the fee distribution to Fee Receipient
     * @param _trendTokenRedeemBurn Percentage of redeem trend token fees that get burned (instead of going to reserves)
    *                               which increases the value of Trend Tokens
     * @param _accruedXDPtoFeeRecipient  Percentage of protocol earned XDP that goes to fee recipient
     */
    function _updateFeeDistribution(uint  _trendTokenRedeemBurn, uint _accruedXDPtoFeeRecipient) external onlyManager {
        require(_trendTokenRedeemBurn <= 1e18 && _accruedXDPtoFeeRecipient <=  1e18, "cannot exceed 100%.");
        trendTokenRedeemBurn = _trendTokenRedeemBurn;
        accruedXDPtoFeeRecipient = _accruedXDPtoFeeRecipient;
    }

    

    /**
     * @notice Allows manager to set the referralReward
     */
    function _setReferralReward(uint _referralReward) onlyManager external {
        require(_referralReward <= 0.50e18,"!_setReferralReward");
        referralReward = _referralReward;
    }
    


    // -------   MANAGER: UPDATE VALUES ------- // 

    
    /**
     * @notice Sets the minimum value of a token before it can be removed from the portfolio
     */
    function _maxDisableValue(uint _maxDisableTokenValue) onlyManager external {
        require(_maxDisableTokenValue <= compTT.trendTokenMaxDisableValue(address(this)), "!maxDisableValue");
        maxDisableTokenValue = _maxDisableTokenValue;
    }


    /**
     * @notice Allows manager to set the maximum Trend Token supply
     * @param _maxSupply The new Trend Token max supply 
     */
    function _setMaxSupply(uint _maxSupply) onlyManager external {
        maxSupply = _maxSupply;
    }

    
    /**
     * @notice Allows manager to set amount of equity to be held in contract (remainder held in Dual Pools)
     */
    function setContractFactor(uint _contractFactor) internal {
        require(_contractFactor<=1e18, "max exceeded");
        contractFactor = _contractFactor;
    }


    /**
     * @notice Allows manager to set amount of equity to be held in contract (remainder held in Dual Pools)
     */
    function _setContractFactor(uint _contractFactor) onlyManager external {
        setContractFactor(_contractFactor);
    }


    // ------- TRADING BOT: UPDATE BOOL --------- //

    /**
     * @notice Allows trading bot to pause deposits of underlying
     * @dev Used when wanting to disable a token
     */
    function _depositsDisabled(address underlying, bool _state) onlyTradingBot external {
        depositsDisabled[underlying] = _state;
    }


    /**
     * @notice Allows manager to pause Trend Token
     * @dev Pauses mint/redeem/borrowRebalance of this Trend Token
     * @param _pause True if this Trend Token is to be paused
     */
    function _pauseTrendToken(bool _pause) onlyTradingBot external {
        trendTokenPaused = _pause;
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
        require(_allocations.length == getMarkets().length, "!length");
        uint allocationTotal = 0;
        for (uint i=0; i<_allocations.length; i++) {
            uint allocation = _allocations[i];
            require(allocation <= 1e18, "max allocation 100%.");
            allocationTotal += allocation;
        }
        require(allocationTotal == 1e18, "allocation != 100%");
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
        require(address(_dToken) != address(0) && tokenEntered(_dToken),"Token not enabled");
    }


    /** add ack BNB cannot disable
    *   Disables token market (cant borrow or collateral)
    *   Requires token is currently enabled
    *   Requires total value (contract, collateral, borrow) is below minTradeVal
    *       otherwise Equity will drop and therefore price of Trend Token
    */
    function _disableToken(IERC20 _bep20, uint[] calldata _allocations) onlyTradingBot external {
        IVBep20 dToken = dTokenSupportedRequire(_bep20);
        require(_bep20 != wbnb && tokenEquityVal(dToken) < maxDisableTokenValue,"cannot disable BNB");
        checkActiveToken(dToken);
        compDP.claimXDP(address(this));
        disableCol(dToken);
        _setDesiredAllocationsFresh(_allocations);
    }


    /** ADD BACK
     * @notice Allows trading bot to swap XDP for BNB
     * @dev Limited to the amount of XDP owned by the pool (balance-reserves)
     */
    function _swapXDPforBNB(uint _sellAmountXDP, uint _minOut) external onlyTradingBot {
        require(_sellAmountXDP <= balanceXDP(),"insufficent XDP balance");
        address[] memory _path = Lib.pathGenerator2(address(xdp), address(wbnb));
        xdp.approve(address(pancakeRouter), _sellAmountXDP);
        uint[] memory amounts = pancakeRouter.swapExactTokensForETH(_sellAmountXDP,  _minOut, _path, address(this), block.timestamp);
        amounts[amounts.length.sub(1)];
    }
    
    


    // -------------------- MANAGER: REDUCE TREND TOKENS ------------------- // 
    /**
     * @notice Allows manager to redeem Trend Tokens to fee recipient OR redeem for BNB --> XTT --> burn
     */

    /** 
     * @notice Allows manager to redeem Trend Tokens to fee recipient wallet
     */
    function _reduceTrendTokenReservesToRecipient(uint redeemAmtTrendToken) onlyManager external  {
        uint currentBalance = trendToken.balanceOf(address(this));
        require(redeemAmtTrendToken <= currentBalance,"insufficient TrendToken balance");
        trendToken.transfer(feeRecipient,redeemAmtTrendToken);
    }


    /**
     * @notice Sends performance fee (in Trend Tokens) to this Trend Token contract
     */
    function _distributePerformanceFee() onlyManager external {
        (uint trendTokenPrice, uint mintMBNB) = trendTokenToUSD(); 
        sendPerformanceFee(mintMBNB, trendTokenPrice);
    }


    // ------- TRADING BOT: DUAL POOL INTERATIONS --------- //


    /**
     * @notice Allows admin to supply collateral from contract holdings
     */
    function _supplyCollateral(IERC20 _depositBep20, uint supplyAmt) onlyTradingBot external {
        IVBep20 dToken = dTokenSupportedRequire(_depositBep20);
        collateralSupply(_depositBep20,dToken, supplyAmt);
    }


    /**
     * @notice Allows admin to supply collateral from contract holdings
     */
    function _redeemCollateral(IERC20 _redeemBep20, uint _redeemAmt) onlyTradingBot external {
        IVBep20 dToken = dTokenSupportedRequire(_redeemBep20);
        collateralRedeem(_redeemBep20,dToken,_redeemAmt);
    }


    /** 
     * @notice Claim XDP from Dual Pools and sends share to fee recipient 
     * @dev The remaining stays in the pool
     */
    function _redeemXDP() onlyTradingBot external {
        
        uint startingBalance = xdp.balanceOf(address(this));
        compDP.claimXDP(address(this));
        uint endingBalance = xdp.balanceOf(address(this));
        uint redeemAmtXDP = endingBalance.sub(startingBalance);
        
        if (accruedXDPtoFeeRecipient>0 && redeemAmtXDP>0) {

            uint transferAmount = Lib.getValue(redeemAmtXDP,accruedXDPtoFeeRecipient);
            xdp.transfer(feeRecipient,transferAmount);

        }
    }


    // ------ EXTERNAL VIEW FUNCTIONS ------------- //


    /**
     * @notice Returns the underlying price of dToken externally
     */
    function priceExt(IVBep20 _dToken) external view returns(uint) {
        return priceBEP20(_dToken) ;
    }


    /**
     * @notice Returns the XDP balance in this pool
     */
    function balanceXDPext() external view returns(uint) {
        return balanceXDP();
    }

    /**
     * @notice Returns the price of trend token (in USD) externally
     */
    function trendTokenToUSDext() external view returns(uint, uint) {
        return trendTokenToUSD();
    }


    /**
     * @return (uint price, uint trendTokenPrice, uint mintMBNB, uint trendTokenAmt, uint protocolFeePerc, int feeOrReward)
     */
    function trendTokenOutExternal(IERC20 _depositBep20, IVBep20 _dToken, uint _sellAmtBEP20) 
        external view returns(uint, uint, uint, uint, uint, int)  {
        return trendTokenOutCalculations(_depositBep20, _dToken, _sellAmtBEP20);
    }


    /**
     * @return (uint price, uint trendTokenPrice, uint mintMBNB, uint trendTokenAmt, uint protocolFeePerc, int feeOrReward)
     */
    function trendTokenInExternal(IERC20 _redeemBep20, IVBep20 _dToken, uint _redeemAmt) 
        external view returns(uint, uint, uint, uint, uint, int)  {
        return trendTokenInCalculations(_redeemBep20, _dToken, _redeemAmt);
    }


    /**
     * @notice External function for stored equity
     */
    function storedEquityExternal() external view returns(address[] memory,uint[] memory,uint[] memory,uint[] memory,uint[] memory,uint) {
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
    function storedEquity() internal view returns(address[] memory,uint[] memory,uint[] memory,uint[] memory,uint[] memory,uint) {  // returns current balances (uint)

        address[] memory dTokens = getMarkets();
        uint[] memory prices = new uint[](dTokens.length);
        uint[] memory conVals = new uint[](dTokens.length);
        uint[] memory colVals = new uint[](dTokens.length);
        uint[] memory borVals = new uint[](dTokens.length);
        uint assetValSum = 0; uint borrowValSum = 0;

        for (uint i = 0; i < dTokens.length; i++) {

            // fetch token and price
            IVBep20 dToken = IVBep20(dTokens[i]);
            uint tokenToUSD = priceBEP20(dToken);
            prices[i] = tokenToUSD;
            (uint tokenBal, uint borrowBal, uint rate) = screenshot(dToken);

            // contract balances
            uint contractVal = Lib.getValue(contractBal(dToken),tokenToUSD);
            conVals[i] = contractVal;

            // collateral values
            uint collateralAmt = Lib.getValue(tokenBal,rate);
            uint collateralVal = Lib.getValue(collateralAmt,tokenToUSD);
            colVals[i] = collateralVal;

            // borrow values
            uint borrowVal = Lib.getValue(borrowBal,tokenToUSD);
            borVals[i] = borrowVal;
            
            assetValSum = assetValSum.add(contractVal.add(collateralVal));
            borrowValSum = borrowValSum.add(borrowVal); 

        }

        uint netEquity = assetValSum.sub(borrowValSum);

        return (dTokens,prices,conVals,colVals,borVals,netEquity);

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
        uint mintTrendToken; 

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
        
        (address[] memory dTokens, // dToken (not underlying)
        uint[] memory prices,
        uint[] memory conVals,
        uint[] memory colVals,,
        uint netEquity) = storedEquity();

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


    function tokenEquityVal(IVBep20 _dToken) internal view returns(uint) {
        
        (address[] memory dTokens,,
        uint[] memory conVals,
        uint[] memory colVals,,) = storedEquity();

        for (uint i=0; i < dTokens.length; i++) {

            if (IVBep20(dTokens[i]) == _dToken) {

                return conVals[i].add(colVals[i]);

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

            _token.transfer(msg.sender, distributeAmount); 
            _token.transfer(referrer, distributeAmount); 


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
    function depositFresh(IERC20 _depositBep20, uint _sellAmtBEP20, address payable _referrer) internal pausedTrendToken returns(uint)  {
        
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
        trendToken.mint(msg.sender, trendTokenAmt);// mint and send Margin Token to Trader (after fees)

        // Require max supply isnt exceeded
        uint supplyTrendToken = trendToken.totalSupply();
        require(supplyTrendToken <= maxSupply,"Max Supply Exceeded.");

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
    function depositBNB(address payable _referrer) external nonReentrant payable {
        depositFresh(wbnb, msg.value, _referrer);
    }


    /**
    *   Payable function for buying Trend Tokens with BNB
    */
    function deposit(IERC20 _depositBep20, uint _sellAmtBEP20, address payable _referrer) external nonReentrant {
        _depositBep20.transferFrom(msg.sender, address(this), _sellAmtBEP20);
        depositFresh(_depositBep20, _sellAmtBEP20,_referrer);
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
        require(_amount <= contractBal(_dToken),"insufficent bal");

        if (_underlying == wbnb) {

            msg.sender.transfer(_amount); 

        } else {

            _underlying.transfer(msg.sender, _amount); 

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
    function redeemFresh(IERC20 _redeemBep20, uint _redeemAmt) internal pausedTrendToken returns(uint) { // change back to external
        
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
        trendToken.transfersFrom(msg.sender, address(this), trendTokenInAmt); 
        //sendPerformanceFee(mintMBNB,trendTokenPrice);

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
    function redeem(IERC20 _redeemBep20, uint _redeemAmt) external nonReentrant {
        redeemFresh(_redeemBep20, _redeemAmt);
    }


    // --------------- TRADE FUNCTIONALITY ----------------- // 

    /**
     * @notice Calculates the value of underlying to send back to the user
     */
    function tradeInfo(IERC20[] memory tokenInOut, IVBep20[] memory dTokensInOut, uint valueIn) internal view returns(uint valOutAfterBuy)  {

        (address[] memory dTokens,, // dToken (not underlying)
        uint[] memory conVals,
        uint[] memory colVals,,
        uint netEquity) = storedEquity();

        require(netEquity>0 && address(dTokensInOut[0]) != address(0) && address(dTokensInOut[1]) != address(0) &&
               dTokensInOut[0] != dTokensInOut[1] &&  tokenInOut.length == 2, "equity !> 0");

        int[] memory priorPostDeltaIn = new int[](2);
        int[] memory priorPostDeltaOut = new int[](2);
        uint[] memory tokenEquityInOut = new uint[](2);
        uint[] memory desiredAllocations = new uint[](2);

        for (uint i=0; i < dTokens.length; i++) {

            if (IVBep20(dTokens[i]) == dTokensInOut[0]) { // dTokenIn: sell

                tokenEquityInOut[0] = conVals[i].add(colVals[i]);
                desiredAllocations[0] = desiredAllocations[i];

            } else if (IVBep20(dTokens[i]) == dTokensInOut[1]) { // dTokenOut: buy

                tokenEquityInOut[1] = conVals[i].add(colVals[i]);
                desiredAllocations[1] = desiredAllocations[i];
                
            }
        
        }

        uint equityAfterSell = netEquity.add(valueIn);
        priorPostDeltaIn[0] = int(desiredAllocations[0]).sub(int(Lib.getAssetAmt(tokenEquityInOut[0],netEquity)));
        priorPostDeltaIn[1] = int(desiredAllocations[0]).sub(int(Lib.getAssetAmt(tokenEquityInOut[0].add(valueIn),equityAfterSell))); // post trade

        uint valAfterSell = incentiveModel.valueOutAfterSell(tokenInOut[0], valueIn, priorPostDeltaIn[0], priorPostDeltaIn[1], xtt.balanceOf(msg.sender));

        priorPostDeltaOut[0] = int(desiredAllocations[1]).sub(int(Lib.getAssetAmt(tokenEquityInOut[1],equityAfterSell)));
        priorPostDeltaOut[1] = int(desiredAllocations[1]).sub(int(Lib.getAssetAmt(tokenEquityInOut[1].sub(valAfterSell),equityAfterSell.sub(valAfterSell))));
        
        valOutAfterBuy = incentiveModel.valueOutAfterBuy(tokenInOut[1], valAfterSell, priorPostDeltaOut[0], priorPostDeltaOut[1]);

    }


    /**
     * @notice Executes desired trade
     * @param tokenInOut List of [tokenSell, tokenBuy]
     * @param sellAmt The amount of tokenSell to sell
     */
    function executeTrade(IERC20[] memory tokenInOut, uint sellAmt, uint _minOut) internal pausedTrendToken {
        compTT.tradeAllowed(address(this), sellAmt); 
        
        IVBep20[] memory dTokensInOut = new IVBep20[](2);
        dTokensInOut[0] = IVBep20(compTT.returnDToken(address(tokenInOut[0]))); 
        dTokensInOut[1] = IVBep20(compTT.returnDToken(address(tokenInOut[1]))); 

        uint valueIn = Lib.getValue(sellAmt,priceBEP20(dTokensInOut[0]));
        uint valOutAfterBuy = tradeInfo(tokenInOut,dTokensInOut,valueIn);
        uint outUnderlying = Lib.getAssetAmt(valOutAfterBuy,priceBEP20(dTokensInOut[1]));
        require(outUnderlying >= _minOut,"!minOut");
        
        sendUnderlyingOut(tokenInOut[1], dTokensInOut[1], outUnderlying);
    }

    /**
     * @notice Allows user to swap one underlying (BUSD) for another (BTCB)
     */
    function swapExactTokensForTokens(uint sellAmt, uint minOut, IERC20[] calldata tokenInOut) external nonReentrant {
        tokenInOut[0].transferFrom(msg.sender, address(this), sellAmt);
        executeTrade(tokenInOut,sellAmt,minOut);
    }


    /**
     * @notice Allows user to swap BNB for an underlying (BUSD)
     */
    function swapExactETHForTokens(IERC20[] calldata tokenInOut,uint minOut) external nonReentrant payable {
        require(tokenInOut[0] == wbnb, "input must be BNB");
        executeTrade(tokenInOut,msg.value,minOut);
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
        uint[] memory colVals,,
        uint netEquity) = storedEquity();

        for (uint i=0; i < dTokens.length; i++) {

            if (address(dToken) == dTokens[i]) {

                uint tokenEquity = conVals[i].add(colVals[i]);

                if (netEquity>0 && tokenEquity > 0) {

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


