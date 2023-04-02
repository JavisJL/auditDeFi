// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.0;

import "./ERC20.sol";
import "./ERC20Detailed.sol";
import "./ITrendTokenTkn.sol";

/**
 * @title SimpleToken
 * @dev Very simple ERC20 Token example, where all tokens are pre-assigned to the creator.
 * Note they can later distribute these tokens as they wish using `transfer` and other
 * `ERC20` functions.
 */
contract TrendTokenTkn is ERC20, ERC20Detailed {
    
    uint8 public constant DECIMALS = 18;
    address public minter;


    constructor (string memory _tokenName, string memory _symbol) public ERC20Detailed(_tokenName, _symbol, DECIMALS) {
        minter = msg.sender;
    }

    modifier requireMinter() {
        require(msg.sender == minter, "!minter");
        _;
    } 

    // ------- remove on mainnet -------- // 
    //function _setMinter(address _minter) public {
     //   minter = _minter;
    //}


    function mint(address _recipient, uint256 _amount) external requireMinter {
        _mint(_recipient, _amount);
    }

    function burn(uint256 _amount) external {
        _burn(msg.sender, _amount);
    }

    function transfersFrom(address sender, address recipient, uint256 amount) external returns(bool) {
        require(allowance(sender, recipient) >= amount, "insufficent Trend Token allowance");
        require(balanceOf(sender) >= amount,"insufficent Trend Token balance");
        return transferFrom(sender, recipient, amount);
    }
}

