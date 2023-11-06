// SPDX-License-Identifier: Apache 2
pragma solidity >=0.4.22 <0.8.20;
pragma experimental ABIEncoderV2;

import "./IERC20.sol";
import "./WrappedToken.sol";
import "./SafeERC20.sol";
import "./CrossChainContract.sol";

contract TokenRelayer is CrossChainContract {
    // must impl this 3 event handler defined in ICrossChainContract
    //      function onPropose(uint256 taskID, string memory params) external returns(bool); // return true if propose check success
    //      function onCancel(uint256 taskID) external;
    //      function onCommit(uint256 taskID) external;

    struct RelayerPayload {
        uint16 fromChain;
        address sourceTokenAddress;
        address targetTokenAddress;
        uint256 amount;
        address fromAddress;
        address receiveAddress;
    }

    // Mapping of wrapped assets (chainID => nativeAddress => wrappedAddress)
    mapping(uint16 => mapping(address => address)) wrappedAssets;

    // Mapping to safely identify wrapped assets
    mapping(address => bool) isWrappedAsset;

    uint16 chainID;

    constructor(uint16 chainID_) {
        chainID = chainID_;
    }

    // 1. onPropose example
    function onPropose(
        uint256 taskID,
        string memory params
    ) public override returns (bool) {
        // check avalaible here
        // in ERC20, you can approve money to somewhere in this function
        if (bytes(tasks[taskID]).length != 0) {
            return false;
        }
        RelayerPayload memory payload = abi.decode(
            bytes(params),
            (RelayerPayload)
        );
        //跨链发起方
        if (payload.fromChain == chainID) {
            if (
                IERC20(payload.sourceTokenAddress).balanceOf(
                    payload.fromAddress
                ) <
                payload.amount ||
                IERC20(payload.sourceTokenAddress).allowance(
                    payload.fromAddress,
                    address(this)
                ) <
                payload.amount
            ) {
                return false;
            }
            //这里先不考虑部分erc20 Token的transferFrom方法收取手续费
            SafeERC20.safeTransferFrom(
                IERC20(payload.sourceTokenAddress),
                payload.fromAddress,
                address(this),
                payload.amount
            );
            if (isWrappedAsset[payload.sourceTokenAddress]) {
                WrappedToken(payload.sourceTokenAddress).burn(payload.amount);
            }
            //跨链接收方
        } else {
            if (
                payload.targetTokenAddress != address(0) &&
                IERC20(payload.targetTokenAddress).balanceOf(address(this)) <
                payload.amount
            ) {
                return false;
            }
        }
        tasks[taskID] = params;
        return true;
    }

    // 2. onCancel example
    function onCancel(uint256 taskID) public override {
        // in ERC20, you can send money back to someone who has approved before.
        if (bytes(tasks[taskID]).length != 0) {
            RelayerPayload memory payload = abi.decode(
                bytes(tasks[taskID]),
                (RelayerPayload)
            );
            if (isWrappedAsset[payload.sourceTokenAddress]) {
                WrappedToken(payload.sourceTokenAddress).mint(
                    payload.fromAddress,
                    payload.amount
                );
            } else {
                SafeERC20.safeTransfer(
                    IERC20(payload.sourceTokenAddress),
                    payload.fromAddress,
                    payload.amount
                );
            }
        }
        tasks[taskID] = "";
        return;
    }

    // 3. onCommit example
    function onCommit(uint256 taskID) public override {
        // do the acture operation here
        // in ERC20, you can transfer money to someone that need to transfer before
        require(bytes(tasks[taskID]).length != 0, "invalid taskId");
        RelayerPayload memory payload = abi.decode(
            bytes(tasks[taskID]),
            (RelayerPayload)
        );
        //跨链发起方
        if (payload.fromChain == chainID) {
            //do nothing
            //跨链接收方
        } else {
            if (payload.targetTokenAddress == address(0)) {
                require(
                    wrappedAssets[payload.fromChain][
                        payload.sourceTokenAddress
                    ] != address(0),
                    "can not find wrapped token for this native token"
                );
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
        tasks[taskID] = "";
    }

    // Manager example
    mapping(uint256 => string) tasks;

    /*
    constructor(address bridge) public {
        setBridge(bridge);
    }
    */

    // set to all chain
    function deposit(
        address tokenAddress,
        uint256 amount,
        address receiveAddress
    ) public {
        bytes memory data;
        if (isWrappedAsset[tokenAddress]) {
            data = abi.encode(
                chainID,
                tokenAddress,
                WrappedToken(tokenAddress).nativeAddress(),
                amount,
                msg.sender,
                receiveAddress
            );
        } else {
            data = abi.encode(
                chainID,
                tokenAddress,
                address(0),
                amount,
                msg.sender,
                receiveAddress
            );
        }
        uint256 taskID = getBridge().propose(string(data));
        if (taskID != 0) {
            //onPropose(taskID, string(data));
            getBridge().commit(taskID); // please impl transfer in onCommit()
        }
    }

    function setWrappedAsset(
        uint16 tokenChainId,
        address tokenAddress,
        address wrapper
    ) internal {
        wrappedAssets[tokenChainId][tokenAddress] = wrapper;
        isWrappedAsset[wrapper] = true;
    }

    function createWrapped(
        string memory name_,
        string memory symbol_,
        address nativeAddress_,
        uint16 nativeChainId_
    ) external returns (address token) {
        require(
            wrappedAssets[nativeChainId_][nativeAddress_] == address(0),
            "wrapped asset already exists"
        );
        WrappedToken newAsset = new WrappedToken(
            name_,
            symbol_,
            nativeAddress_,
            nativeChainId_
        );
        token = address(newAsset);
        setWrappedAsset(nativeChainId_, nativeAddress_, token);
    }
}
