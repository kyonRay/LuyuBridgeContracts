// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.4.22 <0.8.20;
pragma experimental ABIEncoderV2;

import "./LuyuSDK.sol";
import "./CrossChainContract.sol";
import "./Proposal.sol";
import "./Ownable.sol";

contract WeCrossBridge is CrossChainBridge, LuyuContract, Ownable {
    string public crossChainUserAddress =
        "0x062201f9aaf520ef5fae98b2c87db66508114c3f"; // L1
    string public peerPath; //= "payment.eth1.WeCrossBridge", "payment.bcos1.WeCrossBridge"

    mapping(uint256 => string) public tasks;
    mapping(uint256 => uint256) nonce2TaskID;

    // taskID => propose status
    ProposalLib.ProposalMap internal proposals;

    event ProposeReceived(uint256 taskID, string params, int256 status);
    event CancelReceived(uint256 taskID);
    event CommitReceived(uint256 taskID);
    event ProposalFinished(uint256 taskID, bool success);

    function setPeer(string memory peer) public onlyOwner {
        peerPath = peer;
    }

    /**
     * @dev This function is used to propose a new task. It generates a unique taskID using the getNonce() function.
     * It then prepares the necessary parameters to call the luyuSendTransaction function which sends a transaction to the blockchain.
     * The transaction details include the path, method, arguments, crossChainUserAddress and a callback method.
     * After the transaction is sent, the function maps the nonce to the taskID and the taskID to the parameters.
     * It then adds a new proposal to the proposals mapping with the taskID and the proposal status.
     * The function finally returns the taskID of the newly proposed task.
     *
     * @param params The parameters for the task to be proposed.
     * @return taskID The unique identifier for the newly proposed task.
     */
    function propose(string memory params) public override returns (uint256) {
        uint256 taskID = getNonce();
        string memory path = peerPath;
        string memory method = "proposeHandler";
        string[] memory args = new string[](2);
        // TODO: luyu use bytes args
        args[0] = toString(taskID);
        args[1] = params;
        string memory callbackMethod = "proposeCallback";
        uint256 nonce = luyuSendTransaction(
            path,
            method,
            args,
            crossChainUserAddress,
            callbackMethod
        );

        nonce2TaskID[nonce] = taskID;
        tasks[taskID] = params;
        ProposalLib.addProposal(
            proposals,
            taskID,
            ProposalLib.ProposalStatusInfo(
                nonce,
                ProposalLib.ProposalStatus.PROPOSED,
                ProposalLib.ProposalStatus.PROPOSING
            )
        );
        return taskID;
    }

    /**
     * @dev This function is used to handle a proposed task. It first assigns the task parameters to the taskID in the tasks mapping.
     * It then calls the onPropose function of the crossChainContract with the taskID and parameters.
     * If the onPropose function returns true, it emits a ProposeReceived event with the taskID, parameters, and the return value.
     * If the onPropose function returns false, it reverts the transaction with an error message.
     *
     * @param taskID The unique identifier for the task to be handled.
     * @param params The parameters for the task to be handled.
     */
    // FIXME: should onlyOwner(), but account manager signature recover wrong address
    function proposeHandler(uint256 taskID, string memory params) public {
        if (bytes(tasks[taskID]).length != 0) {
            return;
        }
        tasks[taskID] = params;
        int256 ret = crossChainContract.onPropose(taskID, params);
        emit ProposeReceived(taskID, params, ret);
        require(ret == 0, "onPropose failed");
    }

    // FIXME: should onlyOwner(), but account manager signature recover wrong address
    function proposeCallback(uint256 nonce, int16 status) public {
        uint256 taskID = nonce2TaskID[nonce];
        if (
            proposals.proposalStatus[taskID].localStatus !=
            ProposalLib.ProposalStatus.PROPOSED ||
            proposals.proposalStatus[taskID].remoteStatus !=
            ProposalLib.ProposalStatus.PROPOSING
        ) {
            return;
        }

        require(taskID != 0, "taskID not found");
        int256 ret = crossChainContract.onPropose(taskID, tasks[taskID]);
        if (status == 0 && ret == 0) {
            ProposalLib.setProposalRemoteStatus(
                proposals,
                taskID,
                ProposalLib.ProposalStatus.PROPOSED
            );
            commit(taskID);
        } else {
            ProposalLib.setProposalRemoteStatus(
                proposals,
                taskID,
                ProposalLib.ProposalStatus.PROPOSE_FAILED
            );
            cancel(taskID);
        }
        delete nonce2TaskID[nonce];
    }

    // internal?
    function cancel(uint256 taskID) public override {
        if (
            proposals.proposalStatus[taskID].localStatus !=
            ProposalLib.ProposalStatus.PROPOSED ||
            proposals.proposalStatus[taskID].remoteStatus !=
            ProposalLib.ProposalStatus.PROPOSE_FAILED
        ) {
            return;
        }
        string memory path = peerPath;
        string memory method = "cancelHandler";
        string[] memory args = new string[](1);
        args[0] = toString(taskID);
        string memory callbackMethod = "cancelCallback";
        uint256 nonce = luyuSendTransaction(
            path,
            method,
            args,
            crossChainUserAddress,
            callbackMethod
        );

        ProposalLib.setProposalLocalStatus(
            proposals,
            taskID,
            ProposalLib.ProposalStatus.CANCELED
        );
        ProposalLib.setProposalRemoteStatus(
            proposals,
            taskID,
            ProposalLib.ProposalStatus.CANCELLING
        );
        ProposalLib.setProposalNonce(proposals, taskID, nonce);
        nonce2TaskID[nonce] = taskID;
    }

    function cancelHandler(uint256 taskID) public {
        emit CancelReceived(taskID);
        crossChainContract.onCancel(taskID);
    }

    // FIXME: should onlyOwner(), but account manager signature recover wrong address
    function cancelCallback(uint256 nonce) public {
        uint256 taskID = nonce2TaskID[nonce];
        if (
            proposals.proposalStatus[taskID].localStatus !=
            ProposalLib.ProposalStatus.CANCELED ||
            proposals.proposalStatus[taskID].remoteStatus !=
            ProposalLib.ProposalStatus.CANCELLING
        ) {
            return;
        }
        require(taskID != 0, "taskID not found");
        ProposalLib.setProposalRemoteStatus(
            proposals,
            taskID,
            ProposalLib.ProposalStatus.CANCELED
        );
        crossChainContract.onCancel(taskID);
        ProposalLib.removeProposal(proposals, taskID);
        tasks[taskID] = "";
        delete nonce2TaskID[nonce];
        emit ProposalFinished(taskID, false);
    }

    // internal?
    function commit(uint256 taskID) public override {
        if (
            proposals.proposalStatus[taskID].localStatus !=
            ProposalLib.ProposalStatus.PROPOSED ||
            proposals.proposalStatus[taskID].remoteStatus !=
            ProposalLib.ProposalStatus.PROPOSED
        ) {
            return;
        }
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
        ProposalLib.setProposalLocalStatus(
            proposals,
            taskID,
            ProposalLib.ProposalStatus.COMMITTED
        );
        ProposalLib.setProposalRemoteStatus(
            proposals,
            taskID,
            ProposalLib.ProposalStatus.COMMITTING
        );
        ProposalLib.setProposalNonce(proposals, taskID, nonce);
        nonce2TaskID[nonce] = taskID;
    }

    function commitHandler(uint256 taskID) public {
        emit CommitReceived(taskID);
        crossChainContract.onCommit(taskID);
    }

    // FIXME: should onlyOwner(), but account manager signature recover wrong address
    function commitCallback(uint256 nonce) public {
        uint256 taskID = nonce2TaskID[nonce];
        if (
            proposals.proposalStatus[taskID].localStatus !=
            ProposalLib.ProposalStatus.COMMITTED ||
            proposals.proposalStatus[taskID].remoteStatus !=
            ProposalLib.ProposalStatus.COMMITTING
        ) {
            return;
        }
        require(taskID != 0, "taskID not found");
        ProposalLib.setProposalRemoteStatus(
            proposals,
            taskID,
            ProposalLib.ProposalStatus.COMMITTED
        );
        crossChainContract.onCommit(taskID);
        ProposalLib.removeProposal(proposals, taskID);
        tasks[taskID] = "";
        delete nonce2TaskID[nonce];
        emit ProposalFinished(taskID, true);
    }

    function getUnfinishedTaskIDs() public view returns (uint256[] memory) {
        return proposals.taskIDs;
    }

    function getProposalInfo(
        uint256 taskID
    ) public view returns (ProposalLib.ProposalStatusInfo memory) {
        return proposals.proposalStatus[taskID];
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
}
