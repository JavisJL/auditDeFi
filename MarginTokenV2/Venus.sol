// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;

import "./ITrendTokenTkn.sol";
import "./IVBNB.sol";
import "./IVBep20.sol";
import "./ICompVenus.sol";
import "./ICompTT.sol";
import "./IChainlinkOracle.sol";
import "./Lib.sol";


contract VenusIntegration {

    using SafeMath for uint;

    /**
     * @notice The Trend Token comptroller contract that governs all Trend Tokens and some permissions
    */
    ICompTT public compTT;


    /**
     * @notice The wrapped BNB contract address
     * @dev Used as a placeholder to represent BNB
     */
    IERC20 public wbnb;


    /**
     * testnet: 0x8cE9443B7a6BAeD8151Be38D074E2940bFe158Cd
     * mainnet: 0x219928ddfF4A2655f237660A36725A2DFCe2F8a7,0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c
     */
    constructor(address _compTT) public {
        compTT = ICompTT(_compTT);
        wbnb = IERC20(compTT.wbnb()); // IERC20(_wbnb); // 
    }

    // ------------- FOR TESTING PURPOSES ---------------- //

    /**
     * @notice Allows for the deposit of BNB to this contract
     * @dev Required to receive BNB from users or Venus
     */
    function () external payable {
    }



   // ----- CONTRACT ACCOUNT DATA ------ // 

    function ensureNonzeroAddress(address addr) internal pure {
        require(address(addr) != address(0), "!zeroAddr");
    }


    function returnCompVenus() internal view returns(ICompVenus) {
        return ICompVenus(compTT.compVenus()); 
    }


    /**
     * @notice Returns stored balances (vToken, borrow) and stored exchange rates between bep20<-->vToken
     *         vTokenBal: vToken balance, (to get collateral amount, multiply by rate/1e18)
     *         borrowBal: underlying borrow balance
     *         rate: 'collateral = vToken * rate / 1e18' is multiplied by 1e18
     * @param _vTokens The dToken to get screenshot data on
     */
    function screenshot(IVBep20 _vTokens) internal view returns(uint,uint,uint)  {
        (uint error,uint vTokenBal, uint borrowBal, uint rate)  = _vTokens.getAccountSnapshot(address(this));
        require(error == 0, "!screenshot error");
        return (vTokenBal, borrowBal, rate);
    }


    /**
     *  @notice Returns list of dTokens that have been entered in Venus
     */
    function getMarkets() internal view returns(address[] memory) {
        return returnCompVenus().getAssetsIn(address(this));
    }


    /**
     * @notice The exchange rate between underlying and dToken
     * @dev formula 'dTokenAmt = exchangeRate * underlyingAmt'
     * @param _vTokens The underyling token to get exchange rate of
     */
    function exchangeVBEP20(IVBep20 _vTokens) internal view returns(uint) {
        uint rate =  _vTokens.exchangeRateStored();
        return rate;
    }


    // ---------- VENUS MARKETS ---------- // 


    /**
     * @notice Trend Token enables portfolio of underlying assets to Venus
     * @dev Allows Trend Token to borrow assets from Dual Pool
     * @param _vToken Single vToken to be enabled
     */
    function enableSingleCol(address _vToken) internal {
        address[] memory vToken = new address[](1);
        vToken[0] = _vToken;
        returnCompVenus().enterMarkets(vToken);
    }


    /**
     * @notice Trend Token disables token from Dual Pools
     * @dev Removes token from collateral calculations
     * @param _vToken the dToken to disable collateral 
     */
    function disableCol( IVBep20 _vToken) internal { // Allowing collateral and borrow of entered markets
        returnCompVenus().exitMarket(address(_vToken));
    }


    /**
     * @notice Returns true if _dToken entered into market
     * @dev Required to post collateral (loose funds, wont get vTokens) or borrow
     *      Still able to repay borrow and redeem collateral though
     * @param _vToken The dToken to check if this Trend Tokens is entered into
     */ 
    function tokenEntered(IVBep20 _vToken) internal view returns(bool) {
        return returnCompVenus().checkMembership(address(this), address(_vToken));
    }


    /**
     * @notice Supplies collateral to Dual Pools
     * @dev The Underlying token must entered into by this Trend Token
     * @param _bep20 The underlying asset 
     * @param vToken The dToken for underlying to be supplied to
     * @param amountBEP20 The underlying amount to be supplied
     */
    function collateralSupply(IERC20 _bep20, IVBep20 vToken, uint amountBEP20) internal {  //supply BNB as collateral 
        ensureNonzeroAddress(address(vToken));
        if (_bep20 == wbnb) {
            IVBNB(address(vToken)).mint.value(amountBEP20)();
        } else {
            _bep20.approve(address(vToken), amountBEP20); // approve the transfer
            assert(vToken.mint(amountBEP20) == 0);// mint the vTokens and assert there is no error
        }
    }


    /**
     * @notice Redeems collateral from Dual Pools
     * @param amountBEP20 The underlying amount to be redeemed
     */
    function collateralRedeem(IVBep20 _vToken, uint amountBEP20) internal { // withdrawal BNB collateral 
        ensureNonzeroAddress(address(_vToken));
        require(_vToken.redeemUnderlying(amountBEP20) == 0, "Try smaller amount.");
    }



    // ----------- additions for borrowing ------------- //

    /** 
     * @notice Fetches the collateral factor (e.g 70%) for given market
     * @dev markets returns ==> (isListed, collateralFactor, isXVSused)
     */
    function collateralFactor(IVBep20 vToken) internal view returns(uint) {
        (,uint collateralFactorMantissa,) = returnCompVenus().markets(address(vToken));
        return collateralFactorMantissa;
    }

    /**
     * @notice Borrows assets from Venus 
     * @dev Collateral must be supplied and enabled
     */
    function borrowVenus(IVBep20 vToken, uint amountBorrow) internal {
        ensureNonzeroAddress(address(vToken));
        require(vToken.borrow(amountBorrow) == 0, "!executeBorrow.");
    }


    /**
     * @notice Repays loan to venus
     */
    function repayVenus(IERC20 underlying, IVBep20 vToken, uint amountRepay) internal {
        ensureNonzeroAddress(address(vToken));
        if (underlying == wbnb) {
            IVBNB(address(vToken)).repayBorrow.value(amountRepay)();
        } else {
            underlying.approve(address(vToken), amountRepay); 
            IVBep20(vToken).repayBorrow(amountRepay);
        }
    }



}


