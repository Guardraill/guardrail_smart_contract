// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;


//Shared custom errors used across multiple contracts

library Errors {
    error Unauthorized();
    error NotAdmin();
    error CanOnlyRenounceOwnRole();
    error MissingRole(bytes32 role, address account);
    error InvalidAddress();
    error InvalidAmount();
    error LengthMismatch(uint256 expected, uint256 actual);
    error InvalidState();
    error ContractPaused();
    error ContractNotPaused();
    error AssetTypeNotRegistered(bytes32 assetTypeId);
    error AssetTypeAlreadyRegistered(bytes32 assetTypeId);
    error ProposalAlreadyTokenized(uint256 proposalId);
}
