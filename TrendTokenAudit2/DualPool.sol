// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;

import "./ITrendTokenTkn.sol";
import "./IVBNB.sol";
import "./IVBep20.sol";
import "./ICompDP.sol";
import "./ICompTT.sol";
import "./IChainlinkOracle.sol";
import "./DualPoolStorage.sol";
import "./Lib.sol";

// Mar 19: 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd,0x20e0827B4249588236E31ECE4Fe99A29a0Ec40bA,0x022d21035c00594bdFBdAf77bEF76BBCe597d876


contract DualPoolIntegration is DualPoolStorage {//is DualPoolTokens { // 6,800 bytes --> 5500 --> 4100

    using SafeMath for uint;


    // CONSTRUCTOR
    constructor(address _wbnb, address _compTT, address _compDP) public {
        compTT = ICompTT(_compTT);
        compDP = ICompDP(_compDP); 
        wbnb = IERC20(_wbnb);
        dBNB = IVBep20(compTT.returnDToken(_wbnb));
        priceOracle = IOracle(address(ICompTT(_compTT).oracle()));
        require(address(dBNB) != address(0), "dBNB cannot be zero address.");
    }

    // ------------- FOR TESTING PURPOSES ---------------- //


    /**
     * @notice Allows for the deposit of BNB to this contract
     */
    function () external payable {
    }


   // ----- CONTRACT ACCOUNT DATA ------ // 


    /**
     * @notice Returns stored balances (vToken, borrow) and stored exchange rates between bep20<-->vToken
     *         vTokenBal: vToken balance, (to get collateral amount, multiply by rate/1e18)
     *         borrowBal: underlying borrow balance
     *         rate: 'collateral = vToken * rate / 1e18' is multiplied by 1e18
     * @param _dToken The dToken to get screenshot data on
     */
    function screenshot(IVBep20 _dToken) internal view returns(uint,uint,uint)  {
        (uint error,uint vTokenBal, uint borrowBal, uint rate)  = _dToken.getAccountSnapshot(address(this));
        require(error == 0, "!screenshot error");
        return (vTokenBal, borrowBal, rate);
    }


    /**
     *  @notice Returns list of dTokens that have been entered in Dual Pools
     */
    function getMarkets() internal view returns(address[] memory) {
        return compDP.getAssetsIn(address(this));
    }


    /**
     * @notice Fetch prices of tokens from Chainlink price oracle
     * @param _dToken The underlying assets dToken to get price of
     */
    function priceBEP20(IVBep20 _dToken) internal view returns(uint256) { //have it exact BUSD
        uint price = priceOracle.getUnderlyingPrice(address(_dToken));
        require(price != 0, "price cannot be 0");
        return price;
    }


    /**
     * @notice The exchange rate between underlying and dToken
     * @dev formula 'dTokenAmt = exchangeRate * underlyingAmt'
     * @param _dToken The underyling token to get exchange rate of
     */
    function exchangeVBEP20(IVBep20 _dToken) internal view returns(uint) {
        uint rate =  _dToken.exchangeRateStored();
        return rate;
    }


    // ---------- VENUS MARKETS ---------- // 

    /**
     * @notice Trend Token enables portfolio of underlying assets to Dual Pools
     * @dev Allows Trend Token to borrow assets from Dual Pool
     * @param _dTokens List of bep20 tokens to be enabled
     */
    function enableCol(address[] memory _dTokens) internal {
        compDP.enterMarkets(_dTokens);
    }


    /**
     * @notice Trend Token disables token from Dual Pools
     * @dev Removes token from collateral calculations
     * @param _dToken the dToken to disable collateral 
     */
    function disableCol(IVBep20 _dToken) internal { // Allowing collateral and borrow of entered markets
        compDP.exitMarket(address(_dToken));
    }


    /**
     * @notice Returns true if _dToken entered into market
     * @dev Required to post collateral (loose funds, wont get vTokens) or borrow
     *      Still able to repay borrow and redeem collateral though
     * @param _dToken The dToken to check if this Trend Tokens is entered into
     */ 
    function tokenEntered(IVBep20 _dToken) internal view returns(bool) {
        return compDP.checkMembership(address(this), address(_dToken));
    }


    /**
     * @notice Supplies collateral to Dual Pools
     * @dev The Underlying token must entered into by this Trend Token
     * @param _bep20 The underlying asset 
     * @param _dToken The dToken for underlying to be supplied to
     * @param amountBEP20 The underlying amount to be supplied
     */
    function collateralSupply(IERC20 _bep20, IVBep20 _dToken, uint amountBEP20) internal {  //supply BNB as collateral 
        if (_dToken == dBNB) {
            IVBNB vbnb = IVBNB(address(dBNB));
            vbnb.mint.value(amountBEP20)();
        } else {
            _bep20.approve(address(_dToken), amountBEP20); // approve the transfer
            assert(_dToken.mint(amountBEP20) == 0);// mint the vTokens and assert there is no error
        }
    }


    /**
     * @notice Redeems collateral from Dual Pools
     * @param _bep20 The underlying asset to be redeemed
     * @param amountBEP20 The underlying amount to be redeemed
     */
    function collateralRedeem(IERC20 _bep20, IVBep20 _dToken, uint amountBEP20) internal returns(uint redeemedAmount) { // withdrawal BNB collateral 
        uint balanceBeforeRedeem = _bep20.balanceOf(address(this)); 
        require(_dToken.redeemUnderlying(amountBEP20) == 0, "Try smaller amount.");
        uint balanceAfterRedeem = _bep20.balanceOf(address(this)); 
        redeemedAmount = balanceAfterRedeem.sub(balanceBeforeRedeem);
    }



}


