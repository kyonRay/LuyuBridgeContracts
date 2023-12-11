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
    uint256 public nativeChainId;
    address private tokenRelayer;
    uint256 private rate = 1;
    uint256 private rateDecimals = 0;

    /**
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address nativeAddress_,
        uint256 nativeChainId_
    ) ERC20(name_, symbol_) {
        nativeAddress = nativeAddress_;
        nativeChainId = nativeChainId_;
    }

    /**
     */
    function mint(address to, uint256 value) external onlyOwner returns (bool) {
        // mint wrapped token = value * rate / 10^rateDecimals
        uint256 amount = (value * rate) / (10 ** rateDecimals);
        _mint(to, amount);
        return true;
    }

    function burn(uint256 amount) external onlyOwner {
        // burn wrapped token = amount / (rate / 10^rateDecimals)
        uint256 value = (amount * (10 ** rateDecimals)) / rate;
        _burn(_msgSender(), value);
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

    function setExchangeRate(
        uint256 _rate,
        uint256 _rateDecimals
    ) external onlyOwner {
        rate = _rate;
        rateDecimals = _rateDecimals;
    }

    function getExchangeRate() external view returns (uint256, uint256) {
        return (rate, rateDecimals);
    }
}
