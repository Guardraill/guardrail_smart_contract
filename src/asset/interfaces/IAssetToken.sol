// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IAssetToken {
    enum AssetState {
        Active,
        Paused,
        Matured,
        Defaulted,
        Liquidated
    }

    event Issued(address indexed operator, address indexed to, uint256 amount, bytes data, uint256 timestamp);
    event YieldDistributed(address indexed operator, uint256 totalAmount, uint256 holderCount, uint256 timestamp);
    event YieldClaimed(address indexed investor, address indexed recipient, uint256 amount, uint256 timestamp);
    event RedemptionRequested(address indexed investor, uint256 tokenAmount, bytes data, uint256 timestamp);
    event RedemptionCancelled(address indexed investor, uint256 tokenAmount, uint256 timestamp);
    event Redeemed(
        address indexed operator,
        address indexed from,
        uint256 tokenAmount,
        uint256 valueReturned,
        bytes data,
        uint256 timestamp
    );
    event AssetStateChanged(AssetState oldState, AssetState newState, uint256 timestamp);
    event ControllerTransfer(
        address indexed controller,
        address indexed from,
        address indexed to,
        uint256 amount,
        bytes data,
        bytes operatorData
    );
    event TokensPurchased(address indexed buyer, uint256 tokenAmount, uint256 cost, uint256 timestamp);
    event PricingUpdated(uint256 subscriptionPrice, uint256 redemptionPrice, uint256 timestamp);
    event MetadataHashUpdated(bytes32 indexed metadataHash, uint256 timestamp);
    event SelfServicePurchaseUpdated(bool enabled, uint256 timestamp);
    event ComplianceRegistryUpdated(address indexed registry, uint256 timestamp);
    event TreasuryUpdated(address indexed treasury, uint256 timestamp);

    function issue(address to, uint256 amount, bytes memory data) external returns (bool success);
    function burn(address from, uint256 amount) external returns (bool success);
    function distributeYield(uint256 amount, bytes memory data) external returns (bool success);
    function claimYield(address recipient) external returns (uint256 claimedAmount);
    function redeem(uint256 amount, bytes memory data) external returns (uint256 valueReturned);
    function processRedemption(address investor, uint256 amount, address recipient, bytes memory data)
        external
        returns (uint256 valueReturned);
    function cancelRedemption(uint256 amount) external returns (bool cancelled);

    function previewPurchase(uint256 tokenAmount) external view returns (uint256 cost);
    function previewRedemption(uint256 tokenAmount) external view returns (uint256 valueReturned);
    function claimableYieldOf(address account) external view returns (uint256 amount);
    function pendingRedemptionOf(address account) external view returns (uint256 amount);
    function lockedBalanceOf(address account) external view returns (uint256 amount);

    function canTransfer(address to, uint256 amount, bytes memory data)
        external
        view
        returns (bytes1 statusCode, bytes32 reasonCode);

    function getAssetState() external view returns (AssetState state);
    function getAssetTypeId() external view returns (bytes32 assetTypeId);
    function getProposalId() external view returns (uint256 proposalId);
    function isControllable() external view returns (bool isControllable);
    function pricePerToken() external view returns (uint256);
    function redemptionPricePerToken() external view returns (uint256);
    function maxSupply() external view returns (uint256);
    function treasury() external view returns (address);
    function paymentToken() external view returns (address);
    function metadataHash() external view returns (bytes32);

    function setAssetState(AssetState newState) external;
    function setComplianceRegistry(address registry) external;
    function setTreasury(address treasuryAddress) external;
    function setPricePerToken(uint256 newPrice) external;
    function setRedemptionPricePerToken(uint256 newPrice) external;
    function setPricing(uint256 newSubscriptionPrice, uint256 newRedemptionPrice) external;
    function setSelfServicePurchaseEnabled(bool enabled) external;
    function setMetadataHash(bytes32 newMetadataHash) external;
    function disableController() external;

    function controllerTransfer(address from, address to, uint256 amount, bytes memory data, bytes memory operatorData)
        external;
    function purchase(uint256 tokenAmount) external;

    error ComplianceFailure(bytes32 reason);

    error MaxSupplyExceeded();

    error SelfServicePurchaseDisabled();

    error InsufficientUnlockedBalance();

    error NoClaimableYield();

    error PendingRedemptionTooLarge();

    error Unauthorized();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidState();

    error BurnRequiresPendingRedemption();
}
