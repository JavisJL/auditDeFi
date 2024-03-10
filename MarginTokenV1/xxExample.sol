// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.5.16;




contract Host {

    address[] public colAllo;

    function setAllos(address addr1, address addr2) public {
        colAllo.push(addr1);
        colAllo.push(addr2);
    }
}

contract IHost {

    function colAllo(uint index) public view returns(address);
}



contract Caller {

    //function getValues(address _host) public view returns(address[] memory) {
    //    return IHost(_host).colAllo();
    //}

    function getValuesA(address _host, uint index) public view returns(address) {
        return IHost(_host).colAllo(index);
    }
}