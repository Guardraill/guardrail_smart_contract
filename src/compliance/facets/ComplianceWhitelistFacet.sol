// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LibComplianceStorage} from "../libraries/LibComplianceStorage.sol";
import {IAccessControl} from "../../admin/interfaces/IAccessControl.sol";
import {Roles} from "../../admin/libraries/Roles.sol";


/// @notice Facet 1 of 3 — manages the KYC/AML whitelist of investors.
///         Handles all operations that create, update or remove investor
///         profiles from the compliance registry.
///

contract ComplianceWhitelistFacet {
    uint256 public constant MAX_BATCH_SIZE = 200;

    
    event InvestorWhitelisted(address indexed investor, uint256 timestamp);
    event InvestorRemovedFromWhitelist(address indexed investor, uint256 timestamp);
    event InvestorDataUpdated(address indexed investor, uint256 timestamp);
    event BatchWhitelistProcessed(uint256 count, uint256 timestamp);

    
    error Unauthorized();
    error InvalidInvestor();
    error BatchLengthMismatch();
    error BatchTooLarge(uint256 provided, uint256 maximum);

    

    modifier onlyComplianceOrAdmin() {
        LibComplianceStorage.Layout storage l = LibComplianceStorage.layout();
        IAccessControl ac = IAccessControl(l.accessControl);
        if (!ac.hasRole(Roles.COMPLIANCE_ROLE, msg.sender) && !ac.hasRole(Roles.ADMIN_ROLE, msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    
    function addToWhitelist(address investor) external onlyComplianceOrAdmin {
        if (investor == address(0)) revert InvalidInvestor();
        LibComplianceStorage.Layout storage l = LibComplianceStorage.layout();
        l.investors[investor].isVerified = true;
        l.investors[investor].isFrozen = false;
        emit InvestorWhitelisted(investor, block.timestamp);
    }

    
    function removeFromWhitelist(address investor) external onlyComplianceOrAdmin {
        if (investor == address(0)) revert InvalidInvestor();
        LibComplianceStorage.Layout storage l = LibComplianceStorage.layout();
        l.investors[investor].isVerified = false;
        emit InvestorRemovedFromWhitelist(investor, block.timestamp);
    }

    
    function batchAddToWhitelist(address[] calldata investors) external onlyComplianceOrAdmin {
        if (investors.length > MAX_BATCH_SIZE) {
            revert BatchTooLarge(investors.length, MAX_BATCH_SIZE);
        }
        LibComplianceStorage.Layout storage l = LibComplianceStorage.layout();
        for (uint256 i = 0; i < investors.length; i++) {
            if (investors[i] == address(0)) revert InvalidInvestor();
            l.investors[investors[i]].isVerified = true;
            l.investors[investors[i]].isFrozen = false;
        }
        emit BatchWhitelistProcessed(investors.length, block.timestamp);
    }

    
    function setInvestorStatus(address investor, bool investorIsAccredited) external onlyComplianceOrAdmin {
        if (investor == address(0)) revert InvalidInvestor();
        LibComplianceStorage.Layout storage l = LibComplianceStorage.layout();
        l.investors[investor].isAccredited = investorIsAccredited;
        emit InvestorDataUpdated(investor, block.timestamp);
    }

    
    function setInvestorData(address investor, LibComplianceStorage.InvestorData calldata data)
        external
        onlyComplianceOrAdmin
    {
        if (investor == address(0)) revert InvalidInvestor();
        LibComplianceStorage.Layout storage l = LibComplianceStorage.layout();
        l.investors[investor] = data;
        emit InvestorDataUpdated(investor, block.timestamp);
    }

    
    function batchSetInvestorData(address[] calldata investors, LibComplianceStorage.InvestorData[] calldata data)
        external
        onlyComplianceOrAdmin
    {
        if (investors.length > MAX_BATCH_SIZE) {
            revert BatchTooLarge(investors.length, MAX_BATCH_SIZE);
        }
        if (investors.length != data.length) revert BatchLengthMismatch();
        if (investors.length != data.length) revert BatchLengthMismatch();
        LibComplianceStorage.Layout storage l = LibComplianceStorage.layout();
        for (uint256 i = 0; i < investors.length; i++) {
            if (investors[i] == address(0)) revert InvalidInvestor();
            l.investors[investors[i]] = data[i];
        }
        emit BatchWhitelistProcessed(investors.length, block.timestamp);
    }

    

    
    function getInvestorData(address investor) external view returns (LibComplianceStorage.InvestorData memory) {
        return LibComplianceStorage.layout().investors[investor];
    }

    
    function isInvestorActive(address investor) external view returns (bool) {
        return _isInvestorActive(LibComplianceStorage.layout().investors[investor]);
    }

    

    function _isInvestorActive(LibComplianceStorage.InvestorData memory data) internal view returns (bool) {
        if (!data.isVerified || data.isFrozen) return false;
        return data.validUntil == 0 || data.validUntil >= block.timestamp;
    }

    function isWhitelisted(address investor) external view returns (bool) {
        LibComplianceStorage.Layout storage l = LibComplianceStorage.layout();
        return _isInvestorActive(l.investors[investor]);
    }

    function isAccredited(address investor) external view returns (bool) {
        return LibComplianceStorage.layout().investors[investor].isAccredited;
    }
}
