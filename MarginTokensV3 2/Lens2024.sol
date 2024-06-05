// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

// 1. Add underlying <--> underlying
//      - easy with one Trend Token. If many, should find the most optimal one
// 2. upon deployement, input compTT/compDP and get key addresses from there
// 3. adapt amountsAndFees to input array tokenInOut
// 4. adapt amountsandFeesTrade to input amountOut or amountIn


// 5. Fix Trend5 (input 1) --> BNB
//      - actual input amount is 0.97 since the calculated BNB amount is called

// ensure line 397 postAllocation

import "./IMarginToken.sol";
import "./ITrendTokenTkn.sol";
import "./IChainlinkOracle.sol";
import "./ICompTT.sol";
import "./ICompVenus.sol";
import "./Lib.sol";
import "./IVBep20.sol";
import "./IIncentiveModel.sol";
//import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v2.3.0/contracts/math/SafeMath.sol";

// may 10, 2023:
// incentive: 0x7Bd619A7E35bfd25BFA29FBF2c06F7e04C6c0807
// trend5: 0x5C35922181b3356da981c2735081dB0F09bB4c1C
// trendLens (may 5): 0xed0b7C114e6E500ef3042350FE508C4548405F18

// Changes
// 1) Add a trend token


contract TrendLensStorage {

    /**
     * @notice Displays tokens to rebalance on 'rebalance' page if above or -below this amount
     */
    int public minRebalanceValue = 10e18;

    /**
     * @notice Admin have ability to change some variables
     */
    address public admin;


    /**
     * mainnet: 0xDed21cdB9831B8002cC2BfaBc4D058a1CE54e074
     * testnet: 0xb2Ab79C452bD242862C7593A076833350CD73fB8
     */
    ICompTT public compTT = ICompTT(0x9195e05DA23a1DD6D48eFa71d2259E4E8C8Be642);


    /**
     * mainnet: 0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c
     * testnet: 0xA808e341e8e723DC6BA0Bb5204Bafc2330d7B8e4
     */
    IERC20 public btcb = IERC20(0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c);


}



