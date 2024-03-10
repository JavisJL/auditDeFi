// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.16;



contract EscrowLayer {
    /**
     * @notice Simple layer between DeFi protocol and user to help prevent exploits 
     * @dev Some consideration for user by other DeFi protocols
     * @dev User can still use funds to interact with DeFi protocol (e.g sell for another token)
     */



    // ----------------- LOCKS AND UPDATES -------------------- // 


    /**
     * @notice Amount of time before funds are automatically released
     * @dev Vote can freeze timeLock indefinitely or until voted otherwise
     */
    uint public timeLock;


    /**
     * @notice Updates users account (ex, locked --> unlocked) for token 
     */
    function updateAccount(address userAccount, IERC20 token) public {
        // checks if lock has expired and adjusts balances 
    }

    /**
     * @notice 
     */
    function updateAccount(address userAccount) external {
        // calls pdateAccount(address userAccount, IERC20 token) for all tokens 
    }

    /**
     * @notice Freezes user account by vote
     * @dev Voter must stake XTT
     */
    function freeze(address userAccount) external {

    }


    /**
     * @notice Unfreezes user account by vote
     * @dev Voter must stake XTT 
     */
    function unfreeze(address userAccount) external {

    }


    // ----------------- DEPOSITS AND REDEEMS  -------------------- //


    /**
     * @notice 'token' of 'amount' is sent to this contract by DeFi protocol and credited to 'userAccount'
     * @dev DeFi smart contract must call this function to deposit funds in users name
     */
    function depositToAccount(address userAccount, IERC20 token, uint amount) external {
        // credits 'token' of 'amount' to 'userAccount'
    }


    /**
     * @notice Releases first in first out (FIFO)
     */
    function releaseFromAccount(address userAccount, IERC20 token, uint amount) external {
        // sends 'amount' of 'token' to 'userAccount' if unlocked or timeLock has expired for locked tokens 
    }


    // ----------------- EXECUTES LOCKED ASSET TRADES  -------------------- //


    /**
     * @notice Allows user to buy Trend Tokens with locked assets 
     */
    function internalDeposit() external {

    }

    /**
     * @notice Allows user to sell Trend Tokens with locked Trend Tokens 
     */
    function internalRedeem() external {

    }


    /**
     * @notice allows user to swap token for token with locked assets 
     */
    function internalSwap() external {

    }







}