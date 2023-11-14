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
        args[0] = toString(taskID);
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
        bool ret = crossChainContract.onPropose(taskID, messageDecode(params));
        require(ret, "proposeHandler: onPropose failed");
    }

    function callOnPropose(uint256 taskID) public {
        crossChainContract.onPropose(taskID, messageDecode(tasks[taskID]));
    }

    function proposeCallback(uint256 nonce) public {
        uint256 taskID = nonce2TaskID[nonce];

        bool ret = crossChainContract.onPropose(
            taskID,
            messageDecode(tasks[taskID])
        );
        require(ret, "proposeCallback: onPropose failed");
        // trigger commit
        commit(taskID);
    }

    function cancel(uint256 taskID) public override {
        string memory path = peerPath;
        string memory method = "cancelHandler";
        string[] memory args = new string[](1);
        args[0] = toString(taskID);
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
        args[0] = toString(taskID);
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

    /**
     * @dev Return the log in base 10 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     */
    function log10(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >= 10 ** 64) {
                value /= 10 ** 64;
                result += 64;
            }
            if (value >= 10 ** 32) {
                value /= 10 ** 32;
                result += 32;
            }
            if (value >= 10 ** 16) {
                value /= 10 ** 16;
                result += 16;
            }
            if (value >= 10 ** 8) {
                value /= 10 ** 8;
                result += 8;
            }
            if (value >= 10 ** 4) {
                value /= 10 ** 4;
                result += 4;
            }
            if (value >= 10 ** 2) {
                value /= 10 ** 2;
                result += 2;
            }
            if (value >= 10 ** 1) {
                result += 1;
            }
        }
        return result;
    }

    function toString(uint256 value) internal pure returns (string memory) {
        bytes16 HEX_DIGITS = "0123456789abcdef";
        unchecked {
            uint256 length = log10(value) + 1;
            string memory buffer = new string(length);
            uint256 ptr;
            /// @solidity memory-safe-assembly
            assembly {
                ptr := add(buffer, add(32, length))
            }
            while (true) {
                ptr--;
                /// @solidity memory-safe-assembly
                assembly {
                    mstore8(ptr, byte(mod(value, 10), HEX_DIGITS))
                }
                value /= 10;
                if (value == 0) break;
            }
            return buffer;
        }
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
