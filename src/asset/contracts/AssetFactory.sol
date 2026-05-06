// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAccessControl} from "../../admin/interfaces/IAccessControl.sol";
import {Roles} from "../../admin/libraries/Roles.sol";
import {BaseAssetToken} from "./BaseAssetToken.sol";
import {IAssetFactory} from "../interfaces/IAssetFactory.sol";
import {Errors} from "../../admin/libraries/Errors.sol";
import {ITreasury} from "../../treasury/interfaces/ITreasury.sol";

contract AssetFactory is IAssetFactory {
    struct AssetCreationConfig {
        uint256 subscriptionPrice;
        uint256 redemptionPrice;
        bool selfServicePurchaseEnabled;
        bytes32 metadataHash;
    }

    mapping(uint256 proposalId => address asset) public assets;
    mapping(bytes32 assetTypeId => bool registered) public registeredAssetTypes;
    mapping(bytes32 assetTypeId => string name) public assetTypeNames;
    mapping(bytes32 assetTypeId => address implementation) public assetTypeImplementations;
    mapping(bytes32 assetTypeId => address[] assetsForType) public assetsByType;

    bytes32[] private _registeredAssetTypeIds;

    address[] public allAssets;
    uint256 public totalAssetsCreated;
    bool public paused;

    IAccessControl public immutable accessControl;
    address public complianceRegistry;
    address public treasury;

    event ComplianceRegistryUpdated(address indexed newRegistry, uint256 timestamp);
    event TreasuryUpdated(address indexed newTreasury, uint256 timestamp);

    modifier onlyAdmin() {
        if (!accessControl.hasRole(Roles.ADMIN_ROLE, msg.sender)) {
            revert Errors.Unauthorized();
        }
        _;
    }

    modifier onlyIssuerOrAdmin() {
        if (
            !accessControl.hasRole(Roles.ISSUER_ROLE, msg.sender)
                && !accessControl.hasRole(Roles.ADMIN_ROLE, msg.sender)
        ) {
            revert Errors.Unauthorized();
        }
        _;
    }

    modifier whenNotPaused() {
        require(!paused, Errors.ContractPaused());
        _;
    }

    constructor(address accessControlAddress, address complianceRegistryAddress, address treasuryAddress) {
        if (
            accessControlAddress == address(0) || complianceRegistryAddress == address(0)
                || treasuryAddress == address(0)
        ) {
            revert Errors.InvalidAddress();
        }

        accessControl = IAccessControl(accessControlAddress);
        complianceRegistry = complianceRegistryAddress;
        treasury = treasuryAddress;
    }

    function createAsset(
        uint256 proposalId,
        bytes32 assetTypeId,
        string memory name,
        string memory symbol,
        uint256 maxSupply,
        bytes memory data
    ) external onlyIssuerOrAdmin whenNotPaused returns (address tokenAddress) {
        if (!registeredAssetTypes[assetTypeId]) {
            revert Errors.AssetTypeNotRegistered(assetTypeId);
        }
        if (assets[proposalId] != address(0)) {
            revert Errors.ProposalAlreadyTokenized(proposalId);
        }
        if (maxSupply == 0) {
            revert Errors.InvalidAmount();
        }

        AssetCreationConfig memory config = _decodeAssetConfig(data);

        BaseAssetToken newToken = new BaseAssetToken(
            name,
            symbol,
            maxSupply,
            proposalId,
            assetTypeId,
            address(accessControl),
            complianceRegistry,
            treasury,
            config.subscriptionPrice,
            config.redemptionPrice,
            config.selfServicePurchaseEnabled,
            config.metadataHash
        );

        tokenAddress = address(newToken);

        assets[proposalId] = tokenAddress;
        assetsByType[assetTypeId].push(tokenAddress);
        allAssets.push(tokenAddress);
        totalAssetsCreated++;

        ITreasury(treasury).registerAssetToken(tokenAddress);

        emit AssetCreated(proposalId, tokenAddress, assetTypeId, msg.sender, block.timestamp);
    }

    function registerAssetType(bytes32 assetTypeId, string memory assetTypeName, address implementation)
        external
        onlyAdmin
    {
        require(!registeredAssetTypes[assetTypeId], Errors.AssetTypeAlreadyRegistered(assetTypeId));

        registeredAssetTypes[assetTypeId] = true;
        assetTypeNames[assetTypeId] = assetTypeName;
        assetTypeImplementations[assetTypeId] = implementation;
        _registeredAssetTypeIds.push(assetTypeId);

        emit AssetTypeRegistered(assetTypeId, assetTypeName, implementation, block.timestamp);
    }

    function unregisterAssetType(bytes32 assetTypeId) external onlyAdmin {
        require(registeredAssetTypes[assetTypeId], Errors.AssetTypeNotRegistered(assetTypeId));

        registeredAssetTypes[assetTypeId] = false;
        emit AssetTypeUnregistered(assetTypeId, block.timestamp);
    }

    function pauseFactory() external onlyAdmin {
        paused = true;
        emit FactoryPaused(msg.sender, block.timestamp);
    }

    function unpauseFactory() external onlyAdmin {
        paused = false;
        emit FactoryUnpaused(msg.sender, block.timestamp);
    }

    function isAssetTypeRegistered(bytes32 assetTypeId) external view returns (bool) {
        return registeredAssetTypes[assetTypeId];
    }

    function getAssetTypeImplementation(bytes32 assetTypeId) external view returns (address) {
        return assetTypeImplementations[assetTypeId];
    }

    function getAssetTypeName(bytes32 assetTypeId) external view returns (string memory) {
        return assetTypeNames[assetTypeId];
    }

    function getAllRegisteredAssetTypes() external view returns (bytes32[] memory) {
        uint256 activeCount;
        for (uint256 i = 0; i < _registeredAssetTypeIds.length; i++) {
            if (registeredAssetTypes[_registeredAssetTypeIds[i]]) {
                activeCount++;
            }
        }

        bytes32[] memory result = new bytes32[](activeCount);
        uint256 cursor;
        for (uint256 i = 0; i < _registeredAssetTypeIds.length; i++) {
            bytes32 assetTypeId = _registeredAssetTypeIds[i];
            if (registeredAssetTypes[assetTypeId]) {
                result[cursor] = assetTypeId;
                cursor++;
            }
        }

        return result;
    }

    function getAssetAddress(uint256 proposalId) external view returns (address tokenAddress) {
        return assets[proposalId];
    }

    function getAllAssets() external view returns (address[] memory) {
        return allAssets;
    }

    function getAssetsByType(bytes32 assetTypeId) external view returns (address[] memory) {
        return assetsByType[assetTypeId];
    }

    function getTotalAssetsCreated() external view returns (uint256 count) {
        return totalAssetsCreated;
    }

    function _decodeAssetConfig(bytes memory data) internal pure returns (AssetCreationConfig memory config) {
        if (data.length == 0) {
            return AssetCreationConfig({
                subscriptionPrice: 1e6, redemptionPrice: 1e6, selfServicePurchaseEnabled: true, metadataHash: bytes32(0)
            });
        }

        return abi.decode(data, (AssetCreationConfig));
    }

    function setComplianceRegistry(address newRegistry) external onlyAdmin {
        if (newRegistry == address(0)) revert Errors.InvalidAddress();
        complianceRegistry = newRegistry;
        emit ComplianceRegistryUpdated(newRegistry, block.timestamp);
    }

    function setTreasury(address newTreasury) external onlyAdmin {
        if (newTreasury == address(0)) revert Errors.InvalidAddress();
        treasury = newTreasury;
        emit TreasuryUpdated(newTreasury, block.timestamp);
    }
}
