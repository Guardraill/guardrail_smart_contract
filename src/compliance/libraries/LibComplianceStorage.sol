// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;


/// @notice Diamond storage library for the ComplianceDiamond.
///         All state that the ComplianceRegistry previously held in
///         regular contract storage slots now lives here, isolated
///         inside a pseudo-random keccak256 slot that cannot collide
///         with LibDiamond's own storage or any future facet.
///

library LibComplianceStorage {
   
    bytes32 internal constant COMPLIANCE_STORAGE_POSITION = keccak256("guardrail.compliance.storage.v1");

   

    
    struct InvestorData {
        bool isVerified; 
        bool isAccredited; 
        bool isFrozen; 
        uint64 validUntil; 
        bytes32 jurisdiction; 
        bytes32 externalRef; 
    }

    
    struct AssetRules {
        bool transfersEnabled; 
        bool subscriptionsEnabled; 
        bool redemptionsEnabled; 
        bool requiresAccreditation; 
        uint256 minInvestment; 
        uint256 maxInvestorBalance; 
    }


    struct Layout {
        
        address accessControl;
        mapping(address investor => InvestorData data) investors;
        mapping(address asset => AssetRules rules) assetRules;
        mapping(address asset => mapping(bytes32 jurisdiction => bool restricted)) restrictedJurisdictions;
        bool initialized;
    }

    
    function layout() internal pure returns (Layout storage l) {
        bytes32 position = COMPLIANCE_STORAGE_POSITION;
        assembly {
            l.slot := position
        }
    }
}
