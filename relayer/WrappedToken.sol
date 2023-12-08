// SPDX-License-Identifier: Apache 2
pragma solidity >=0.4.22 <0.8.20;
pragma experimental ABIEncoderV2;

import "./ERC20.sol";
import "./Ownable.sol";

interface ITokenRelayer {
    function deposit(
        address tokenAddress,
        address sender,
        uint256 amount,
        address receiveAddress
    ) external;
}

contract WrappedToken is ERC20, Ownable {
    address public nativeAddress;
    uint16 public nativeChainId;
    address private tokenRelayer;

    /**
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address nativeAddress_,
        uint16 nativeChainId_
    ) ERC20(name_, symbol_) {
        nativeAddress = nativeAddress_;
        nativeChainId = nativeChainId_;
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

    function transfer(
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        address owner = owner();
        if (recipient == owner) {
            bool ret = approve(owner, amount);
            require(ret, "Cannot approve to tokenRelayer.");
            ITokenRelayer(owner).deposit(
                address(this),
                _msgSender(),
                amount,
                _msgSender()
            );
            return true;
        } else {
            _transfer(_msgSender(), recipient, amount);
        }
        return true;
    }
}
