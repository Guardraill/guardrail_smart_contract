// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAccessControl} from "../interfaces/IAccessControl.sol";
import {Roles} from "../libraries/Roles.sol";
import {Errors} from "../libraries/Errors.sol";

contract AccessControl is IAccessControl {
    //Create a struct to hold role data, including members and admin role
    //adminrole is the role that can manage (grant/revoke) the given role

    struct RoleData {
        mapping(address account => bool) members;
        bytes32 adminRole;
    }

    mapping(bytes32 role => RoleData) private _roles;

    bytes32 public constant DEFAULT_ADMIN_ROLE = Roles.DEFAULT_ADMIN_ROLE;
    bytes32 public constant ADMIN_ROLE = Roles.ADMIN_ROLE;
    bytes32 public constant ISSUER_ROLE = Roles.ISSUER_ROLE;
    bytes32 public constant COMPLIANCE_ROLE = Roles.COMPLIANCE_ROLE;
    bytes32 public constant ORACLE_ROLE = Roles.ORACLE_ROLE;
    bytes32 public constant OPERATOR_ROLE = Roles.OPERATOR_ROLE;
    bytes32 public constant PAUSER_ROLE = Roles.PAUSER_ROLE;
    bytes32 public constant TREASURY_ROLE = Roles.TREASURY_ROLE;

    modifier onlyRole(bytes32 role) {
        _checkRole(role);
        _;
    }

    constructor(address defaultAdmin, address operationalAdmin) {
        require(defaultAdmin != address(0), Errors.InvalidAddress());
        require(operationalAdmin != address(0), Errors.InvalidAddress());

        _setRoleAdmin(DEFAULT_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(ISSUER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(COMPLIANCE_ROLE, ADMIN_ROLE);
        _setRoleAdmin(ORACLE_ROLE, ADMIN_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(PAUSER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(TREASURY_ROLE, ADMIN_ROLE);

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(ADMIN_ROLE, operationalAdmin);
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role].members[account];
    }

    function getRoleAdmin(bytes32 role) public view returns (bytes32) {
        bytes32 adminRole = _roles[role].adminRole;
        if (adminRole == bytes32(0) && role != DEFAULT_ADMIN_ROLE) {
            return DEFAULT_ADMIN_ROLE;
        }
        return adminRole;
    }

    function grantRole(bytes32 role, address account) external onlyRole(getRoleAdmin(role)) {
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external onlyRole(getRoleAdmin(role)) {
        _revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address account) external {
        require(account == msg.sender, Errors.CanOnlyRenounceOwnRole());
        _revokeRole(role, account);
    }

    function _checkRole(bytes32 role) internal view {
        require(hasRole(role, msg.sender), Errors.MissingRole(role, msg.sender));
    }

    function _grantRole(bytes32 role, address account) internal {
        require(account != address(0), Errors.InvalidAddress());

        if (!hasRole(role, account)) {
            _roles[role].members[account] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }

    function _revokeRole(bytes32 role, address account) internal {
        if (hasRole(role, account)) {
            _roles[role].members[account] = false;
            emit RoleRevoked(role, account, msg.sender);
        }
    }

    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal {
        bytes32 previousAdminRole = getRoleAdmin(role);
        _roles[role].adminRole = adminRole;
        emit RoleAdminChanged(role, previousAdminRole, adminRole);
    }
}
