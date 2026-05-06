// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library Roles {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 internal constant ISSUER_ROLE = keccak256("ISSUER_ROLE");
    bytes32 internal constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");
    bytes32 internal constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 internal constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 internal constant TREASURY_ROLE = keccak256("TREASURY_ROLE");
}
