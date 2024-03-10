// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.5.16;

import "./SafeMath.sol";
import "./IXTT.sol";




contract VoteXTT {

    using SafeMath for uint;

    // address of admin who can change limited variables
    address public admin;

    // the minimum XTT to count for vote
    uint public minVote;

    // XTT count that voted for yes
    uint public votesYes;

    // XTT count that voted for no
    uint public votesNo;

    // Address of XTT to count towards votes
    IERC20 public xtt;

    // a list of addresses that voted
    address[] public voters;

    // stores the votes of users
    // 0 = no vote, <0 notes no, >0 votes yes
    mapping(address => int) public userVotes;


    // testnet: 0xDEaB642CfE0fa70BF5E9fda6b6485fA0a23F040f
    constructor(address _xtt) public {
        admin = msg.sender;
        xtt = IERC20(_xtt);
        minVote = 100e18;
    }


    /**
     * @notice Allows admin to change minimu XTT holders for user to vote
     */
    function minimumVote(uint _min) external {
        require(msg.sender == admin, "must be admin");
        minVote = _min;
    }


    /**
     * @notice Checks 
     * @dev Used by frontend libraries
     * @return 'yes' if voted yes, 'no' if voted no, 'none' if no vote
     */
    function userVotedYes(address user) external view returns(string memory) {
        int voteWeight = userVotes[user];
        if (voteWeight > 0) {
            return "yes";
        } else if (voteWeight < 0) {
            return "no";
        } else {
            return "none";
        }

    }


    /**
     * @notice Checks if voter has already voted
     * @return True if voter has not voted yet
     */
    function uniqueVoter(address voter) public view returns(bool) {

        for(uint i=0; i<voters.length ;i++) {
            if (voter == voters[i]) {
                return false;
            }
        }

        // voter is not in list of voters
        return true; 

    }


    /**
     * @notice Allows msg.sender to cast a vote
     * @dev must be unique voter and above min limit
     */
    function vote(bool _yes, bool _no) public {

        require(_yes != _no, "cannot be true or false for both yes and no.");
        require(uniqueVoter(msg.sender),"voter already voted.");
        uint balanceXTT = xtt.balanceOf(msg.sender);
        require(balanceXTT >= minVote, "voter does not have enough XTT to vote. ");

        if (_yes) {
            votesYes += balanceXTT;
            userVotes[msg.sender] = int(balanceXTT);
        } else {
            votesNo += balanceXTT;
            userVotes[msg.sender] = -int(balanceXTT);
        }

        voters.push(msg.sender);

    }



}