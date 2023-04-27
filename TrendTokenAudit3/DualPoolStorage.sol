// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;

import "./ITrendTokenTkn.sol";
import "./IVBep20.sol";
import "./ICompTT.sol";
import "./ICompDP.sol";


contract DualPoolStorage {


    /**
     * @notice The Dual Pool comptroller contract that governs all Trend Tokens and some permissions
    */
    ICompDP public compDP;


    /**
     * @notice The Trend Token comptroller contract that governs all Trend Tokens and some permissions
    */
    ICompTT public compTT;


    /**
     * @notice The dToken for BNB
    */
    IVBep20 public dBNB;

    /**
     * @notice The wrapped BNB contract address
     * @dev Used as a placeholder to represent BNB
     */
    IERC20 public wbnb;


    /**
     * @notice The Price Oracle for Dual Pool pricing
    */
    IOracle public priceOracle;


}
