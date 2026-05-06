// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAccessControl} from "../interfaces/IAccessControl.sol";
import {Roles} from "../libraries/Roles.sol";
import {MultiSigAdminErrors} from "../libraries/MultiSigAdminErrors.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// multisig that holds DEFAULT_ADMIN_ROLE on the platform.

contract MultiSigAdmin is ReentrancyGuard {
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address indexed target,
        bytes data,
        uint256 expiresAt,
        uint256 timelockUntil
    );
    event ProposalSigned(uint256 indexed proposalId, address indexed signer, uint256 signaturesCount);
    event ProposalExecuted(uint256 indexed proposalId, address indexed executor);
    event ProposalCancelled(uint256 indexed proposalId, address indexed canceller);
    event SignerAdded(address indexed signer);
    event SignerRemoved(address indexed signer);
    event QuorumUpdated(uint256 oldQuorum, uint256 newQuorum);

    struct Proposal {
        bytes32 proposalHash;
        address target;
        bytes data;
        uint256 value;
        uint256 signaturesCount;
        uint256 createdAt;
        uint256 expiresAt;
        uint256 timelockUntil;
        bool executed;
        bool cancelled;
        address proposer;
        mapping(address signer => bool signed) signatures;
    }

    address[] public signers;
    mapping(address account => bool isSigner) public isSigner;

    uint256 public quorum;
    uint256 public proposalCount;
    uint256 public timelockDuration;

    mapping(uint256 proposalId => Proposal) public proposals;

    uint256 public constant PROPOSAL_EXPIRY = 7 days;
    uint256 public constant MIN_TIMELOCK = 48 hours;

    modifier onlySigner() {
        if (!isSigner[msg.sender]) revert MultiSigAdminErrors.NotSigner();
        _;
    }

    modifier onlySelf() {
        require(msg.sender == address(this), MultiSigAdminErrors.CallerNotSelf());
        _;
    }

    constructor(address[] memory _signers, uint256 _quorum, uint256 _timelockDuration) {
        if (_signers.length == 0) revert MultiSigAdminErrors.InvalidSigners();
        if (_quorum == 0 || _quorum > _signers.length) revert MultiSigAdminErrors.InvalidQuorum();
        if (_timelockDuration < MIN_TIMELOCK) revert MultiSigAdminErrors.InvalidTimelockDuration();

        for (uint256 i = 0; i < _signers.length; i++) {
            address signer = _signers[i];
            require(signer != address(0), MultiSigAdminErrors.InvalidSignerAddress());
            if (isSigner[signer]) revert MultiSigAdminErrors.DuplicateSigner();

            isSigner[signer] = true;
            signers.push(signer);
            emit SignerAdded(signer);
        }

        quorum = _quorum;
        timelockDuration = _timelockDuration;
    }

    function propose(address target, bytes calldata data, uint256 value)
        external
        onlySigner
        returns (uint256 proposalId)
    {
        require(target != address(0), MultiSigAdminErrors.AddressZeroNotAllowed());
        bytes32 hash = keccak256(abi.encode(target, data, value, proposalCount, block.chainid));

        proposalId = proposalCount++;

        Proposal storage p = proposals[proposalId];
        p.target = target;
        p.data = data;
        p.value = value;
        p.createdAt = block.timestamp;
        p.expiresAt = block.timestamp + PROPOSAL_EXPIRY;
        p.timelockUntil = block.timestamp + timelockDuration;
        p.proposer = msg.sender;

        p.signatures[msg.sender] = true;
        p.signaturesCount = 1;
        p.proposalHash = hash;

        emit ProposalCreated(proposalId, msg.sender, target, data, p.expiresAt, p.timelockUntil);
        emit ProposalSigned(proposalId, msg.sender, 1);
    }

    function sign(uint256 proposalId) external onlySigner {
        Proposal storage p = proposals[proposalId];

        if (p.createdAt == 0) revert MultiSigAdminErrors.ProposalNotFound();
        if (p.executed) revert MultiSigAdminErrors.AlreadyExecuted();
        if (p.cancelled) revert MultiSigAdminErrors.ProposalAlreadyCancelled();
        if (block.timestamp > p.expiresAt) revert MultiSigAdminErrors.ProposalExpired();
        if (p.signatures[msg.sender]) revert MultiSigAdminErrors.AlreadySigned();

        p.signatures[msg.sender] = true;
        p.signaturesCount++;

        emit ProposalSigned(proposalId, msg.sender, p.signaturesCount);
    }

    function execute(uint256 proposalId) external onlySigner nonReentrant {
        Proposal storage p = proposals[proposalId];

        bytes32 expectedHash = keccak256(abi.encode(p.target, p.data, p.value, proposalId, block.chainid));

        if (p.createdAt == 0) revert MultiSigAdminErrors.ProposalNotFound();
        if (p.executed) revert MultiSigAdminErrors.AlreadyExecuted();
        if (p.cancelled) revert MultiSigAdminErrors.ProposalAlreadyCancelled();
        if (block.timestamp > p.expiresAt) revert MultiSigAdminErrors.ProposalExpired();
        if (p.signaturesCount < quorum) revert MultiSigAdminErrors.QuorumNotReached();
        if (block.timestamp < p.timelockUntil) revert MultiSigAdminErrors.TimelockNotElapsed();
        if (expectedHash != p.proposalHash) revert MultiSigAdminErrors.ProposalHashMismatch();
        p.executed = true;

        (bool success, bytes memory result) = p.target.call{value: p.value}(p.data);

        if (!success) {
            if (result.length > 0) {
                assembly {
                    revert(add(result, 32), mload(result))
                }
            }
            revert MultiSigAdminErrors.ExecutionFailed();
        }

        emit ProposalExecuted(proposalId, msg.sender);
    }

    function cancel(uint256 proposalId) external nonReentrant {
        Proposal storage p = proposals[proposalId];
        if (msg.sender != p.proposer && msg.sender != address(this)) {
            revert MultiSigAdminErrors.NotProposer();
        }
        if (p.createdAt == 0) revert MultiSigAdminErrors.ProposalNotFound();
        if (p.executed) revert MultiSigAdminErrors.AlreadyExecuted();
        require(msg.sender == p.proposer || msg.sender == address(this), "Not proposer");

        p.cancelled = true;
        emit ProposalCancelled(proposalId, msg.sender);
    }

    function addSigner(address newSigner) external onlySelf {
        require(newSigner != address(0), MultiSigAdminErrors.InvalidSignerAddress());
        require(!isSigner[newSigner], MultiSigAdminErrors.AlreadyASigner());

        isSigner[newSigner] = true;
        signers.push(newSigner);
        emit SignerAdded(newSigner);
    }

    function removeSigner(address signerToRemove) external onlySelf {
        require(isSigner[signerToRemove], MultiSigAdminErrors.NotSigner());
        require(signers.length - 1 >= quorum, MultiSigAdminErrors.WrongQuorum());

        isSigner[signerToRemove] = false;
        for (uint256 i = 0; i < signers.length; i++) {
            if (signers[i] == signerToRemove) {
                signers[i] = signers[signers.length - 1];
                signers.pop();
                break;
            }
        }
        emit SignerRemoved(signerToRemove);
    }

    function updateQuorum(uint256 newQuorum) external onlySelf {
        if (newQuorum == 0 || newQuorum > signers.length) revert MultiSigAdminErrors.InvalidQuorum();
        uint256 oldQuorum = quorum;
        quorum = newQuorum;
        emit QuorumUpdated(oldQuorum, newQuorum);
    }

    function getSigners() external view returns (address[] memory) {
        return signers;
    }

    function hasSignedProposal(uint256 proposalId, address signer) external view returns (bool) {
        return proposals[proposalId].signatures[signer];
    }

    function getProposalState(uint256 proposalId)
        external
        view
        returns (
            address target,
            bool executed,
            bool cancelled,
            uint256 signaturesCount,
            uint256 expiresAt,
            uint256 timelockUntil,
            bool readyToExecute
        )
    {
        Proposal storage p = proposals[proposalId];
        return (
            p.target,
            p.executed,
            p.cancelled,
            p.signaturesCount,
            p.expiresAt,
            p.timelockUntil,
            p.signaturesCount >= quorum && block.timestamp >= p.timelockUntil && !p.executed && !p.cancelled
                && block.timestamp <= p.expiresAt
        );
    }

    receive() external payable {}
}
