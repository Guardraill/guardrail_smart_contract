// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LibComplianceStorage} from "../libraries/LibComplianceStorage.sol";
import {IAccessControl} from "../../admin/interfaces/IAccessControl.sol";
import {Roles} from "../../admin/libraries/Roles.sol";


/// @notice  manages per-asset compliance rule sets and
///         jurisdiction restrictions. Every asset token deployed by
///         AssetFactory must have its rules configured here before any
///         investor can interact with it.
///

contract ComplianceRulesFacet {

    event AssetRulesSet(address indexed asset, uint256 timestamp);
    event JurisdictionRestrictionUpdated(
        address indexed asset, bytes32 indexed jurisdiction, bool restricted, uint256 timestamp
    );
    event AccessControlUpdated(address indexed newAccessControl, uint256 timestamp);

    error Unauthorized();
    error InvalidAsset();
    error InvalidAddress();

    

    modifier onlyAdmin() {
        LibComplianceStorage.Layout storage l = LibComplianceStorage.layout();
        IAccessControl ac = IAccessControl(l.accessControl);
        if (!ac.hasRole(Roles.ADMIN_ROLE, msg.sender)) revert Unauthorized();
        _;
    }

    modifier onlyComplianceOrAdmin() {
        LibComplianceStorage.Layout storage l = LibComplianceStorage.layout();
        IAccessControl ac = IAccessControl(l.accessControl);
        if (!ac.hasRole(Roles.COMPLIANCE_ROLE, msg.sender) && !ac.hasRole(Roles.ADMIN_ROLE, msg.sender)) {
            revert Unauthorized();
        }
        _;
    }


    // Configure the compliance rules for a specific asset token.
    // Must be called for every newly deployed asset before investors
    // can interact — default zero-value rules block all operations.
    
    function setAssetRules(address asset, LibComplianceStorage.AssetRules calldata rules)
        external
        onlyComplianceOrAdmin
    {
        if (asset == address(0)) revert InvalidAsset();
        LibComplianceStorage.Layout storage l = LibComplianceStorage.layout();
        l.assetRules[asset] = rules;
        emit AssetRulesSet(asset, block.timestamp);
    }

    
    function setJurisdictionRestriction(address asset, bytes32 jurisdiction, bool restricted)
        external
        onlyComplianceOrAdmin
    {
        if (asset == address(0)) revert InvalidAsset();
        LibComplianceStorage.Layout storage l = LibComplianceStorage.layout();
        l.restrictedJurisdictions[asset][jurisdiction] = restricted;
        emit JurisdictionRestrictionUpdated(asset, jurisdiction, restricted, block.timestamp);
    }


    function setAccessControl(address newAccessControl) external onlyAdmin {
        if (newAccessControl == address(0)) revert InvalidAddress();
        LibComplianceStorage.Layout storage l = LibComplianceStorage.layout();
        l.accessControl = newAccessControl;
        emit AccessControlUpdated(newAccessControl, block.timestamp);
    }

    

    
    function getAssetRules(address asset) external view returns (LibComplianceStorage.AssetRules memory) {
        return LibComplianceStorage.layout().assetRules[asset];
    }

    
    function isJurisdictionRestricted(address asset, bytes32 jurisdiction) external view returns (bool) {
        return LibComplianceStorage.layout().restrictedJurisdictions[asset][jurisdiction];
    }

    
    function getAccessControl() external view returns (address) {
        return LibComplianceStorage.layout().accessControl;
    }
}
