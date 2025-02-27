// SPDX-License-Identifier: Apache 2
pragma solidity >=0.4.22 <0.8.20;
pragma experimental ABIEncoderV2;

import "./IERC20.sol";
import "./WrappedToken.sol";
import "./SafeERC20.sol";
import "./CrossChainContract.sol";
import "./Ownable.sol";

contract TokenRelayer is CrossChainContract, Ownable {
    struct RelayerPayload {
        uint256 fromChain;
        address sourceTokenAddress;
        address targetTokenAddress;
        uint256 amount;
        address fromAddress;
        address receiveAddress;
    }
    modifier onlyBridge() {
        require(
            _msgSender() == address(getBridge()) || _msgSender() == owner(),
            "only bridge or owner can call this function"
        );
        _;
    }

    // struct TransferBill {
    //     address tokenAddress;
    //     address fromAddress;
    //     uint256 amount;
    // }

    // Mapping of wrapped assets (chainID => nativeAddress => wrappedAddress)
    mapping(uint256 => mapping(address => address)) wrappedAssets;

    // Mapping to safely identify wrapped assets
    mapping(address => bool) isWrappedAsset;

    // Mapping transfer amount
    /// taskID => TransferBill
    // mapping(uint256 => TransferBill) transferLedger;

    mapping(uint256 => string) tasks;
    uint256 chainID;

    event Deposit(uint256, address, address, address, uint256);

    constructor(uint256 chainID_) {
        chainID = chainID_;
    }

    // 1. onPropose example
    function onPropose(
        uint256 taskID,
        string memory params
    ) public override onlyBridge returns (int256) {
        // check avalaible here
        // in ERC20, you can approve money to somewhere in this function
        if (bytes(tasks[taskID]).length != 0) {
            return 1;
        }
        if (bytes(params).length == 0) {
            return 2;
        }
        string memory abiEncoded = string(hexString2Bytes(params));
        RelayerPayload memory payload = abi.decode(
            bytes(abiEncoded),
            (RelayerPayload)
        );
        //跨链发起方
        if (payload.fromChain == chainID) {
            // TransferBill memory transferBill = transferLedger[taskID];
            // if (
            //     transferBill.tokenAddress != payload.sourceTokenAddress ||
            //     transferBill.fromAddress != payload.fromAddress ||
            //     transferBill.amount != payload.amount
            // ) {
            //     return 3;
            // }
            //跨链接收方
        } else {
            if (payload.targetTokenAddress == address(0)) {
                require(
                    wrappedAssets[payload.fromChain][
                        payload.sourceTokenAddress
                    ] != address(0),
                    "can not find wrapped token for this native token"
                );
            }
            if (
                payload.targetTokenAddress != address(0) &&
                IERC20(payload.targetTokenAddress).balanceOf(address(this)) <
                payload.amount
            ) {
                return 4;
            }
        }
        tasks[taskID] = abiEncoded;
        return 0;
    }

    // 2. onCancel example
    function onCancel(uint256 taskID) public override onlyBridge {
        // in ERC20, you can send money back to someone who has approved before.
        if (bytes(tasks[taskID]).length != 0) {
            RelayerPayload memory payload = abi.decode(
                bytes(tasks[taskID]),
                (RelayerPayload)
            );
            if (payload.fromChain == chainID) {
                SafeERC20.safeTransfer(
                    IERC20(payload.sourceTokenAddress),
                    payload.fromAddress,
                    payload.amount
                );
            }
            // delete?
            tasks[taskID] = "";
        }
        return;
    }

    // 3. onCommit example
    function onCommit(uint256 taskID) public override onlyBridge {
        // do the acture operation here
        // in ERC20, you can transfer money to someone that need to transfer before
        // require(bytes(tasks[taskID]).length != 0, "invalid taskId");
        if (bytes(tasks[taskID]).length == 0) {
            return;
        }
        RelayerPayload memory payload = abi.decode(
            bytes(tasks[taskID]),
            (RelayerPayload)
        );
        //跨链发起方
        if (payload.fromChain == chainID) {
            if (isWrappedAsset[payload.sourceTokenAddress]) {
                WrappedToken(payload.sourceTokenAddress).burn(payload.amount);
            }
            //跨链接收方
        } else {
            // TODO: comment it
            if (payload.targetTokenAddress == address(0)) {
                payload.targetTokenAddress = wrappedAssets[payload.fromChain][
                    payload.sourceTokenAddress
                ];
                WrappedToken(payload.targetTokenAddress).mint(
                    payload.receiveAddress,
                    payload.amount
                );
            } else {
                SafeERC20.safeTransfer(
                    IERC20(payload.targetTokenAddress),
                    payload.receiveAddress,
                    payload.amount
                );
            }
        }
        // delete?
        tasks[taskID] = "";
    }

    // set to all chain
    // function deposit(
    //     address tokenAddress,
    //     uint256 amount,
    //     address receiveAddress
    // ) public {
    //     deposit(tokenAddress, msg.sender, amount, receiveAddress);
    // }

    // TODO:this function is for test, remove it after R1
    function deposit(
        address tokenAddress,
        address sender,
        uint256 amount,
        address receiveAddress
    ) public {
        bytes memory data;
        SafeERC20.safeTransferFrom(
            IERC20(tokenAddress),
            sender,
            address(this),
            amount
        );
        if (isWrappedAsset[tokenAddress]) {
            // if is wrappedAssets, then this transaction is wrappedAssets send to nativeAddress
            data = abi.encode(
                chainID, // from chain
                tokenAddress, // source tokenAddress
                WrappedToken(tokenAddress).nativeAddress(), // target token address
                amount,
                sender, // from address
                receiveAddress // receive Address
            );
        } else {
            data = abi.encode(
                chainID, // from chain
                tokenAddress, // source tokenAddress
                address(0), // target token address, if 0, will use wrapped token
                amount, // amount
                sender, // from address
                receiveAddress // receive Address
            );
        }
        // remove to hex
        uint256 taskID = getBridge().propose(bytes2HexString(data));
        // transferLedger[taskID] = TransferBill(tokenAddress, sender, amount);
        emit Deposit(taskID, tokenAddress, sender, receiveAddress, amount);
    }

    event CreateToken(address);

    // should make sure wrapper's owner is this contract
    function setWrappedAsset(
        uint256 tokenChainId,
        address tokenAddress,
        address wrapper
    ) public onlyOwner {
        wrappedAssets[tokenChainId][tokenAddress] = wrapper;
        isWrappedAsset[wrapper] = true;
        emit CreateToken(wrapper);
    }

    // TODO: comment native means
    function createWrapped(
        string memory name_,
        string memory symbol_,
        address nativeAddress_,
        uint256 nativeChainId_
    ) external onlyOwner returns (address) {
        if (wrappedAssets[nativeChainId_][nativeAddress_] != address(0)) {
            return wrappedAssets[nativeChainId_][nativeAddress_];
        }
        WrappedToken newAsset = new WrappedToken(
            name_,
            symbol_,
            nativeAddress_,
            nativeChainId_
        );
        address token = address(newAsset);
        wrappedAssets[nativeChainId_][nativeAddress_] = token;
        isWrappedAsset[token] = true;
        emit CreateToken(token);
        return token;
    }

    // get TransferBill
    // function getTransferBill(
    //     uint256 taskID
    // ) external  view returns (TransferBill memory) {
    //     return transferLedger[taskID];
    // }

    function transferWrappedTokenOwnership(
        address tokenAddress,
        address newOwner
    ) external onlyOwner {
        WrappedToken(tokenAddress).transferOwnership(newOwner);
    }

    function setWrappedAssetExchangeRate(
        address tokenAddress,
        uint256 rate,
        uint32 rateDecimals
    ) external onlyOwner {
        WrappedToken(tokenAddress).setExchangeRate(rate, rateDecimals);
    }

    function bytes2HexString(
        bytes memory buffer
    ) private pure returns (string memory) {
        // Fixed buffer size for hexadecimal convertion
        bytes memory converted = new bytes(buffer.length * 2);

        bytes memory _base = "0123456789abcdef";

        for (uint256 i = 0; i < buffer.length; i++) {
            converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
            converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
        }

        return string(abi.encodePacked(converted));
    }

    // Convert an hexadecimal string to raw bytes
    function hexString2Bytes(
        string memory s
    ) private pure returns (bytes memory) {
        bytes memory ss = bytes(s);
        require(ss.length % 2 == 0); // length must be even
        bytes memory r = new bytes(ss.length / 2);
        for (uint i = 0; i < ss.length / 2; ++i) {
            r[i] = bytes1(
                fromHexChar(uint8(ss[2 * i])) *
                    16 +
                    fromHexChar(uint8(ss[2 * i + 1]))
            );
        }
        return r;
    }

    function fromHexChar(uint8 c) private pure returns (uint8) {
        if (bytes1(c) >= bytes1("0") && bytes1(c) <= bytes1("9")) {
            return c - uint8(bytes1("0"));
        }
        if (bytes1(c) >= bytes1("a") && bytes1(c) <= bytes1("f")) {
            return 10 + c - uint8(bytes1("a"));
        }
        if (bytes1(c) >= bytes1("A") && bytes1(c) <= bytes1("F")) {
            return 10 + c - uint8(bytes1("A"));
        }
        revert("fail");
    }
}
