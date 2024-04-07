// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;
//pragma experimental ABIEncoderV2;

import "./IIncentiveModel.sol";
import "./Lib.sol";
import "./SignedSafeMath.sol";
import "./SafeMath.sol";

// ---------- CHANGES ----------- // 
// 1) Change fee amount to be based on amount in portfolio AFTER trade
//      - reduce exploit of larger redeems dropping price

// Add to Github Repo
// 1) Create updatable feePerToken() underlying:fee pairs, similar to CompTT (make sure cant duplicate underlying)
//      - add array of underlying
// 2) Upgradeable protocolFeeDeposit, protocolFeeRedeem, protocolFeeTrade
//      - keep discount and threshold fixed 

contract IncentiveModel is IIncentiveModel {

    using SignedSafeMath for int;
    using SafeMath for uint;

    // ---------- PUBLIC VARIABLES ------------- // 

    /**
     * @notice Used as a sanity check when adding incentive model to Trend Token
     */
    bool public constant isIncentiveModel = true;

    /**
     * @notice Has permission to make changes
     */
    address public admin;

    /**
     *@notice Base fee charged when depositing for Trend Tokens
     */
    uint public protocolFeeDeposit = 0.0015e18;

    /**
     *@notice Base fee charged when redeeming Trend Tokens for underlying
     */
    uint public protocolFeeRedeem = 0.0025e18;

    /**
     *@notice Base fee charged when trading underlying for underlying
     */
    uint public protocolFeeTrade = 0.0015e18;
    

    /**
     * @notice Discounts when meeting low, med, and high XTT Thresholds
     */
    uint public constant lowDiscount = 0.20e18;
    uint public constant medDiscount = 0.40e18;
    uint public constant highDiscount = 0.80e18;

    /**
     * @notice Amount of XTT required to be held to receive low, med, and high discounts
     */
    uint public lowThreshold = 100e18;
    uint public medThreshold = 10000e18;
    uint public highThreshold = 100000e18;


    /**
     * @notice Maps ERC20 token to its base reward/fee when depositing or redeeming
     * @dev If BNB: 0.50%, then 0.50% reward when depositing BNB if protocol desires more
     *                          0.50% fee when redeeming BNB if protocol desires less
     */
    mapping(address => uint) public feePerToken;


    /**
     * @notice Maintains a list of all underlying assets that are included in the feePerToken mapping
     *         This allows this underlying to be deposited, redeemed, or traded
     */
    IERC20[] public allUnderlying;


    /**
     * @notice Emitted when updated associated values
     */
    event UpdateFeeDiscount(uint oldLow, uint oldMed, uint oldHigh, uint newLow, uint newMed, uint newHigh);
    event UpdateDepositFee(uint oldFee, uint newFee);
    event UpdateRedeemFee(uint oldFee, uint newFee);
    event UpdateProtocolFee(uint oldFee, uint newFee);



    constructor() public {
        admin = msg.sender;
    }

    
    /**
     *  Changes the XTT holding threshold for 20%, 40%, and 60% trading fees on buying/selling Trend Tokens
     */
    function _updateTradeFeeDiscounts(uint _lowThres, uint _medThres, uint _highThres) external {
        require(msg.sender == admin,"!admin");
        require(_lowThres < _medThres && _medThres < _highThres && _highThres <= 1e18,"!threshold");
        uint oldLow = lowThreshold;
        uint oldMed = medThreshold;
        uint oldHigh = highThreshold;
        lowThreshold = _lowThres;
        medThreshold = _medThres;
        highThreshold = _highThres;
        emit UpdateFeeDiscount(oldLow, oldMed, oldHigh, lowThreshold, medThreshold, highThreshold);
    }


    /**
     * @notice Updates deposit fee when buying Trend Tokens
     */
    function _updateDepositFee(uint _newDepositFee) external {
        require(msg.sender == admin,"!admin");
        require(_newDepositFee <= 0.05e18,"max 5%");
        uint oldFee = protocolFeeDeposit;
        protocolFeeDeposit = _newDepositFee;
        emit UpdateDepositFee(oldFee, protocolFeeDeposit);
    }


    /**
     * @notice Updates redeem fee when selling Trend Tokens
     */
    function _updateRedeemFee(uint _newRedeemFee) external {
        require(msg.sender == admin,"!admin");
        require(_newRedeemFee <= 0.10e18,"max 10%");
        uint oldFee = protocolFeeRedeem;
        protocolFeeRedeem = _newRedeemFee;
        emit UpdateRedeemFee(oldFee, protocolFeeRedeem);
    }


    /**
     * @notice Updates redeem fee when trading underlying for underlying
     */
    function _updateProtocolFeeTrade(uint _newProtocolFee) external {
        require(msg.sender == admin,"!admin");
        require(_newProtocolFee <= 0.050e18,"max 5%");
        uint oldFee = protocolFeeTrade;
        protocolFeeTrade = _newProtocolFee;
        emit UpdateProtocolFee(oldFee, protocolFeeTrade);
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


    /**
     * @notice Allows admin to change the fee/reward for deposit, redeem, and trade for each token
     * @ testnet
     * BNB: 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd ==> 2000000000000000
     * BUSD: 0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47 ==> 2500000000000000
     * BTC: 0xA808e341e8e723DC6BA0Bb5204Bafc2330d7B8e4 ==> 3000000000000000
     */
    function _updateFeePerToken(IERC20 underlying, uint feeOrReward) external {
        require(msg.sender == admin,"!admin");
        require(feeOrReward > 0 && feeOrReward <= 0.05e18,"max 5%, min>0");
        if (feePerToken[address(underlying)] == 0) {
            allUnderlying.push(underlying);
        }
        feePerToken[address(underlying)] = feeOrReward;
    }


    /**
     * @notice Returns the fee/reward for specified underlying token
     * @dev If fee/reward is zero, then it wasnt updated, and default fee 5%
     */
    function returnFeePerToken(IERC20 underlying) internal view returns(uint) {
        uint fee = feePerToken[address(underlying)];
        require(fee>0,"feePerToken not updated.");
        return fee;
    }

    function returnFeePerTokenExt(IERC20 underlying) external view returns(uint) {
        return returnFeePerToken(underlying);
    }

    // ------------- CALCULATING DEPOSIT/REDEEM FEE OR REWARD ---------------- //


    /**
     * @notice calculates the reward (or fee) when user deposits a token
     * @param _bep20 The underlying asset to be deposited
     * @param _valueIn The value of deposited _bep20 (un-used for now)
     * @param _priorDelta Desired allocations minus actual allocations before _bep20 deposit (positive if desired more asset) 
     * @param _postDelta Desired allocations minus estimated allocations after _bep20 deposit
     */
    function depositRewardOrFee(IERC20 _bep20, uint _valueIn, int _priorDelta, int _postDelta) internal view returns(uint reward, uint fee) {

        _valueIn; // may be used in the future to vary deposit reward (or fee)

        if (_priorDelta >= 0) { // require more of the token (net reward unless far excess) 

            uint priorDelta = uint(_priorDelta);
            reward = returnFeePerToken(_bep20);

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

            fee = returnFeePerToken(_bep20);

        }


    }


    function redeemRewardOrFee(IERC20 _bep20, uint _valueIn, int _priorDelta, int _postDelta) internal view returns(uint reward, uint fee) {

        _valueIn; // may be used in the future to vary deposit reward (or fee)
        
        if (_priorDelta <= 0) { // require less of the token (net reward unless far excess) 

            reward = returnFeePerToken(_bep20);

            if (_postDelta > 0) { // all deposit goes towards desired

                uint priorDelta = uint(-_priorDelta);
                uint excess = uint(_postDelta);

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

            fee = returnFeePerToken(_bep20);

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
             external view returns(int totalFee, uint protocolFeePerc, uint reward, uint fee) {
        price; // may be used in the future
        (reward, fee) = depositRewardOrFee(_depositBEP20,_valueDeposit, priorDelta, postDelta);
        uint feeFactorFromDiscountXTT = uint(1e18).sub(feeDiscount(balanceXTT));
        protocolFeePerc = protocolFeeDeposit.mul(feeFactorFromDiscountXTT).div(1e18);
        totalFee = int(protocolFeePerc).add(int(fee)).sub(int(reward));
        return (totalFee, protocolFeePerc, reward, fee);

    }


    /** 
     * @notice Returns the total Trend Token redeem fee 
     * @dev May be negative if reward exceeds the protocolBaseFee (especially if high XDP discount)
     * @param reward The incentive reward if any
     * @param fee The incentive fee if any
     */
    function totalRedeemFee(IERC20 _redeemBep20, uint _valueRedeem, int priorDelta, int postDelta, uint price, uint balanceXTT) 
             external view returns(int totalFee, uint protocolFeePerc, uint reward, uint fee) {
        price; // may be used in the future
        (reward, fee) = redeemRewardOrFee(_redeemBep20,_valueRedeem, priorDelta, postDelta);
        uint feeFactorFromDiscountXTT = uint(1e18).sub(feeDiscount(balanceXTT));
        protocolFeePerc = protocolFeeRedeem.mul(feeFactorFromDiscountXTT).div(1e18);
        totalFee = int(protocolFeePerc).add(int(fee)).sub(int(reward));
        return (totalFee, protocolFeePerc, reward, fee);

    }

    // ------------- TRADE FUNCTIONS ----------------- // 


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
