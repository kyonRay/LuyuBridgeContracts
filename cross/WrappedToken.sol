// SPDX-License-Identifier: Apache 2
pragma solidity >=0.4.22 <0.8.20;
pragma experimental ABIEncoderV2;

import "./ERC20.sol";

contract WrappedToken is ERC20 {
    address public nativeAddress;
    uint16 public nativeChainId;
    address owner;

    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    /**
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address nativeAddress_,
        uint16 nativeChainId_
    ) ERC20(strConcat("F", name_), strConcat("F", symbol_)) {
        nativeAddress = nativeAddress_;
        nativeChainId = nativeChainId_;
        owner = msg.sender;
        //super._setupDecimals();
    }

    /**
     */
    function mint(address to, uint256 value) public onlyOwner returns (bool) {
        _mint(to, value);
        return true;
    }

    function burn(uint256 amount) public onlyOwner {
        _burn(_msgSender(), amount);
    }

    function strConcat(
        string memory _a,
        string memory _b
    ) internal pure returns (string memory) {
        bytes memory _ba = bytes(_a);
        bytes memory _bb = bytes(_b);
        string memory ret = new string(_ba.length + _bb.length);
        bytes memory bret = bytes(ret);
        uint k = 0;
        for (uint i = 0; i < _ba.length; i++) bret[k++] = _ba[i];
        for (uint j = 0; j < _bb.length; j++) bret[k++] = _bb[j];
        return string(ret);
    }
}
