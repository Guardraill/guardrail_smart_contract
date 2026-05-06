// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LibComplianceStorage} from "../libraries/LibComplianceStorage.sol";
import {IAccessControl} from "../../admin/interfaces/IAccessControl.sol";
import {Roles} from "../../admin/libraries/Roles.sol";
import {Errors} from "../../admin/libraries/Errors.sol";

/// @notice the read-only compliance gate.
///         Contains canTransfer, canSubscribe and canRedeem — the three
///         functions called by BaseAssetToken before every token movement.
///         This is the most performance-critical facet — it is called on
///         every purchase, transfer and redemption.


contract ComplianceCheckFacet {
   
    bytes32 private constant TRANSFERS_DISABLED = keccak256("TRANSFERS_DISABLED");
    bytes32 private constant SUBSCRIPTIONS_DISABLED = keccak256("SUBSCRIPTIONS_DISABLED");
    bytes32 private constant REDEMPTIONS_DISABLED = keccak256("REDEMPTIONS_DISABLED");
    bytes32 private constant SENDER_NOT_ELIGIBLE = keccak256("SENDER_NOT_ELIGIBLE");
    bytes32 private constant RECIPIENT_NOT_ELIGIBLE = keccak256("RECIPIENT_NOT_ELIGIBLE");
    bytes32 private constant SENDER_JURISDICTION_RESTRICTED = keccak256("SENDER_JURISDICTION_RESTRICTED");
    bytes32 private constant RECIPIENT_JURISDICTION_RESTRICTED = keccak256("RECIPIENT_JURISDICTION_RESTRICTED");
    bytes32 private constant ACCREDITATION_REQUIRED = keccak256("ACCREDITATION_REQUIRED");
    bytes32 private constant BELOW_MIN_INVESTMENT = keccak256("BELOW_MIN_INVESTMENT");
    bytes32 private constant MAX_BALANCE_EXCEEDED = keccak256("MAX_BALANCE_EXCEEDED");
    bytes32 private constant INVESTOR_NOT_ELIGIBLE = keccak256("INVESTOR_NOT_ELIGIBLE");
    bytes32 private constant JURISDICTION_RESTRICTED = keccak256("JURISDICTION_RESTRICTED");

    modifier onlyComplianceOrAdmin() {
        LibComplianceStorage.Layout storage l = LibComplianceStorage.layout();
        IAccessControl ac = IAccessControl(l.accessControl);
        if (!ac.hasRole(Roles.COMPLIANCE_ROLE, msg.sender) && !ac.hasRole(Roles.ADMIN_ROLE, msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    error Unauthorized();
    error InvalidInvestor();
    event InvestorDataUpdated(address investor, uint256 timestamp);

    function canTransfer(address asset, address from, address to, uint256 amount, uint256 receivingBalance)
        external
        view
        returns (bool isValid, bytes32 reason)
    {
        LibComplianceStorage.Layout storage l = LibComplianceStorage.layout();
        LibComplianceStorage.AssetRules storage rules = l.assetRules[asset];

        // 1. Asset-level transfer switch
        if (!rules.transfersEnabled) {
            return (false, TRANSFERS_DISABLED);
        }

        // 2. Sender checks — skip for mints (from == address(0))
        if (from != address(0)) {
            LibComplianceStorage.InvestorData storage senderData = l.investors[from];
            if (!_isInvestorActive(senderData)) {
                return (false, SENDER_NOT_ELIGIBLE);
            }
            if (l.restrictedJurisdictions[asset][senderData.jurisdiction]) {
                return (false, SENDER_JURISDICTION_RESTRICTED);
            }
        }

        // 3. Recipient checks — skip for burns (to == address(0))
        if (to != address(0)) {
            LibComplianceStorage.InvestorData storage recipientData = l.investors[to];
            if (!_isInvestorActive(recipientData)) {
                return (false, RECIPIENT_NOT_ELIGIBLE);
            }
            if (l.restrictedJurisdictions[asset][recipientData.jurisdiction]) {
                return (false, RECIPIENT_JURISDICTION_RESTRICTED);
            }

            // 4. Accreditation gate
            if (rules.requiresAccreditation && !recipientData.isAccredited) {
                return (false, ACCREDITATION_REQUIRED);
            }

            // 5. Minimum investment check — only for mints (purchases)
            if (from == address(0) && rules.minInvestment > 0) {
                if (amount < rules.minInvestment) {
                    return (false, BELOW_MIN_INVESTMENT);
                }
            }

            // 6. Maximum balance check
            if (rules.maxInvestorBalance > 0) {
                if (receivingBalance + amount > rules.maxInvestorBalance) {
                    return (false, MAX_BALANCE_EXCEEDED);
                }
            }
        }

        return (true, bytes32(0));
    }

    function canSubscribe(address asset, address investor, uint256 amount, uint256 resultingBalance)
        external
        view
        returns (bool isValid, bytes32 reason)
    {
        LibComplianceStorage.Layout storage l = LibComplianceStorage.layout();
        LibComplianceStorage.AssetRules storage rules = l.assetRules[asset];

        // 1. Asset-level subscription switch
        if (!rules.subscriptionsEnabled) {
            return (false, SUBSCRIPTIONS_DISABLED);
        }

        // 2. Investor active check
        LibComplianceStorage.InvestorData storage investorData = l.investors[investor];
        if (!_isInvestorActive(investorData)) {
            return (false, INVESTOR_NOT_ELIGIBLE);
        }

        // 3. Jurisdiction check
        if (l.restrictedJurisdictions[asset][investorData.jurisdiction]) {
            return (false, JURISDICTION_RESTRICTED);
        }

        // 4. Accreditation gate
        if (rules.requiresAccreditation && !investorData.isAccredited) {
            return (false, ACCREDITATION_REQUIRED);
        }

        // 5. Minimum investment
        if (rules.minInvestment > 0 && amount < rules.minInvestment) {
            return (false, BELOW_MIN_INVESTMENT);
        }

        if (rules.maxInvestorBalance > 0 && resultingBalance > rules.maxInvestorBalance) {
            return (false, MAX_BALANCE_EXCEEDED);
        }

        return (true, bytes32(0));
    }

    /// @notice Check whether an investor may redeem (request redemption of) an asset.
    ///         Called by BaseAssetToken.redeem() before locking tokens.
    ///
    
    function canRedeem(address asset, address investor, uint256 amount)
        external
        view
        returns (bool isValid, bytes32 reason)
    {
        LibComplianceStorage.Layout storage l = LibComplianceStorage.layout();
        LibComplianceStorage.AssetRules storage rules = l.assetRules[asset];

        amount;

        // 1. Asset-level redemption switch
        if (!rules.redemptionsEnabled) {
            return (false, REDEMPTIONS_DISABLED);
        }

        // 2. Investor active check — frozen investors cannot redeem
        LibComplianceStorage.InvestorData storage investorData = l.investors[investor];
        if (!_isInvestorActive(investorData)) {
            return (false, INVESTOR_NOT_ELIGIBLE);
        }

        // 3. Jurisdiction check
        if (l.restrictedJurisdictions[asset][investorData.jurisdiction]) {
            return (false, JURISDICTION_RESTRICTED);
        }

        return (true, bytes32(0));
    }

    // validUntil == 0 is an explicit sentinel meaning permanent whitelist.
    
    function _isInvestorActive(LibComplianceStorage.InvestorData storage data) internal view returns (bool) {
        if (!data.isVerified || data.isFrozen) return false;
        return data.validUntil == 0 || data.validUntil >= block.timestamp;
    }

    function setInvestorData(address investor, LibComplianceStorage.InvestorData calldata data)
        external
        onlyComplianceOrAdmin
    {
        if (investor == address(0)) revert InvalidInvestor();
        
        if (data.validUntil != 0 && data.validUntil <= block.timestamp) {
            revert InvalidInvestor(); 
        }
        LibComplianceStorage.Layout storage l = LibComplianceStorage.layout();
        l.investors[investor] = data;
        emit InvestorDataUpdated(investor, block.timestamp);
    }
}
