// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "./ERC20.sol";
import "./ITrendTokenTkn.sol";


contract TrendTokenTkn is ERC20 {

    // @notice Allows for minting of new tokens
    address public minter;
    

    constructor (string memory _tokenName, string memory _tokenSymbol) ERC20(_tokenName, _tokenSymbol)  {
        minter = msg.sender;
    }

    // ------- Mint and Burn Functionality ----------- // 


    modifier requireMinter() {
        require(msg.sender == minter, "!minter");
        _;
    } 

    /**
     * @notice Allows minter to mint new tokens
     * @dev The minter will be the Trend Token that deploys this contract
     */
    function mint(address _recipient, uint256 _amount) external requireMinter {
        _mint(_recipient, _amount);
    }

    /**
     * @notice Allows any wallet to burn new tokens
     */
    function burn(uint256 _amount) external {
        _burn(msg.sender, _amount);
    }


}

