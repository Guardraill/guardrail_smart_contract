// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Custom errors used in the MultiSigAdmin contract

library MultiSigAdminErrors {
    error NotSigner();
    error AlreadySigned();
    error AlreadyASigner();
    error AlreadyExecuted();
    error ProposalNotFound();
    error QuorumNotReached();
    error ExecutionFailed();
    error InvalidQuorum();
    error InvalidSigners();
    error DuplicateSigner();
    error ProposalExpired();
    error TimelockNotElapsed();
    error WrongQuorum();
    error InvalidSignerAddress();
    error AddressZeroNotAllowed();

    error ProposalAlreadyCancelled();
    error InvalidTimelockDuration();
    error ProposalHashMismatch();
    error NotProposer();
    error CallerNotSelf();
}
