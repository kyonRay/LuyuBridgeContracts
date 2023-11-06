/*

  << TestERC20 >>

*/

pragma solidity >=0.4.22 <0.8.20;

import "./ERC20.sol";

contract TestERC20 is ERC20("test", "TST") {
    /**
     */
    constructor() {}

    /**
     */
    function mint(address to, uint256 value) public returns (bool) {
        _mint(to, value);
        return true;
    }
}
