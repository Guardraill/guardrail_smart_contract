// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICompliance {
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

    event AddressWhitelisted(address indexed investor, address indexed addedBy, uint256 timestamp);
    event AddressRemovedFromWhitelist(address indexed investor, address indexed removedBy, uint256 timestamp);
    event InvestorStatusUpdated(
        address indexed investor, bool isAccredited, address indexed updatedBy, uint256 timestamp
    );
    event InvestorDataUpdated(address indexed investor, bytes32 indexed externalRef, uint256 timestamp);
    event AssetRulesUpdated(address indexed asset, uint256 timestamp);
    event JurisdictionRestrictionUpdated(address indexed asset, bytes32 indexed jurisdiction, bool restricted);

    function addToWhitelist(address investor) external;
    function removeFromWhitelist(address investor) external;
    function batchAddToWhitelist(address[] memory investors) external;
    function isWhitelisted(address investor) external view returns (bool isWhitelisted);

    function setInvestorStatus(address investor, bool isAccredited) external;
    function isAccredited(address investor) external view returns (bool isAccredited);

    function setInvestorData(address investor, InvestorData calldata data) external;
    function batchSetInvestorData(address[] calldata investors, InvestorData[] calldata data) external;
    function getInvestorData(address investor) external view returns (InvestorData memory data);

    function setAssetRules(address asset, AssetRules calldata rules) external;
    function getAssetRules(address asset) external view returns (AssetRules memory rules);

    function setJurisdictionRestriction(address asset, bytes32 jurisdiction, bool restricted) external;
    function isJurisdictionRestricted(address asset, bytes32 jurisdiction) external view returns (bool restricted);

    function canTransfer(address asset, address from, address to, uint256 amount, uint256 receivingBalance)
        external
        view
        returns (bool isValid, bytes32 reason);

    function canSubscribe(address asset, address investor, uint256 amount, uint256 resultingBalance)
        external
        view
        returns (bool isValid, bytes32 reason);

    function canRedeem(address asset, address investor, uint256 amount)
        external
        view
        returns (bool isValid, bytes32 reason);

    error NotComplianceOfficer();

    error InvalidInvestor();

    error InvalidAsset();

    error BatchLengthMismatch();

    error ComplianceCheckFailed(bytes32 reason);
}