contract TrendLens is TrendLensStorage {
    /**
     * @notice Will need to change swapPair and amountsAndFeesTrade when more than one Trend Token
     */


    constructor() {
        admin = msg.sender;
    }

    // -------------------- ADMIN PARAMETERS ---------------------- //


    /**
     * @notice Restricts actions to manager
     */
    modifier onlyAdmin() {
        require(msg.sender == admin, "!owner");
        _;
    } 


    function changeMinRebalanceValue(int newRebalanceValue) onlyAdmin() public {
        minRebalanceValue = newRebalanceValue;
    }



    // ------------ TREND TOKEN GENERIC DATA AND SUMMARY --------------- // 



    /**
     * @notice Returns TrendToken, BNB, and BTC prices
     */
    function chartPrices(IMarginToken _trendToken) public view returns(uint trendToken,uint bnb, uint btc) {
        (trendToken,) = _trendToken.trendTokenToUSDext();
        bnb = compTT.priceBEP20(IERC20(compTT.wbnb()));
        btc = compTT.priceBEP20(btcb);
    }


    /**
     * @notice General Trend Token Data found at dualpools.com/trendtokens
     */
    struct TrendTokenData {
        string name;
        uint userBalance;
        uint userBalanceUsd;
        uint price; // current price of Trend Token
        uint supply; // amount of Trend Tokens in circulated
        uint supplyUsd;
        uint performanceFee;
    } 



    /**
     * @notice Fetches data for a specific Trend Token
     * @param _trendToken The Trend Token to get data on
     */
    function trendTokenData(IMarginToken _trendToken, address userAccount) internal view returns(TrendTokenData memory) {

        (uint _price,,) = chartPrices(_trendToken);

        ITrendTokenTkn trendTokenTkn = _trendToken.trendToken();
        uint _supply = trendTokenTkn.totalSupply();

        uint userBal = trendTokenTkn.balanceOf(userAccount);

        return TrendTokenData({
            name: trendTokenTkn.name(),
            userBalance: userBal,
            userBalanceUsd: userBal*_price/1e18,
            price: _price,
            supply: _supply,
            supplyUsd: _supply*_price/1e18,
            performanceFee: _trendToken.performanceFee()
        });
    } 


    /**
     * @notice Returns token summary (number of tokens, total value, and general token data for each token)
     */
    function trendTokenDataAll(IMarginToken[] calldata trendTokens, address userAccount) external view returns(uint totalSupplyUsd, 
                                                                                                        uint tokenNum, 
                                                                                                        uint userToalSupplyUsd,
                                                                                                        uint userNumberTrendTokens, 
                                                                                                        uint _balanceXTT,
                                                                                                        TrendTokenData[] memory datas) {

        datas = new TrendTokenData[](trendTokens.length);

        for (uint i=0; i<trendTokens.length; i++) {

            TrendTokenData memory data = trendTokenData(trendTokens[i],userAccount);

            totalSupplyUsd += data.supplyUsd;
            userToalSupplyUsd += data.userBalanceUsd;

            if (data.userBalanceUsd > 0) {
                userNumberTrendTokens += 1;
            }

            datas[i] = data;

        }

        tokenNum = trendTokens.length;
        _balanceXTT = compTT.getXTTAddress().balanceOf(userAccount);
        
    }


    // ------------------- TREND TOKEN SPECIFIC DATA ---------------------- //


    /**
     * @notice Detailed Trend Token Data found at dualpools.com/trendtokens/specificTrendToken
     */
    struct TrendTokenDetailedData {
        IERC20[] portfolio; // list of tokens
        uint[] contractVals; // contract values in each token
        uint[] collateralVals; // collateral values in each token
        uint[] borrowVals; // USD value in each token
        uint[] exposure; // percent allocations to each asset
        uint netExposure; // sum of allocations (maybe factor in borrows somehow
        uint reserveShareXDP;
        uint borrowRebalanceRewardXDP; // XDP reward for public borrow rebalance
        uint protocolFee; // fee for deposit/redeem (found in incentive model)
        uint performanceFee; // performance fee percentage
        uint reservesTrendTokens; // amount of Trend Tokens in Rreserves
        uint reservesXDP; // amount of XDP in reserves
        uint maxDiscountXDP; // percentage discount for highDiscount
        uint maxDiscountThresholdXDP; // amount of XDP needed for highDiscount
    }


    // ----------------- SWAP ELEMENT ------------------- // 
    /**
     * @notice Used for swapping functionality
     * @dev Wallet Balances, tokens to trade, estimated amounts out, max out
     */


    /**
     * @notice Returns the ERC20 (underlying) tokens for the Trend Token portfolio
     * return ["0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd",
                 "0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47",
                 "0xA808e341e8e723DC6BA0Bb5204Bafc2330d7B8e4"]
     */
    function trendTokenPortfolio(IMarginToken trendToken) internal view returns(address[] memory portfolio) {

        (address[] memory tradeableTokens,,,,,) = trendToken.storedEquityExternal();
        return tradeableTokens;

    }


    /**
     * @notice Removes token from portfolio
     * [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47,0xA808e341e8e723DC6BA0Bb5204Bafc2330d7B8e4],0xA808e341e8e723DC6BA0Bb5204Bafc2330d7B8e4
     * [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47,0xA808e341e8e723DC6BA0Bb5204Bafc2330d7B8e4],0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47
     * [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47,0xA808e341e8e723DC6BA0Bb5204Bafc2330d7B8e4],0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd
     * [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47,0xA808e341e8e723DC6BA0Bb5204Bafc2330d7B8e4],0xae13d989daC2f0dEbFf460aC112a837C89BAa7cc
     */
    function removeUnderlyingFromPortfolio(address[] memory portfolio, address token) internal pure returns(address[] memory) {

        uint newPortLen = portfolio.length - 1; // one less of portfolio
        address[] memory newPort = new address[](newPortLen); // creates empty newPort array

        uint newPortCount = 0;
        for (uint i=0; i < portfolio.length; i++) {
            require(newPortCount < portfolio.length,"token must be in portfolio");

            address portToken = portfolio[i];

            if (portToken != token) { // only adds to new portfolio if not equal to token

                newPort[newPortCount] = portToken;
                newPortCount++;

            } 
        }
        return newPort;
    }



    /**
     * @notice adds trendToken to portfolio
     * test [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd],0x311171A7F7f77CB14ff499cE286A8D2F471C98B4
     * test [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47,0xA808e341e8e723DC6BA0Bb5204Bafc2330d7B8e4],0x311171A7F7f77CB14ff499cE286A8D2F471C98B4
     */
    function portfolioAddTrendToken(address[] memory portfolio, address trendToken) internal pure returns(address[] memory) {

        address[] memory newPort = new address[](portfolio.length + 1);

        for (uint i=0; i < portfolio.length; i++) {

                newPort[i] = portfolio[i];
        }

        newPort[portfolio.length] = trendToken; // adds trend token to the end

        return newPort;

    }


    /** 
     * test: 0x0000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000
     * test: 0x311171A7F7f77CB14ff499cE286A8D2F471C98B4,0x0000000000000000000000000000000000000000
     * test: 0x0000000000000000000000000000000000000000,0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47
     */
    function swapPairs(IMarginToken trendToken, address inputToken, address outputToken) external view returns(address[] memory) {
        require(inputToken != outputToken && outputToken != address(0),"invalid tokens");

        address[] memory portfolio = trendTokenPortfolio(trendToken);
        address[] memory portfolioPlusTrendToken = portfolioAddTrendToken(portfolio, address(trendToken));
        address[] memory portfolioPlusTrendTokenRemoveInput = removeUnderlyingFromPortfolio(portfolioPlusTrendToken, inputToken);
        address[] memory portfolioPlusTrendTokenRemoveInputAndOutput = removeUnderlyingFromPortfolio(portfolioPlusTrendTokenRemoveInput, outputToken);

        require(portfolioPlusTrendToken.length-2 == portfolioPlusTrendTokenRemoveInputAndOutput.length, "input and output token not in portfolio or a Trend Token.");
        
        return portfolioPlusTrendTokenRemoveInputAndOutput;

        
    }




    // ---------------------------- AMOUNTS OUT HELPER FUNCTIONS ----------------------------- // 
    // copied from MarginToken.sol and lightly modified
    // not enough contract byte size in MarginToken.sol to make these functions external


    /**
     * @notice Fetches the wallet of wallet for token
     * @dev Renamed from MarginToken.sol from balanceHolder()
     */
    function walletBalance(address wallet, IERC20 token) public view returns(uint bal) {
        if (token == IERC20(compTT.wbnb())) {
            bal = wallet.balance;
        } else {
            bal = token.balanceOf(wallet);
        }
    }


    function balanceXTT(address trader) public view returns(uint) {
        return compTT.getXTTAddress().balanceOf(trader);
    }

    /**
     * @notice Returns the desired allocations of a token based on index
     * @dev May be negative if desired borrow exceeds desired contract and collateral
     * @param tokenIndex The index of token in portfolioTokens
     */
    function desiredAllocation(IMarginToken marginToken, uint tokenIndex) public view returns(int) {
        int con = int(marginToken.contractAllo(tokenIndex));
        int col = int(marginToken.collateralAllo(tokenIndex));
        int bor = int(marginToken.borrowAllo(tokenIndex));
        return con + col - bor;
    }


    /**
     * @notice External function for stored equity
     */
    function storedEquity(IMarginToken trendToken) public view returns(address[] memory,uint[] memory,uint[] memory,uint[] memory,uint[] memory,uint) {
        return trendToken.storedEquityExternal();
    }


    /**
     * @notice Collects and calculates key information for tokenInfo
     * @dev Required due to 'stack too deep' issue in tokenInfo
     */
    function tokenInfoHelper(IMarginToken trendToken, IERC20 _token, uint depositAmt, uint redeemAmt) public view returns(uint depositVal, uint redeemVal, int tokenEquity, uint index, uint portfolioEquity) {
        
        (address[] memory tokens, 
        uint[] memory prices,
        uint[] memory conVals,
        uint[] memory colVals,
        uint[] memory borVals,
        uint netEquity) = storedEquity(trendToken);

        require(Lib.addressInList(address(_token),tokens),"!portfolio.");

        for (uint i=0; i < tokens.length; i++) {

            if (tokens[i] == address(_token)) {

                // stores USD values
                depositVal = Lib.getValue(depositAmt,prices[i]);
                redeemVal = Lib.getValue(redeemAmt,prices[i]);
                tokenEquity = int(conVals[i]) + (int(colVals[i])) - (int(borVals[i]));
                portfolioEquity =  netEquity;
                index = i;
            }
        }

    }

    /**
     * @notice Fetches data required for deposit/redeem incentives for a specific token
     * @dev Used by trendTokenOutCalculations() and trendTokenInCalculations() for incentive model 
     * @param _token The spefific token to get information on (e.g 0xbb..)
     * return priorDelta The differences between desired and current allocations prior to deposit or redeem of _token
     * return postDelta The differences between desired and current allocations post deposit or redeem of _token
     * return price The price of _token, 
     * return equity The total Trend Token equity in contract and Venus for entire portfolioTokens
     */
    function tokenInfo(IMarginToken marginToken, IERC20 _token, uint depositAmt, uint redeemAmt) public view returns(int priorDelta, int postDelta) {
        
        (uint depositVal, uint redeemVal, int tokenEquity, uint i, uint netEquity) = tokenInfoHelper(marginToken, _token, depositAmt, redeemAmt);

        if (netEquity>0) {

            // get delta prior to action 'desired - current' 
            int priorAllocations = tokenEquity * 1e18 / int(netEquity);
            priorDelta = desiredAllocation(marginToken,i) - priorAllocations;

            // require redeem value does not exceed net portfolio equity or token contract values
            require(redeemVal < netEquity && int(redeemVal) <= tokenEquity,"insufficient redeem"); // should look at contract values not tokenEquity

            // get delta post action 'desired - current'
            int postAllocation = (tokenEquity + int(depositVal) - int(redeemVal)) * 1e18 / (int(netEquity + depositVal - redeemVal));
            postDelta = desiredAllocation(marginToken,i) - int(postAllocation);

                
        } else { // starting conditions

            require(redeemVal==0,"redeem=0.");
            priorDelta = desiredAllocation(marginToken,i);
            postDelta = int(1e18);            
        
        }

    }


    // -------------- DEPOSIT FUNCTIONS (deposit underlyings) ---------------- //
    /**
     * @notice Calculates amount of Trend Token Out (based on input token) 
     *         and amount of token in (based on Trend Token out)
     */

    /**
     * @notice trendTokenInCalculations had 'stack too deep' issue
     */
    function trendTokenOutCalculationsHelper(IMarginToken trendToken, uint inValue, int feeOrReward) public view returns(uint) {
        uint inValueMinusFees = Lib.getValue(inValue, uint(int(1e18) - feeOrReward));

        // calculates trend token amount out based on price and fees
        (uint trendTokenPrice,) = trendToken.trendTokenToUSDext(); 
        uint trendTokenOutAmt = Lib.getAssetAmt(inValueMinusFees,trendTokenPrice);
        return trendTokenOutAmt;
    }


    /**
     * @notice Calculates the fees and trend token amounts out upon deposit
     * @dev Calls the Incentive Model contract to fetch base protocol fee and fee/reward incentive
     * @dev Copied from MarginTokens.sol but added trendToken parameter and incentiveModel local variable
     */
    function trendTokenOutCalculations(IMarginToken trendToken, IERC20 _depositBep20, uint _sellAmtBEP20, address trader) 
        public view returns(uint trendTokenAmt, uint protocolFeePerc, int feeOrReward)  {

        // calculates the difference between desired and actual positions before and after user deposit
        (int priorDelta, int postDelta) = tokenInfo(trendToken,_depositBep20,_sellAmtBEP20,0);
        uint priceToken = compTT.priceBEP20(_depositBep20);
        uint inValue = Lib.getValue(_sellAmtBEP20,priceToken);

        // calculates the value user deposited after subtracting fees from incentiveModel (fee or reward)
        (feeOrReward, protocolFeePerc,,) = trendToken.incentiveModel().totalDepositFee(_depositBep20, inValue, priorDelta, postDelta, priceToken, balanceXTT(trader)); 

        // calculates trend token amount out based on price and fees
        trendTokenAmt = trendTokenOutCalculationsHelper(trendToken, inValue, feeOrReward);

    }


    /**
     * @notice Calculates the amount of Trend Tokens out (if amountIn>0) or approximate amount of underlyingIn (if desiredAmountOut>0)
     * @param amountUnderlyingIn The user specified amount of underlying in. Zero if user specifies desired amount of trendTokenOut
     * @param desiredTrendTokenOut The user specified amount of trend token out. Zero if user specifies amount of underlying In
     */
    function trendTokenOutAmounts(IMarginToken trendToken, IERC20 _depositBep20, uint amountUnderlyingIn, uint desiredTrendTokenOut, address trader) public view returns(uint underlyingIn, uint trendTokenOut, int feeOrReward, uint poolReward) {
        
        // user will specify either underlyingIn or desired trendTokenOut
        require(amountUnderlyingIn == 0 || desiredTrendTokenOut == 0,"amountTokenIn or amountTrendTokenOut must be zero.");

        // create local variables to temporarily store values in if-else statement
        uint trendTokenOutAmt; uint protocolFeePerc; int _feeOrReward;

        // must calculate amount of underlyingIn if amountTrendTokenOut was specified
        if (desiredTrendTokenOut > 0) {

            // calculate estimated underlyingIn amount
            (uint trendTokenPrice,) = trendToken.trendTokenToUSDext();
            uint estUnderlyingIn =  desiredTrendTokenOut * trendTokenPrice / compTT.priceBEP20(_depositBep20);
            (trendTokenOutAmt, protocolFeePerc, _feeOrReward) = trendTokenOutCalculations(trendToken, _depositBep20, estUnderlyingIn, trader);
            underlyingIn = desiredTrendTokenOut * estUnderlyingIn / trendTokenOutAmt;
            trendTokenOut = desiredTrendTokenOut;

        } else {

            (trendTokenOutAmt, protocolFeePerc, _feeOrReward) = trendTokenOutCalculations(trendToken, _depositBep20, amountUnderlyingIn, trader);
            underlyingIn = amountUnderlyingIn;
            trendTokenOut = trendTokenOutAmt;

        }

        feeOrReward = _feeOrReward;
        poolReward = protocolFeePerc;

    }



    // -------------- REDEEMS (deposit trend tokens) ---------------- // 


    /**
     * @notice trendTokenInCalculations had 'stack too deep' issue
     */
    function trendTokenInCalculationsHelper(IMarginToken trendToken, uint outValueEst, int feeOrReward) public view returns(uint) {
        uint outValueAddFees = Lib.getValue(outValueEst, uint(int(1e18) + feeOrReward)); 
        (uint trendTokenPrice,) = trendToken.trendTokenToUSDext(); 
        uint trendTokenInAmt = Lib.getAssetAmt(outValueAddFees,trendTokenPrice); 
        return trendTokenInAmt;
    }

    /**
     * @notice Calculates the amount of underlying to send to manager after deposit of Trend Tokens
     * @dev Takes into account the redeem fee calculation from incentive model
     */
    function trendTokenInCalculations(IMarginToken trendToken, IERC20 _redeemBep20, uint _redeemAmt, address trader) 
        internal view returns(uint trendTokenInAmt, uint protocolFeePerc, int feeOrReward)  {

        (int priorDelta, int postDelta) = tokenInfo(trendToken,_redeemBep20,0,_redeemAmt);
        uint price = compTT.priceBEP20(_redeemBep20);
        uint outValueEst = Lib.getValue(_redeemAmt,price); 

        // calculate value to send to user including fees
        (feeOrReward, protocolFeePerc,,) = trendToken.incentiveModel().totalRedeemFee(_redeemBep20, outValueEst, priorDelta, postDelta, price, balanceXTT(trader));

        // store key variables 
        trendTokenInAmt = trendTokenInCalculationsHelper(trendToken, outValueEst, feeOrReward);

    }


    function trendTokenInAmounts(IMarginToken trendToken, IERC20 _redeemBep20, uint desiredTrendTokenIn, uint amountUnderlyingOut, address trader) public view returns(uint trendTokenIn, uint underlyingOut, int feeOrReward, uint poolReward) {

        // user will specify either underlyingIn or desired trendTokenOut
        require(desiredTrendTokenIn == 0 || amountUnderlyingOut == 0,"amountTokenIn or amountTrendTokenOut must be zero.");

        // create local variables to temporarily store values in if-else statement
        uint trendTokenInAmt; uint protocolFeePerc; int _feeOrReward;

        // must calculate amount of underlyingIn if amountTrendTokenOut was specified
        if (desiredTrendTokenIn > 0) {

            // calculate estimated underlyingOut amount
            (uint trendTokenPrice,) = trendToken.trendTokenToUSDext();
            uint estUnderlyingOutAmt = desiredTrendTokenIn * trendTokenPrice / compTT.priceBEP20(_redeemBep20); // small number incase low contract balance
            (trendTokenInAmt, protocolFeePerc, _feeOrReward) = trendTokenInCalculations(trendToken, _redeemBep20, estUnderlyingOutAmt, trader);
            underlyingOut = desiredTrendTokenIn * estUnderlyingOutAmt / trendTokenInAmt;
            trendTokenIn = desiredTrendTokenIn;

        } else {

            (trendTokenInAmt, protocolFeePerc, _feeOrReward) = trendTokenInCalculations(trendToken, _redeemBep20, amountUnderlyingOut, trader);
            underlyingOut = amountUnderlyingOut;
            trendTokenIn = trendTokenInAmt;

        }

        feeOrReward = _feeOrReward;
        poolReward = protocolFeePerc;

    }


    // --------------- TRADING ------------ //


    //function swapInfoFreshHelper() internal view returns()


    /**
     * @notice Performs intermediary calculations for swapInfo()
     * return tokenEquityInOut The equity of tokenIn and tokenOut
     * return desiredAllos The desired allocations of tokenIn and tokenOut
     * return netEquity The net equity of the entire portfolio
     */
    function swapInfoFresh(IMarginToken trendToken, IERC20[] memory tokensInOut) internal view returns(int[] memory, int[] memory) {

        // create local return variables (negative if borrow)
        int[] memory tokenEquityInOut = new int[](2);
        int[] memory desiredAllos = new int[](2);

        // requires all tokens for netEquity value
        (address[] memory tokens,,
        uint[] memory conVals,
        uint[] memory colVals,
        uint[] memory borVals,) = storedEquity(trendToken);

        for (uint i=0; i < tokens.length; i++) {


            if (IERC20(tokens[i]) == tokensInOut[0]) { 

                tokenEquityInOut[0] = int(conVals[i] + colVals[i]) - int(borVals[i]);
                desiredAllos[0] = int(trendToken.contractAllo(i) + trendToken.collateralAllo(i)) - int(trendToken.borrowAllo(i));

            } else {  // then must be tokenOut

                tokenEquityInOut[1] = int(conVals[i] + colVals[i]) - int(borVals[i]);
                desiredAllos[1] = int(trendToken.contractAllo(i) + trendToken.collateralAllo(i)) - int(trendToken.borrowAllo(i));  

            }
        
        }

        return (tokenEquityInOut, desiredAllos);

    }


    /** 
     * @notice Calculates the value of tokenOut to send back to the user
     * @dev Used in executeTrade()
     * @param tokenInOut An array of [tokenIn, tokenOut]
     * @param valueIn The value of tokenIn sent by user
     */
    function swapInfo(IMarginToken trendToken, IERC20[] memory tokenInOut, uint valueIn, address trader) internal view returns(uint valOutAfterBuy)  {

        // helper function gets equity of tokenInOut, desired allocations, and total portfolio
        (int[] memory tokenEquityInOut, int[] memory desiredAllos) = swapInfoFresh(trendToken,tokenInOut);
        (,,,,,uint netEquity) = storedEquity(trendToken);

        // ensures tokenIn and tokenOut are not zero address or the same token, and are only 2 tokens
        require(netEquity>0 && address(tokenInOut[0]) != address(0) && tokenInOut[0] != tokenInOut[1] &&  tokenInOut.length == 2, "equity!>0");

        // local variables to store prior and post delta (difference in desired-current allocations) for tokenIn and tokenOut
        int[] memory priorPostDeltaIn = new int[](2);
        int[] memory priorPostDeltaOut = new int[](2);

        // fetch incentiveModel address
        //IIncentiveModel incentiveModelX = trendToken.incentiveModel();

        // calculates the value (USD) of token being sold
        //uint equityAfterSellInX = netEquity.add(valueIn); // should always be positive
        int tokenInEquityAfterSell = tokenEquityInOut[0] + int(valueIn); // may be negative (if borrow)
        priorPostDeltaIn[0] = desiredAllos[0] - (tokenEquityInOut[0] * 1e18 / int(netEquity)); // 1 - 13/30 = 56%
        priorPostDeltaIn[1] = desiredAllos[0] - (tokenInEquityAfterSell * 1e18 / int(netEquity + valueIn)); // 1 - (13+1)/ 31 = 54%        
        uint valAfterSellOut = trendToken.incentiveModel().valueOutAfterSell(tokenInOut[0], valueIn, priorPostDeltaIn[0], priorPostDeltaIn[1], balanceXTT(trader));

        // calculates the value (USD) of token being purchased
        priorPostDeltaOut[0] = desiredAllos[1] - (tokenEquityInOut[1] * 1e18 / int(netEquity + valueIn)); // 0 - 17/31 = -55%
        uint equityAfterSellOut = netEquity + valueIn - valAfterSellOut;
        int tokenOutEquityAfterSell = tokenEquityInOut[1] - int(valAfterSellOut);
        priorPostDeltaOut[1] = desiredAllos[1] - (tokenOutEquityAfterSell * 1e18 / int(equityAfterSellOut)); // 0 - (17-1)/(31-1) = -47%
        valOutAfterBuy = trendToken.incentiveModel().valueOutAfterBuy(tokenInOut[1], valAfterSellOut, priorPostDeltaOut[0], priorPostDeltaOut[1]);

    }

    /**
     * @notice Calculates the rewardOrFee and protocolFee for swapping 
     * @return rewardOrFee Calculated based on the difference in expected output and calculated output
     * @return protocolFee Either protocolFeeDeposit, protocolFeeRedeem, protocolFeeTrade and subject to fee discount
     */
    function swapFeeCalculator(IMarginToken trendToken, IERC20 tokenIn, IERC20 tokenOut, uint amountIn, uint calculatedOut) public view returns(int rewardOrFee, uint protocolFee) {

        // Fetch protocol fee for trading
        IIncentiveModel incentiveModel = trendToken.incentiveModel();
        protocolFee = incentiveModel.protocolFeeTrade();

        // Calculated expected output after fee
        uint expectedOut = compTT.priceBEP20(tokenIn) * amountIn / compTT.priceBEP20(tokenOut);
        uint expectedOutWithProtocolFee = expectedOut * (uint(1e18) + protocolFee);

        // Calculated feeOrReward
        int difference =  int(expectedOutWithProtocolFee) - int(calculatedOut); // may need to flip it
        int average = int(expectedOutWithProtocolFee + calculatedOut);
        rewardOrFee = difference * 1e18 / average;

    }


    function swapAmountsHelper(IMarginToken trendToken, IERC20[] memory tokenInOut, uint exactAmountIn, address trader) public view returns(uint) {
        uint valueIn = Lib.getValue(exactAmountIn,compTT.priceBEP20(tokenInOut[0]));
        uint valOutAfterBuy = swapInfo(trendToken, tokenInOut, valueIn, trader);
        uint outUnderlying = Lib.getAssetAmt(valOutAfterBuy, compTT.priceBEP20(tokenInOut[1]));
        return outUnderlying;

    }


    /**
     * @notice Calculates the amounts and fees for swapping one asset (i.e BTC) for another (i.e ETH)
     */
    function swapAmounts(IMarginToken trendToken, IERC20 tokenIn, IERC20 tokenOut, uint exactAmountIn, uint desiredAmountOut, address trader) public view returns(uint underlyingIn, uint underlyingOut, int feeOrReward, uint poolReward) {

        // user will specify either underlyingIn or desired trendTokenOut
        require(exactAmountIn == 0 || desiredAmountOut == 0,"exactAmountIn or desiredAmountOut must be zero.");

        // reformat tokenIn and tokenOut inputs to array
        IERC20[] memory tokenInOut = new IERC20[](2);
        tokenInOut[0] = tokenIn;
        tokenInOut[1] = tokenOut;

        if (desiredAmountOut > 0) {

            // calculate estimate underlyingIn
            uint startAmountIn = desiredAmountOut * compTT.priceBEP20(tokenOut) / compTT.priceBEP20(tokenIn);
            uint underlyingOutCalc = swapAmountsHelper(trendToken, tokenInOut, startAmountIn, trader);
            underlyingIn = desiredAmountOut * startAmountIn / underlyingOutCalc;
            underlyingOut = desiredAmountOut;

        } else {

            underlyingIn = exactAmountIn;
            underlyingOut = swapAmountsHelper(trendToken, tokenInOut, underlyingIn, trader);

        }

        (feeOrReward, poolReward) = swapFeeCalculator(trendToken, tokenIn, tokenOut, underlyingIn, underlyingOut);

    }


    // -------------------------- AMOUNTSOUT ENDPOINT ----------------------------- //


    /**
     * @notice Used by frontend to fetch amountsIn or amountsOut depending on users input
     * @param tokenIn The underlying or trend token in
     * @param tokenOut The underlying or trend token out 
     * @param amountIn The amount of tokenIn specified by user (if applicable)
     * @param amountOut The amount of tokenOut specified by user (if applicable)
     */
    function amountsOut(IMarginToken trendTokenContract, IERC20 tokenIn, IERC20 tokenOut, uint amount, bool directionIn, address trader) 
        external view returns(uint amountIn, uint amountOut, int feeOrReward, uint poolReward) {

        // user will specify either underlyingIn or desired trendTokenOut
        require(amountIn == 0 || amountOut == 0,"exactAmountIn or desiredAmountOut must be zero.");

        ITrendTokenTkn trendTokenTkn = trendTokenContract.trendToken();

        // fetch desired amounts based on amount and direction
        amountIn = amount;
        amountOut = 0;
        if (!directionIn) {
            amountIn = 0;
            amountOut = amount;
        }

        // deposit function (trend token out)

        if (address(tokenOut) == address(trendTokenTkn)) {

            (amountIn, amountOut, feeOrReward, poolReward) = trendTokenOutAmounts(trendTokenContract, tokenIn, amountIn, amountOut, trader);

        // redeem function (trend token in)
        } else if (address(tokenIn) == address(trendTokenTkn)) {

            (amountIn, amountOut, feeOrReward, poolReward) = trendTokenInAmounts(trendTokenContract, tokenOut, amountIn, amountOut, trader);

        // swap function
        } else {

            (amountIn, amountOut, feeOrReward, poolReward) = swapAmounts(trendTokenContract, tokenIn, tokenOut, amountIn, amountOut, trader);

        }

    }



    // ---------------------- TREND TOKEN DETAILED ------------------------- //


    /**
     * @notice Used to reduce contract size
     */
    struct StoredEquity { 
        address[] tokens;
        uint[] prices;
        uint[] cons;
        uint[] cols;
        uint[] bors;
        uint total;
    }

    /**
     * @notice Calculates allocations and desired
     * @dev Used to work around "stack too deep" error
     */
    function trendTokenDetailedHelper(IMarginToken trendToken, StoredEquity memory se) internal view returns(int[] memory, int[] memory) {

        int[] memory allocations = new int[](se.cons.length);
        int[] memory desired = new int[](se.cons.length);

        for (uint i=0; i < se.cons.length; i++) {

            // calculate net exposure to asset
            allocations[i] = (int(se.cons[i]) + int(se.cols[i]) - int(se.bors[i])) * 1e18 / int(se.total);

            // calculate desired exposure to an asset
            desired[i] = int(trendToken.contractAllo(i)) + int(trendToken.collateralAllo(i)) - int(trendToken.borrowAllo(i));

        }

        return (allocations, desired);

    }


    function trendTokenDetailed(IMarginToken trendToken) public view returns(address[] memory tokens,
                                                                               uint[] memory prices,
                                                                               uint[] memory con,
                                                                               uint[] memory col,
                                                                               uint[] memory bor,
                                                                               int[] memory allocations, // current
                                                                               int[] memory desired, // desired
                                                                               uint total) {
        
        (tokens, prices, con, col,bor, total) = trendToken.storedEquityExternal();

        // used to save contract size in trendTokenDetailedHelper
        StoredEquity memory _storedEquity = StoredEquity({
            tokens: tokens,
            prices: prices,
            cons: con,
            cols: col,
            bors: bor,
            total: total
        });

        (allocations, desired) = trendTokenDetailedHelper(trendToken,_storedEquity);

    }



    /**
     * @notice Finds the reward (or fee) of a trendToken for each underlying asset
     * @dev Whether it is a reward or fee depends on current and desired allocations
     */
    function returnFeePerToken(IMarginToken trendToken, address _underlying) public view returns(uint) {
        IIncentiveModel incentiveModel = IIncentiveModel(trendToken.incentiveModel());
        uint reward = incentiveModel.feePerToken(_underlying);
        return reward;
    }


    /**
     * @notice returns the reward and action for that reward for each token
     * @return amounts Negative if allocations is less than desired (frontend assigns "buy" or "sell" accordingly)
     */
    function trendTokenDetailed2(IMarginToken trendToken) public view returns(address[] memory, uint[] memory, int[] memory) {
    

        (address[] memory portfolio,,,,,
        int[] memory allocations, 
        int[] memory desired, 
        uint total) =  trendTokenDetailed(trendToken); 

        uint[] memory actionReward = new uint[](portfolio.length);
        int[] memory amounts = new int[](portfolio.length);

        for (uint i=0; i < portfolio.length; i++) {

            actionReward[i] = returnFeePerToken(trendToken, portfolio[i]);
            amounts[i] = int(allocations[i] - int(desired[i])) * int(total) / int(1e18);

        }

        return (portfolio, actionReward, amounts);

    }


    // ---------------------- REBALANCE PAGE (need to be redone after new rebalance contracts) ----------------------------- //

    /**
     * @notice Sorts _tokens based on _arr values
     * @return Sorted tokens
     */
    function sortArray(address[] memory _tokens, int[] memory _arr) internal pure returns(address[] memory, int[] memory, uint) {

        uint256 l = _arr.length;
        uint numberOfNegatives = 0;

        int[] memory arr = new int[](l);
        for(uint i=0;i<l;i++) { // creates new array from arr_
            arr[i] = _arr[i];
            if (_arr[i] < 0) {
                numberOfNegatives = numberOfNegatives + 1;
            }
        } 

        address[] memory tokens = new address[](l);
        for(uint i=0;i<l;i++) {tokens[i] = _tokens[i];} // creates new array from arr_

        for(uint i=0; i<l; i++) {

            for(uint j=i+1; j<l; j++) {
                
                if(arr[i]<arr[j]) { // replace j and i

                    int temp = arr[j];
                    arr[j] = arr[i];
                    arr[i] = temp;

                    address tempTkn = tokens[j];
                    tokens[j] = tokens[i];
                    tokens[i] = tempTkn;

                }

            }
        }

        return (tokens, arr, numberOfNegatives);
    }


    /**
     * @notice Calculates the removeTokens, addTokens, and floor trend token back! 
     * @dev numberOfNegatives are when desired>current (sell Tokens) 
     */
    function rebalancePage(IMarginToken trendToken) public view returns(address[] memory, address[] memory) {

        // fetches tokens, action (desired buy or sell), and amounts (to be bought or sold)
        (address[] memory token,,int[] memory amounts) = trendTokenDetailed2(trendToken);

        // sorted by positive to negative (most buyTokens to most sellTokens)
        (address[] memory sortedTokens, int[] memory sortedAmounts, uint numberOfSellTokens) = sortArray(token, amounts);
      

        // get first numberOfBuyTokens in sortedTokens
        uint numberOfBuyTokens = sortedTokens.length - numberOfSellTokens;
        address[] memory sortedBuyTokens = new address[](numberOfBuyTokens);
        for(uint i=0; i<numberOfBuyTokens; i++) {  // stops when sortedBuyTokens filled
            if (sortedAmounts[i] > minRebalanceValue) {
                sortedBuyTokens[i] = sortedTokens[i];
            }
        }

        // gets last numberOfSellTokens in sortedTokens (reverse order)
        uint startIndex = sortedTokens.length-1; // starts at the end
        address[] memory sortedSellTokens = new address[](numberOfSellTokens);
        for(uint i=0; i<numberOfSellTokens; i++) { // fills up sortedSellTokens from end of list
            if (sortedAmounts[startIndex] < -minRebalanceValue) {
                sortedSellTokens[i] = sortedTokens[startIndex];
                startIndex = startIndex - 1;
            }
        }

        return (sortedBuyTokens, sortedSellTokens);
       

    }



}







