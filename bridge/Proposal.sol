// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.4.22 <0.8.20;
pragma experimental ABIEncoderV2;

library ProposalLib {
    enum ProposalStatus {
        PROPOSING,
        PROPOSED,
        PROPOSE_FAILED,
        COMMITTING,
        COMMITTED,
        CANCELLING,
        CANCELED
    }
    struct ProposalStatusInfo {
        uint256 nonce;
        ProposalStatus localStatus;
        ProposalStatus remoteStatus;
    }

    struct ProposalMap {
        uint256[] taskIDs;
        // taskID => ProposalStatusInfo
        mapping(uint256 => ProposalStatusInfo) proposalStatus;
    }

    function addProposal(
        ProposalMap storage self,
        uint256 taskID,
        ProposalStatusInfo memory status
    ) internal {
        self.taskIDs.push(taskID);
        self.proposalStatus[taskID] = status;
    }

    function setProposalLocalStatus(
        ProposalMap storage self,
        uint256 taskID,
        ProposalStatus status
    ) internal {
        self.proposalStatus[taskID].localStatus = status;
    }

    function setProposalRemoteStatus(
        ProposalMap storage self,
        uint256 taskID,
        ProposalStatus status
    ) internal {
        self.proposalStatus[taskID].remoteStatus = status;
    }

    function setProposalNonce(
        ProposalMap storage self,
        uint256 taskID,
        uint256 nonce
    ) internal {
        self.proposalStatus[taskID].nonce = nonce;
    }

    function removeProposal(
        ProposalMap storage self,
        uint256 taskID
    ) internal returns (bool) {
        uint256[] storage taskIDs = self.taskIDs;
        uint256 length = taskIDs.length;
        for (uint256 i = 0; i < length; i++) {
            if (taskIDs[i] == taskID) {
                if (i != length - 1) {
                    taskIDs[i] = taskIDs[length - 1];
                }
                taskIDs.pop();
                delete self.proposalStatus[taskID];
                return true;
            }
        }
        return false;
    }

    function getProposalStatus(
        ProposalMap storage self,
        uint256 taskID
    ) internal view returns (ProposalStatusInfo memory) {
        return self.proposalStatus[taskID];
    }
}
