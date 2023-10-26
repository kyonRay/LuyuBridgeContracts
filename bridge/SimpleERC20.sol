// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.4.22 <0.8.20;

contract SimpleERC20 {
    mapping(address => int256) public balanceOf;

    function transfer(address to, int256 value) public returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;

        return true;
    }

    function set(address to, int256 value) public returns (bool) {
        balanceOf[to] = value;

        return true;
    }
}
