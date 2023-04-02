// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

// 1. Add underlying <--> underlying
//      - easy with one Trend Token. If many, should find the most optimal one
// 2. upon deployement, input compTT/compDP and get key addresses from there

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

    using SafeMath for uint;

    IERC20 public addressXTT = IERC20(0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee);
    ICompDP public compDP = ICompDP(0x022d21035c00594bdFBdAf77bEF76BBCe597d876);
    ICompTT public compTT = ICompTT(0x2B0B9618F453Fef6Fa0F750214f6c46006557e34);
    IERC20 public wbnb = IERC20(0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd);
    
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

        (uint _price,) = _trendToken.trendTokenToUSD();

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
    function swapPairs(ITrendToken trendToken) external view returns(address[] memory) {

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
     */
    function underlyingInAndFee(ITrendToken trendToken, IERC20 tokenIn, uint trendTokenOutAmt) public view returns(uint, int) {
        IVBep20 dToken = IVBep20(compTT.returnDToken(address(tokenIn)));
        (uint trendTokenPrice,) = trendToken.trendTokenToUSD();
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
        (uint trendTokenPrice,) = trendToken.trendTokenToUSD();
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


    function balance(IERC20 token) public view returns(uint bal) {
        if (token == wbnb) {
            bal = msg.sender.balance;
        } else {
            bal = token.balanceOf(msg.sender);
        }
    }


    /**
     * @notice Calculates input, output, fees, and balances for Swap page
     * 
     */
    function amountsAndFees(ITrendToken trendToken, IERC20 underlying, uint underlyingAmount, uint trendTokenAmount, bool isDeposit) 
    external view returns(uint calculatedAmount, int feeOrReward, uint balanceToken) {
        require(underlyingAmount == 0 || trendTokenAmount == 0, "One of underlyingAmount or trendTokenAmount must be 0.");
        if (isDeposit) {
            (calculatedAmount, feeOrReward) =  depositAmountsAndFee(trendToken, underlying, underlyingAmount, trendTokenAmount);
        } else {
            (calculatedAmount, feeOrReward) =  redeemAmountsAndFees(trendToken, underlying, underlyingAmount, trendTokenAmount);
        }
        balanceToken = balance(underlying);
    }



    // ----------------- AMOUNTS OUT AND WALLET BALANCES ------------------- // 
    /**
     * @notice Used for swapping functionality
     * @dev Wallet Balances, tokens to trade, estimated amounts out, max out
     */







    // ------------------ USER TREND TOKEN ACCOUNT ---------------------- //
    /**
     * @notice Specific users total supplied to Trend Tokens and Borrows, 
     * @dev Given in USD, BTC, display XTT balance (maybe values)
     */







}


