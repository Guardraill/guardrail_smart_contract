// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IAssetFactory {
    event AssetCreated(
        uint256 indexed proposalId,
        address indexed tokenAddress,
        bytes32 indexed assetTypeId,
        address creator,
        uint256 timestamp
    );
    event AssetTypeRegistered(
        bytes32 indexed assetTypeId, string assetTypeName, address implementation, uint256 timestamp
    );
    event AssetTypeUnregistered(bytes32 indexed assetTypeId, uint256 timestamp);
    event FactoryPaused(address indexed by, uint256 timestamp);
    event FactoryUnpaused(address indexed by, uint256 timestamp);

    function createAsset(
        uint256 proposalId,
        bytes32 assetTypeId,
        string memory name,
        string memory symbol,
        uint256 maxSupply,
        bytes memory data
    ) external returns (address tokenAddress);

    function registerAssetType(bytes32 assetTypeId, string memory assetTypeName, address implementation) external;
    function unregisterAssetType(bytes32 assetTypeId) external;

    function isAssetTypeRegistered(bytes32 assetTypeId) external view returns (bool);
    function getAssetTypeImplementation(bytes32 assetTypeId) external view returns (address);
    function getAssetTypeName(bytes32 assetTypeId) external view returns (string memory);
    function getAllRegisteredAssetTypes() external view returns (bytes32[] memory);

    function getAssetAddress(uint256 proposalId) external view returns (address tokenAddress);
    function getAllAssets() external view returns (address[] memory assets);
    function getAssetsByType(bytes32 assetTypeId) external view returns (address[] memory assets);
    function getTotalAssetsCreated() external view returns (uint256 count);
    function paused() external view returns (bool isPaused);

    function pauseFactory() external;
    function unpauseFactory() external;
}
