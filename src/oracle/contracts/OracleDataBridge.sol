// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAccessControl} from "../../admin/interfaces/IAccessControl.sol";
import {Roles} from "../../admin/libraries/Roles.sol";
import {IAssetToken} from "../../asset/interfaces/IAssetToken.sol";
import {IOracleDataBridge} from "../interfaces/IOracleDataBridge.sol";

contract OracleDataBridge is IOracleDataBridge {
    error Unauthorized();
    error InvalidAddress();
    error InvalidAmount();
    error ValuationStale(address asset, uint64 updatedAt);

    IAccessControl public immutable accessControl;

    uint256 public constant MAX_VALUATION_AGE = 90 days;

    mapping(address oracle => bool trusted) public trustedOracles;
    mapping(address asset => AssetValuation valuation) private _valuations;
    mapping(address asset => mapping(bytes32 documentType => bytes32 documentHash)) private _documentHashes;

    modifier onlyAdmin() {
        if (!accessControl.hasRole(Roles.ADMIN_ROLE, msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    modifier onlyOracle() {
        if (
            !trustedOracles[msg.sender] && !accessControl.hasRole(Roles.ORACLE_ROLE, msg.sender)
                && !accessControl.hasRole(Roles.ADMIN_ROLE, msg.sender)
        ) {
            revert Unauthorized();
        }
        _;
    }

    constructor(address accessControlAddress) {
        if (accessControlAddress == address(0)) {
            revert InvalidAddress();
        }

        accessControl = IAccessControl(accessControlAddress);
    }

    function setTrustedOracle(address oracle, bool trusted) external onlyAdmin {
        if (oracle == address(0)) {
            revert InvalidAddress();
        }

        trustedOracles[oracle] = trusted;
        emit TrustedOracleUpdated(oracle, trusted);
    }

    function submitValuation(address asset, uint256 assetValue, uint256 navPerToken, bytes32 referenceId)
        external
        onlyOracle
    {
        _submitValuation(asset, assetValue, navPerToken, referenceId);
    }

    function submitValuationAndSyncPricing(
        address asset,
        uint256 assetValue,
        uint256 navPerToken,
        uint256 subscriptionPrice,
        uint256 redemptionPrice,
        bytes32 referenceId
    ) external onlyOracle {
        _submitValuation(asset, assetValue, navPerToken, referenceId);
        IAssetToken(asset).setPricing(subscriptionPrice, redemptionPrice);
    }

    function anchorDocument(address asset, bytes32 documentType, bytes32 documentHash, bytes32 referenceId)
        external
        onlyOracle
    {
        if (asset == address(0) || documentHash == bytes32(0)) {
            revert InvalidAddress();
        }

        _documentHashes[asset][documentType] = documentHash;
        emit DocumentAnchored(asset, documentType, documentHash, referenceId, block.timestamp);
    }

    function getLatestValuation(address asset) external view returns (AssetValuation memory valuation) {
        return _valuations[asset];
    }

    function getDocumentHash(address asset, bytes32 documentType) external view returns (bytes32 documentHash) {
        return _documentHashes[asset][documentType];
    }

    function _submitValuation(address asset, uint256 assetValue, uint256 navPerToken, bytes32 referenceId) internal {
        if (asset == address(0)) {
            revert InvalidAddress();
        }
        if (assetValue == 0 || navPerToken == 0) {
            revert InvalidAmount();
        }

        _valuations[asset] = AssetValuation({
            assetValue: assetValue,
            navPerToken: navPerToken,
            updatedAt: uint64(block.timestamp),
            referenceId: referenceId
        });

        emit ValuationSubmitted(asset, assetValue, navPerToken, referenceId, block.timestamp);
    }

    function isValuationFresh(address asset) public view returns (bool) {
        uint64 updatedAt = _valuations[asset].updatedAt;
        if (updatedAt == 0) return false;
        return block.timestamp - updatedAt <= MAX_VALUATION_AGE;
    }
}
