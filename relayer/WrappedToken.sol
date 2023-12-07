// SPDX-License-Identifier: Apache 2
pragma solidity >=0.4.22 <0.8.20;
pragma experimental ABIEncoderV2;

import "./ERC20.sol";

interface ITokenRelayer {
    function deposit(
        address tokenAddress,
        address sender,
        uint256 amount,
        address receiveAddress
    ) external;
}

contract WrappedToken is ERC20 {
    address public nativeAddress;
    uint16 public nativeChainId;
    address private tokenRelayer;
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
    ) ERC20(name_, symbol_) {
        nativeAddress = nativeAddress_;
        nativeChainId = nativeChainId_;
        owner = msg.sender;
        tokenRelayer = msg.sender;
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
        if (recipient == tokenRelayer) {
            bool ret = approve(tokenRelayer, amount);
            require(ret, "Cannot approve to tokenRelayer.");
            ITokenRelayer(tokenRelayer).deposit(
                address(this),
                _msgSender(),
                amount,
                _msgSender()
            );
            emit Transfer(_msgSender(), recipient, amount);
            return true;
        } else {
            _transfer(_msgSender(), recipient, amount);
        }
        return true;
    }

    function setTokenRelayer(address tokenRelayer_) public onlyOwner {
        tokenRelayer = tokenRelayer_;
    }
}
