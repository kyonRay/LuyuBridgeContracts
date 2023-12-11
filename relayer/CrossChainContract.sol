// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.4.22 <0.8.20;
pragma experimental ABIEncoderV2;

interface ICrossChainContract {
    // Cross chain events
    function onPropose(
        uint256 taskID,
        string memory params
    ) external returns (int256); // return true if propose check success

    function onCancel(uint256 taskID) external;

    function onCommit(uint256 taskID) external;
}

interface ICrossChainBridge {
    function propose(string memory params) external returns (uint256); // return cross chain taskID

    function cancel(uint256 taskID) external; // trigger cancel

    function commit(uint256 taskID) external; // trigger commit

    // internal functin, no need to implement
    function enable() external;
}

abstract contract CrossChainContract is ICrossChainContract {
    event BridgeEnabled(address bridgeAddress);

    ICrossChainBridge bridgeAddress;
    ICrossChainBridge bridgeCandidate;

    function setBridge(address bridge) public {
        bridgeCandidate = ICrossChainBridge(bridge);
        bridgeCandidate.enable(); // my address is sent by msg.sender() in this function
    }

    function getBridge() public view returns (ICrossChainBridge) {
        require(
            address(bridgeAddress) != address(0),
            "no bridgeAddress, please use setBridge()"
        );
        return bridgeAddress;
    }

    function onBridgeEnable() public {
        require(
            address(bridgeCandidate) == msg.sender,
            "To setBridge, must call setBridge, not this function"
        );
        bridgeAddress = bridgeCandidate;
        emit BridgeEnabled(address(bridgeCandidate));
    }
}

abstract contract CrossChainBridge is ICrossChainBridge {
    CrossChainContract public crossChainContract;

    function enable() public override {
        crossChainContract = CrossChainContract(msg.sender);
        crossChainContract.onBridgeEnable();
    }
}

// only for test
contract NativeBridge is CrossChainBridge {
    NativeBridge public peer;

    // mock bridge impl
    function propose(
        string memory params
    ) public override hasPeerInit hasCrossChainContractInit returns (uint256) {
        uint256 taskID;
        if (comesFromPeer()) {
            taskID = getNonce();
        } else {
            taskID = peer.propose(params);
        }

        if (taskID == 0) {
            // error, do nothing, return 0
            return 0;
        }

        int256 success = crossChainContract.onPropose(taskID, params);
        if (success == 0) {
            // commit(taskID);
            return taskID; // call commit(taskID) if you get taskID
        } else {
            cancel(taskID);
            return 0;
        }
    }

    function cancel(
        uint256 taskID
    ) public override hasPeerInit hasCrossChainContractInit {
        if (taskID == 0) {
            // illegal taskID
            return;
        }

        if (!comesFromPeer()) {
            peer.cancel(taskID);
        }

        crossChainContract.onCancel(taskID);
        return;
    }

    function commit(
        uint256 taskID
    ) public override hasPeerInit hasCrossChainContractInit {
        if (taskID == 0) {
            // illegal taskID
            return;
        }

        if (!comesFromPeer()) {
            peer.commit(taskID);
        }

        crossChainContract.onCommit(taskID);
        return;
    }

    // Internal functions
    function setPeer(address peerAddress) public {
        require(
            address(this) != peerAddress,
            "Must set other bridge, not myself"
        );

        if (msg.sender == address(peer)) {
            return;
        }

        peer = NativeBridge(peerAddress);
        peer.setPeer(address(this));
    }

    modifier hasPeerInit() {
        require(address(peer) != address(0), "Must init peer");
        _;
    }

    modifier hasCrossChainContractInit() {
        require(
            address(crossChainContract) != address(0),
            "Must call enable to set CrossChainContract"
        );
        _;
    }

    function comesFromPeer() private view returns (bool) {
        return msg.sender == address(peer);
    }

    function getSecondTime(uint256 time) private pure returns (uint256) {
        if (time / 10000000000 != 0) {
            return getSecondTime(time / 10);
        } else {
            return time;
        }
    }

    function getNow() private view returns (uint256) {
        // 'now' in ehtereum return in seconds but millisecond in fisco bcos
        // Need to format to seconds
        return getSecondTime(block.timestamp);
    }

    uint256 nonceSeed = 0;

    function getNonce() private returns (uint256) {
        return ((nonceSeed++) % 100000) + getNow() * 100000;
    }
}

contract EvidenceManagerExample is CrossChainContract {
    // must impl this 3 event handler defined in ICrossChainContract
    //      function onPropose(uint256 taskID, string memory params) external returns(bool); // return true if propose check success
    //      function onCancel(uint256 taskID) external;
    //      function onCommit(uint256 taskID) external;

    // 1. onPropose example
    function onPropose(
        uint256 taskID,
        string memory params
    ) public override returns (int256) {
        // check avalaible here
        // in ERC20, you can approve money to somewhere in this function
        if (bytes(tasks[taskID]).length != 0) {
            return -1;
        } else {
            tasks[taskID] = params;
            return 0;
        }
    }

    // 2. onCancel example
    function onCancel(uint256 taskID) public override {
        // in ERC20, you can send money back to someone who has approved before.
        tasks[taskID] = "";
        return;
    }

    // 3. onCommit example
    function onCommit(uint256 taskID) public override {
        // do the acture operation here
        // in ERC20, you can transfer money to someone that need to transfer before
        evidence = tasks[taskID];
        tasks[taskID] = "";
    }

    // Manager example
    string public evidence;
    mapping(uint256 => string) tasks;

    /*
    constructor(address bridge) public {
        setBridge(bridge);
    }
    */

    // set to all chain
    function testSetEvidence(string memory data) public {
        uint256 taskID = getBridge().propose(data);
        if (taskID != 0) {
            getBridge().commit(taskID); // please impl transfer in onCommit()
            emit SetEvidenceTaskID(taskID);
        }
    }

    event SetEvidenceTaskID(uint256);
}
