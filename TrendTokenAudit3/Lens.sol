// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

// 1. Add underlying <--> underlying
//      - easy with one Trend Token. If many, should find the most optimal one
// 2. upon deployement, input compTT/compDP and get key addresses from there
// 3. adapt amountsAndFees to input array tokenInOut
// 4. adapt amountsandFeesTrade to input amountOut or amountIn

import "./ITrendToken.sol";
import "./ITrendTokenTkn.sol";
import "./ICompTT.sol";
import "./ICompDP.sol";
import "./Lib.sol";
import "./SafeMath.sol";
//import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v2.3.0/contracts/math/SafeMath.sol";

// incentive: 0x7Bd619A7E35bfd25BFA29FBF2c06F7e04C6c0807
// trend5: 0x50D5323350cD16b39Bd03657Ec6383A3bE2Bd462

contract TrendLens {
    /**
     * @notice Will need to change swapPair and amountsAndFeesTrade when more than one Trend Token
     */

    using SafeMath for uint;
    using SignedSafeMath for int;

    IERC20 public addressXTT = IERC20(0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee);
    ICompDP public compDP = ICompDP(0x022d21035c00594bdFBdAf77bEF76BBCe597d876);
    ICompTT public compTT = ICompTT(0x2B0B9618F453Fef6Fa0F750214f6c46006557e34);
    IERC20 public wbnb = IERC20(0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd);
    // compTT: 0x20e0827B4249588236E31ECE4Fe99A29a0Ec40bA
    ITrendToken public trend5 = ITrendToken(0x311171A7F7f77CB14ff499cE286A8D2F471C98B4);
    
    constructor() public {
    }



    // ----------- USER BALANCE ------------------ // 

    // trendTokens, underlyings, underlyingsUsd, 
    // totalEquity, totalTrendTokens, balanceXTT




    // ------------ TREND TOKEN GENERIC DATA AND SUMMARY --------------- // 


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
    // add amount user owns! 


    /**
     * @notice Fetches data for a specific Trend Token
     * @param _trendToken The Trend Token to get data on
     */
    function trendTokenData(ITrendToken _trendToken, address userAccount) public view returns(TrendTokenData memory) {

        (uint _price,) = _trendToken.trendTokenToUSDext();

        ITrendTokenTkn trendTokenTkn = _trendToken.trendToken();
        uint _supply = trendTokenTkn.totalSupply();

        uint userBal = trendTokenTkn.balanceOf(userAccount);


        //IIncentiveModel incentiveModel = _trendToken.incentiveModel();
        //uint _baseFee = incentiveMode.protocolFee();

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
    function trendTokenDataAll(ITrendToken[] memory trendTokens, address userAccount) public view returns(uint totalSupplyUsd, 
                                                                                                        uint tokenNum, 
                                                                                                        uint userToalSupplyUsd,
                                                                                                        uint userNumberTrendTokens, 
                                                                                                        uint balanceXTT,
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
        balanceXTT = addressXTT.balanceOf(userAccount);
        
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



    // if trend Token --> portfolio
    // if underlying --> Trend Token + portfolio - underlying
    
    /**
     * @notice Input 
     */
    function swapPairsOld(ITrendToken trendToken) external view returns(address[] memory) {

        address[] memory dTokens = compDP.getAssetsIn(address(trendToken));
        address dBNB = address(trendToken.dBNB());
        address[] memory tradeableTokens = new address[](dTokens.length); 

        for (uint i=0; i < dTokens.length; i++) {

            address dToken = dTokens[i];

            if (dToken == dBNB) {
                tradeableTokens[i] = address(wbnb);
            } else {
                tradeableTokens[i] = IVBep20(dToken).underlying();
            }

        }

        return tradeableTokens;
        
    }


    function trendTokenPortfolio(ITrendToken trendToken) public view returns(address[] memory portfolio) {

        address[] memory dTokens = compDP.getAssetsIn(address(trendToken));
        address dBNB = address(trendToken.dBNB());
        address[] memory tradeableTokens = new address[](dTokens.length); 

        for (uint i=0; i < dTokens.length; i++) {

            address dToken = dTokens[i];

            if (dToken == dBNB) {
                tradeableTokens[i] = address(wbnb);
            } else {
                tradeableTokens[i] = IVBep20(dToken).underlying();
            }

        }

        return tradeableTokens;

    }


    /**
     * @notice Removes token from portfolio
     * [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47,0xA808e341e8e723DC6BA0Bb5204Bafc2330d7B8e4],0xA808e341e8e723DC6BA0Bb5204Bafc2330d7B8e4
     * [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47,0xA808e341e8e723DC6BA0Bb5204Bafc2330d7B8e4],0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47
     * [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47,0xA808e341e8e723DC6BA0Bb5204Bafc2330d7B8e4],0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd
     * [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47,0xA808e341e8e723DC6BA0Bb5204Bafc2330d7B8e4],0xae13d989daC2f0dEbFf460aC112a837C89BAa7cc
     */
    function removeUnderlyingFromPortfolio(address[] memory portfolio, address token) public pure returns(address[] memory) {

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
    function portfolioAddTrendToken(address[] memory portfolio, address trendToken) public pure returns(address[] memory) {

        address[] memory newPort = new address[](portfolio.length.add(1));

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
    function swapPairs(ITrendToken trendToken, IERC20 underlying) external view returns(address[] memory) {

        if (address(trendToken) == address(0) && address(underlying) == address(0)) {

            address[] memory portfolio = trendTokenPortfolio(trend5);
            return portfolioAddTrendToken(portfolio, address(trend5));

        } else if (address(trendToken) == address(0)) { // underlying: portfolio-underlying + trendToken

            address[] memory portfolio = trendTokenPortfolio(trend5);
            address[] memory portfolioSubUnderlying = removeUnderlyingFromPortfolio(portfolio, address(underlying));
            return portfolioAddTrendToken(portfolioSubUnderlying, address(trend5));

        } else if (address(underlying) == address(0)) { // trendToken: portfolio

            return trendTokenPortfolio(trendToken);

        } else {

            revert("trendToken or underlying must be zero address");

        }
        
    }


    // -------------- DEPOSIT FUNCTIONS ---------------- //
    /**
     * @notice Calculates amount of Trend Token Out (based on input token) 
     *         and amount of token in (based on Trend Token out)
     */



    /**
     * @notice Input amount of token in and returns amount of Trend Token out and fee
     */
    function trendTokenOutAndFee(ITrendToken trendToken, IERC20 tokenIn, uint underlyingInAmt) public view returns(uint, int) {
        IVBep20 dToken = IVBep20(compTT.returnDToken(address(tokenIn)));
        (,,, uint trendTokenOut,,int feePercent) = trendToken.trendTokenOutExternal(tokenIn, dToken, underlyingInAmt);
        return (trendTokenOut,feePercent);
    }


    /**
     * @notice Input amount of trend token out and returns required token in and fee
     * @dev 
     * test: 0x311171A7F7f77CB14ff499cE286A8D2F471C98B4,0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47,10000000000
     */
    function underlyingInAndFee(ITrendToken trendToken, IERC20 tokenIn, uint trendTokenOutAmt) public view returns(uint, int) {
        IVBep20 dToken = IVBep20(compTT.returnDToken(address(tokenIn)));
        (uint trendTokenPrice,) = trendToken.trendTokenToUSDext();
        uint estUnderlerlyingInAmt = trendTokenOutAmt.mul(trendTokenPrice).div(trendToken.priceExt(dToken)); // 10 trendToken * $2 per trendToken / $1 underlying 
        (,,, uint trendTokenOut,, int feeOrReward) = trendToken.trendTokenOutExternal(tokenIn, dToken, estUnderlerlyingInAmt);
        uint underlyingIn = trendTokenOutAmt.mul(estUnderlerlyingInAmt).div(trendTokenOut);
        return (underlyingIn, feeOrReward);
    }



    /**
     * @notice Calculates the amount of Trend Token Out (if underlyingIn inputted) or Underlying In (if trendTokenOut inputted)
     * @dev One of underlyingIn or trendTokenOut must be zero
     */
    function depositAmountsAndFee(ITrendToken trendToken, IERC20 tokenIn, uint underlyingIn, uint trendTokenOut) public view returns(uint, int) {
        require(underlyingIn == 0 || trendTokenOut == 0, "One of underlyingIn or trendTokenOut must be 0.");
        if (underlyingIn != 0) {
            return trendTokenOutAndFee(trendToken, tokenIn, underlyingIn);
        } else {
            return underlyingInAndFee(trendToken, tokenIn, trendTokenOut);
        }
    }


    // -------------- REDEEMS ---------------- // 


    /**
     * @notice Input amount of token in and returns amount of Trend Token out and fee
     */
    function trendTokenInAndFee(ITrendToken trendToken, IERC20 tokenOut, uint underlyingOutAmt) public view returns(uint, int) {
        IVBep20 dToken = IVBep20(compTT.returnDToken(address(tokenOut)));
        (,,, uint trendTokenIn,,int feePercent) = trendToken.trendTokenInExternal(tokenOut, dToken, underlyingOutAmt);
        return (trendTokenIn,feePercent);
    }



    /**
     * @notice Input amount of trend token out and returns required token in and fee
     * @dev 
     */
    function underlyingOutAndFee(ITrendToken trendToken, IERC20 tokenOut, uint trendTokenInAmt) public view returns(uint, int feePercent) {
        IVBep20 dToken = IVBep20(compTT.returnDToken(address(tokenOut)));
        (uint trendTokenPrice,) = trendToken.trendTokenToUSDext();
        uint estUnderlerlyingOutAmt = trendTokenInAmt.mul(trendTokenPrice).div(trendToken.priceExt(dToken));
        (,,, uint trendTokenOut,, int feeOrReward) = trendToken.trendTokenInExternal(tokenOut, dToken, estUnderlerlyingOutAmt);
        uint underlyingIn = trendTokenInAmt.mul(estUnderlerlyingOutAmt).div(trendTokenOut);
        return (underlyingIn, feeOrReward);
    }



    /**
     * @notice Calculates the amount of Trend Token In (if underlyingOut inputted) or Underlying Out (if trendTokenIn inputted)
     * @dev One of underlyingIn or trendTokenOut must be zero
     */
    function redeemAmountsAndFees(ITrendToken trendToken, IERC20 tokenOut, uint underlyingOut, uint trendTokenIn) public view returns(uint, int) {
        require(underlyingOut == 0 || trendTokenIn == 0, "One of underlyingOut or trendTokenIn must be 0.");
        if (underlyingOut != 0) {
            return trendTokenInAndFee(trendToken, tokenOut, underlyingOut);
        } else {
            return underlyingOutAndFee(trendToken, tokenOut, trendTokenIn);
        }
    }


    // ---------- REDEEMS AND DEPOSITS TOTAL --------------- // 


    function balance(IERC20 token) public view returns(uint bal) {
        if (token == wbnb) {
            bal = msg.sender.balance;
        } else {
            bal = token.balanceOf(msg.sender);
        }
    }


    function walletBalance(address wallet, IERC20 token) public view returns(uint bal) {
        if (token == wbnb) {
            bal = wallet.balance;
        } else {
            bal = token.balanceOf(wallet);
        }
    }


    /**
     * @notice Calculates input, output, fees, and balances for Swap page
     * @ example [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x311171A7F7f77CB14ff499cE286A8D2F471C98B4],100000000000000,0
     */
    function amountsAndFees(address[] calldata tokenInOut, uint underlyingAmount, uint trendTokenAmount) 
    external view returns(uint calculatedAmount, int feeOrReward, uint balanceToken) {
        require(underlyingAmount == 0 || trendTokenAmount == 0, "One of underlyingAmount or trendTokenAmount must be 0.");
        if (tokenInOut[1] == address(trend5)) { // depositing undering for Trend Tokens
            //require(underlyingAmount>0 && trendTokenAmount == 0, "invalid values");
            IERC20 underlying = IERC20(tokenInOut[0]);
            ITrendToken trendToken = ITrendToken(tokenInOut[1]);
            (calculatedAmount, feeOrReward) =  depositAmountsAndFee(trendToken, underlying, underlyingAmount, trendTokenAmount);
            balanceToken = balance(underlying);
        } else { // redeeming Trend Tokens for Underlying
            //require(trendTokenAmount == 0 &&underlyingAmount>0, "invalid values");
            ITrendToken trendToken = ITrendToken(tokenInOut[0]);
            IERC20 underlying = IERC20(tokenInOut[1]);
            (calculatedAmount, feeOrReward) =  redeemAmountsAndFees(trendToken, underlying, underlyingAmount, trendTokenAmount);
            balanceToken = balance(underlying);
        }

    }


    // --------------- TRADING ------------ //

    /**
     * @notice Calculates amountOut and fees according to trade paramters for trend5 ONLY
        * @notice Sells tokenIn of amountIn for tokenOut
     * @dev Used for underlying --> underlying trade
     * @return Fee is negative if there is a reward
     * test [bnb,busd],0.0001: [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47],100000000000000,0 
     * test [busd,bnb],0.0001: [0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47,0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd],100000000000000 
     */
    function amountsAndFeesTradeHelper(IERC20[] memory tokenInOut, uint amountIn) internal view returns(uint amountOut, int fee) {

        // Create dToken list
        IVBep20[] memory dTokensInOut = new IVBep20[](2);
        dTokensInOut[0] = IVBep20(compTT.returnDToken(address(tokenInOut[0])));
        dTokensInOut[1] = IVBep20(compTT.returnDToken(address(tokenInOut[1])));
        
        // Get values
        uint priceIn = trend5.priceExt(dTokensInOut[0]);
        uint priceOut = trend5.priceExt(dTokensInOut[1]);
        uint valueIn = Lib.getValue(amountIn, priceIn);
        uint valueOut = trend5.tradeInfoExt(tokenInOut, dTokensInOut, valueIn);

        // Calculate fee 
        int amountLostOrGain = int(valueIn).sub(int(valueOut)); // gained if negative
        int avgTradeValue = (int(valueIn).add(int(valueOut))).div(2);
        fee = amountLostOrGain.mul(int(1e18)).div(avgTradeValue);

        // calculate amount out
        amountOut = Lib.getAssetAmt(valueOut,priceOut);

    }


    /**
     * @return balanceToken the balance of the token being sold (tokenIn)
     * example: [0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47,0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd],100000000000000,0
     * example: [0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47],100000000000000,0 
     */
    function amountsAndFeesTrade(IERC20[] calldata tokenInOut, uint amountIn, uint amountOut) 
        external view returns(uint calculatedAmount, int feeOrReward, uint balanceTokenIn)  {

        require(amountIn == 0 || amountOut == 0,"one should be zero");

        if (amountIn != 0) { 
        
            // @notice calculatedAmount is the calculated amount out
            (calculatedAmount, feeOrReward) = amountsAndFeesTradeHelper(tokenInOut, amountIn);

        } else { 

            uint priceIn = trend5.priceExt(IVBep20(compTT.returnDToken(address(tokenInOut[0]))));
            uint priceOut = trend5.priceExt(IVBep20(compTT.returnDToken(address(tokenInOut[1]))));

            uint estValueOut = Lib.getValue(amountOut,priceOut);
            uint estAmountIn = Lib.getAssetAmt(estValueOut,priceIn);
            (calculatedAmount, feeOrReward) = amountsAndFeesTradeHelper(tokenInOut, estAmountIn);
            uint valueOut = Lib.getValue(calculatedAmount,priceOut);

            // @notice calculatedAmount is the calculated amount in
            calculatedAmount = Lib.getAssetAmt(valueOut,priceIn); // amountIn

        }

        balanceTokenIn = balance(tokenInOut[0]);

    }

    // tradeInfoExt test
    //[0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47],[0x243fF2E429B4676d37085E7b5a1e1576f11508f3,0x2a98C6E2BD140513df99FFCC710902a2faFb3bb7],100000000000000
    //[0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47,0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd],[0x2a98C6E2BD140513df99FFCC710902a2faFb3bb7,0x243fF2E429B4676d37085E7b5a1e1576f11508f3],100000000000000

}


