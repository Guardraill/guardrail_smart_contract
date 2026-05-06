// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IOracleDataBridge {
    struct AssetValuation {
        uint256 assetValue;
        uint256 navPerToken;
        uint64 updatedAt;
        bytes32 referenceId;
    }

    event TrustedOracleUpdated(address indexed oracle, bool trusted);
    event ValuationSubmitted(
        address indexed asset, uint256 assetValue, uint256 navPerToken, bytes32 indexed referenceId, uint256 timestamp
    );
    event DocumentAnchored(
        address indexed asset,
        bytes32 indexed documentType,
        bytes32 indexed documentHash,
        bytes32 referenceId,
        uint256 timestamp
    );

    function setTrustedOracle(address oracle, bool trusted) external;
    function submitValuation(address asset, uint256 assetValue, uint256 navPerToken, bytes32 referenceId) external;
    function submitValuationAndSyncPricing(
        address asset,
        uint256 assetValue,
        uint256 navPerToken,
        uint256 subscriptionPrice,
        uint256 redemptionPrice,
        bytes32 referenceId
    ) external;
    function anchorDocument(address asset, bytes32 documentType, bytes32 documentHash, bytes32 referenceId) external;

    function getLatestValuation(address asset) external view returns (AssetValuation memory valuation);
    function getDocumentHash(address asset, bytes32 documentType) external view returns (bytes32 documentHash);
}
