// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.4.22 <0.8.20;
pragma experimental ABIEncoderV2;

import "./LuyuSDK.sol";
import "./CrossChainContract.sol";

contract WeCrossBridge is CrossChainBridge, LuyuContract {
    string public crossChainUserAddress =
        "0x062201f9aaf520ef5fae98b2c87db66508114c3f"; // L1
    string public peerPath; //= "payment.eth1.WeCrossBridge", "payment.bcos1.WeCrossBridge"

    mapping(uint256 => string) public tasks;
    mapping(uint256 => uint256) nonce2TaskID;

    function setPeer(string memory peer) public {
        peerPath = peer;
    }

    function propose(string memory params) public override returns (uint256) {
        uint256 taskID = getNonce();
        string memory message = messageEncode(params);
        string memory path = peerPath;
        string memory method = "proposeHandler";
        string[] memory args = new string[](2);
        args[0] = uintToString(taskID);
        args[1] = message;
        string memory luyuIdentity = crossChainUserAddress;
        string memory callbackMethod = "proposeCallback";
        uint256 nonce = luyuSendTransaction(
            path,
            method,
            args,
            luyuIdentity,
            callbackMethod
        );

        nonce2TaskID[nonce] = taskID;
        tasks[taskID] = message;
        return taskID;
    }

    function proposeHandler(uint256 taskID, string memory params) public {
        tasks[taskID] = params;
        crossChainContract.onPropose(taskID, messageDecode(params));
    }

    function callOnPropose(uint256 taskID) public {
        crossChainContract.onPropose(taskID, messageDecode(tasks[taskID]));
    }

    function proposeCallback(uint256 nonce) public {
        uint256 taskID = nonce2TaskID[nonce];

        crossChainContract.onPropose(taskID, messageDecode(tasks[taskID]));

        // trigger commit
        commit(taskID);
    }

    function cancel(uint256 taskID) public override {
        string memory path = peerPath;
        string memory method = "cancelHandler";
        string[] memory args = new string[](1);
        args[0] = uintToString(taskID);
        string memory luyuIdentity = crossChainUserAddress;
        string memory callbackMethod = "cancelCallback";
        uint256 nonce = luyuSendTransaction(
            path,
            method,
            args,
            luyuIdentity,
            callbackMethod
        );

        nonce2TaskID[nonce] = taskID;
    }

    function cancelHandler(uint256 taskID) public {
        crossChainContract.onCancel(taskID);
    }

    function cancelCallback(uint256 nonce) public {
        uint256 taskID = nonce2TaskID[nonce];
        crossChainContract.onCancel(taskID);
    }

    function commit(uint256 taskID) public override {
        string memory path = peerPath;
        string memory method = "commitHandler";
        string[] memory args = new string[](1);
        args[0] = uintToString(taskID);
        string memory luyuIdentity = crossChainUserAddress;
        string memory callbackMethod = "commitCallback";
        uint256 nonce = luyuSendTransaction(
            path,
            method,
            args,
            luyuIdentity,
            callbackMethod
        );

        nonce2TaskID[nonce] = taskID;
    }

    function commitHandler(uint256 taskID) public {
        crossChainContract.onCommit(taskID);
    }

    function commitCallback(uint256 nonce) public {
        uint256 taskID = nonce2TaskID[nonce];
        crossChainContract.onCommit(taskID);
    }

    function uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        uint256 index = digits - 1;
        temp = value;
        while (temp != 0) {
            buffer[index--] = bytes1(uint8(48 + (temp % 10)));
            temp /= 10;
        }
        return string(buffer);
    }

    function messageEncode(
        string memory message
    ) private pure returns (string memory) {
        return bytes2HexString(bytes(message));
    }

    function messageDecode(
        string memory encodedMessage
    ) private pure returns (string memory) {
        return string(hexString2Bytes(encodedMessage));
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
}
