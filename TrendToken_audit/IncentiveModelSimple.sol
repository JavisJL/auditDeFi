// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;
//pragma experimental ABIEncoderV2;

import "./IIncentiveModelSimple.sol";
import "./Lib.sol";
import "./SignedSafeMath.sol";
import "./SafeMath.sol";




contract IncentiveModelSimple is IIncentiveModelSimple {

    using SignedSafeMath for int;
    using SafeMath for uint;

    // ---------- PUBLIC VARIABLES ------------- // 


    bool public isIncentiveModel = true;

    address public admin;

    /**
     *@notice Base fee charged when depositing for Trend Tokens
     */
    uint public constant protocolFeeDeposit = 0.0025e18;

    /**
     *@notice Base fee charged when redeeming Trend Tokens or redeeming Trend Tokens
     */
    uint public constant protocolFeeRedeem = 0.0050e18;

    /**
     *@notice Base fee charged when redeeming Trend Tokens or redeeming Trend Tokens
     */
    uint public constant protocolFeeTrade = 0.0050e18;
    

    uint public lowDiscount = 0.20e18;
    uint public medDiscount = 0.40e18;
    uint public highDiscount = 0.60e18;

    uint public lowThreshold = 100e18;
    uint public medThreshold = 10000e18;
    uint public highThreshold = 100000e18;


    /**
     * @notice allocations can be +/- this percentage before deposit/redeem incentive or reward
     * @dev Allocation Delta will trigger a fee/reward if [-5%, 5%] if threshold = 5%
     */
    uint public threshold = 0.05e18;

    constructor() public {
        admin = msg.sender;
    }


    /**
     *  Changes the XTT holding threshold for 20%, 40%, and 60% trading fees on buying/selling Trend Tokens
     */
    function _updateTradeFeeDiscounts(uint _lowThres, uint _medThres, uint _highThres) external {
        require(msg.sender == admin,"!admin");
        require(_lowThres < _medThres && _medThres < _highThres,"!threshold");
        lowThreshold = _lowThres;
        medThreshold = _medThres;
        highThreshold = _highThres;
    }


    /**
     * @notice Returns the trade fee discount for holding XDP tokens
     * @param _traderBalance The traders balance of XDP tokens
     */
    function feeDiscount(uint _traderBalance) public view returns(uint discount) {
        if (_traderBalance >= highThreshold) {
            discount = highDiscount;
        } else if (_traderBalance >= medThreshold) {
            discount = medDiscount;
        } else if (_traderBalance >= lowThreshold) {
            discount = lowDiscount;
        } else {
            discount = 0;
        }
    }


    /** CHANGE TO MAINNET ADDRESSES
     * @notice Returns the base trading fee based on what token is deposited or redeemed
     * @dev Higher base trading fee if token has lower liquidity to estimate higher slippage
     */
    function feePerToken(IERC20 _bep20) public pure returns(uint) {
        if (_bep20 == IERC20(0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd)) {
            return 0.0020e18;
        } else if (_bep20 == IERC20(0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47)) {
            return 0.0025e18;
        } else if (_bep20 == IERC20(0xA808e341e8e723DC6BA0Bb5204Bafc2330d7B8e4)) {
            return 0.0035e18;
        }
    }



    // ------------- CALCULATING DEPOSIT/REDEEM FEE OR REWARD ---------------- //


    /**
     * @notice calculates the reward (or fee) when user deposits a token
     * @param _bep20 The underlying asset to be deposited
     * @param _valueIn The value of deposited _bep20 (un-used for now)
     * @param _priorDelta Desired allocations minus actual allocations before _bep20 deposit (positive if desired more asset) 
     * @param _postDelta Desired allocations minus estimated allocations after _bep20 deposit
     */
    function depositRewardOrFee(IERC20 _bep20, uint _valueIn, int _priorDelta, int _postDelta) public pure returns(uint reward, uint fee) {

        _valueIn; // may be used in the future to vary deposit reward (or fee)

        if (_priorDelta >= 0) { // require more of the token (net reward unless far excess) 

            uint priorDelta = uint(_priorDelta);
            reward = feePerToken(_bep20);

            if (_postDelta < 0) { // all deposit goes towards desired

                uint excess = uint(-_postDelta);

                if (priorDelta >= excess) { // most of the deposit goes towards desired (net reward) 

                    uint rewardFactor = Lib.getAssetAmt(uint(priorDelta.sub(excess)),priorDelta);
                    reward = Lib.getValue(reward, rewardFactor);

                } else {

                    uint feeFactor = Lib.getAssetAmt(uint(excess.sub(priorDelta)),excess);
                    fee = Lib.getValue(feeFactor,reward);
                    reward = 0;

                }

            }

        } else { // desires less of the token (full fee)

            fee = feePerToken(_bep20);

        }


    }


    function redeemRewardOrFee(IERC20 _bep20, uint _valueIn, int _priorDelta, int _postDelta) public pure returns(uint reward, uint fee) {

        _valueIn; // may be used in the future to vary deposit reward (or fee)
        
        if (_priorDelta <= 0) { // require less of the token (net reward unless far excess) 

            reward = feePerToken(_bep20);

            if (_postDelta < 0) { // all deposit goes towards desired

                uint priorDelta = uint(-_priorDelta);
                uint excess = uint(-_postDelta);

                if (priorDelta >= excess) { // most of the deposit goes towards desired (net reward) 

                    uint rewardFactor = Lib.getAssetAmt(uint(priorDelta.sub(excess)),priorDelta);
                    reward = Lib.getValue(reward, rewardFactor);

                } else {

                    uint feeFactor = Lib.getAssetAmt(uint(excess.sub(priorDelta)),excess);
                    fee = Lib.getValue(feeFactor,reward);
                    reward = 0;

                }

            }

        } else { // desires less of the token (full fee)

            fee = feePerToken(_bep20);

        }


    }



    /** 
     * @notice Caculates the trade fee (reward) perfect for specified trade
     * @dev Only considers the amount needed to be traded to get within threshold
     * param _valueIn The USD value being deposited by user
     * param _tokenEquity The contract plus collateral values of token being deposited
     * param _poolEquity The total equity in the pool
     * param _allocationDelta Desired allocation (percent) minus current allocation (percent)
     *                         Positive if Trend Token wants more of the asset
     * @return reward if deposit/withdrawal rebalances productively, fee if counterproductively
     * re-arrange this to have valueFor and valueAgainst
     */


    /** 
     * @notice Returns the total Trend Token deposit fee 
     * @dev May be negative if reward exceeds the protocolBaseFee (especially if high XDP discount)
     * @param reward The incentive reward if any
     * @param fee The incentive fee if any
     */
    function totalDepositFee(IERC20 _depositBEP20, uint _valueDeposit, int priorDelta, int postDelta, uint price, uint balanceXTT)  
             public view returns(int totalFee, uint protocolFeePerc, uint reward, uint fee) {
        price; // may be used in the future
        (reward, fee) = depositRewardOrFee(_depositBEP20,_valueDeposit, priorDelta, postDelta);
        uint feeFactorFromDiscountXTT = uint(1e18).sub(feeDiscount(balanceXTT));
        protocolFeePerc = protocolFeeDeposit.mul(feeFactorFromDiscountXTT).div(1e18);
        totalFee = int(protocolFeePerc).add(int(fee)).sub(int(reward));
        return (totalFee, protocolFeePerc, reward, fee);

    }


    // assume BUSD = 100%, currently at 90% ($90 BUSD, $10 BNB)
    // inputs,
    // valueDeposited = $50
    // allocationDelta = 10%

    // would like full reward ==> but thinks only $10 of the $50 is deposited, so gives full fee instead of reward 

    // needs to compare the allocation before and allocation after
    // compare the two, and give a discount if closer than desired? 


    /** 
     * @notice Returns the total Trend Token redeem fee 
     * @dev May be negative if reward exceeds the protocolBaseFee (especially if high XDP discount)
     * @param reward The incentive reward if any
     * @param fee The incentive fee if any
     */
    function totalRedeemFee(IERC20 _redeemBep20, uint _valueRedeem, int priorDelta, int postDelta, uint price, uint balanceXTT) 
             public view returns(int totalFee, uint protocolFeePerc, uint reward, uint fee) {
        price; // may be used in the future
        (reward, fee) = redeemRewardOrFee(_redeemBep20,_valueRedeem, priorDelta, postDelta);
        uint feeFactorFromDiscountXTT = uint(1e18).sub(feeDiscount(balanceXTT));
        protocolFeePerc = protocolFeeRedeem.mul(feeFactorFromDiscountXTT).div(1e18);
        totalFee = int(protocolFeePerc).add(int(fee)).sub(int(reward));
        return (totalFee, protocolFeePerc, reward, fee);

    }


    /**
     * @notice Returns the value out after _tokenIn is sold
     */
    function valueOutAfterSell(IERC20 _tokenIn, uint _valueIn, int priorDeltaIn, int postDeltaIn, uint balanceXTT) external view returns(uint redeemValue) {
        (uint rewardIn, uint feeIn) = depositRewardOrFee(_tokenIn,_valueIn, priorDeltaIn, postDeltaIn);
        uint feeFactorFromDiscountXTT = uint(1e18).sub(feeDiscount(balanceXTT));
        uint protocolFeePerc = protocolFeeTrade.mul(feeFactorFromDiscountXTT).div(1e18);
        int totalFeeIn = int(protocolFeePerc).add(int(feeIn)).sub(int(rewardIn));
        uint muliple = uint(int(1e18).sub(totalFeeIn));
        redeemValue = _valueIn.mul(muliple).div(1e18);
    }


    function valueOutAfterBuy(IERC20 _tokenOut, uint _valueAfterSell, int priorDeltaOut, int postDeltaOut) external view returns(uint buyValue)  {
        // calculates value out
        (uint rewardOut, uint feeOut) = redeemRewardOrFee(_tokenOut,_valueAfterSell, priorDeltaOut, postDeltaOut);
        uint multiple = uint(int(1e18).sub(int(feeOut).sub(int(rewardOut))));
        buyValue = _valueAfterSell.mul(multiple).div(1e18);

    }


}
