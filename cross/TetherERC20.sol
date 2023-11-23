// SPDX-License-Identifier: Apache 2
pragma solidity >=0.4.22 <0.8.20;

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

contract TetherERC20 is ERC20("Tether", "USDT"), Ownable {
    address private tokenRelayer;

    function mint(address to, uint256 value) public returns (bool) {
        _mint(to, value);
        return true;
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
                msg.sender,
                amount,
                _msgSender()
            );
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
