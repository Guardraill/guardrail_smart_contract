// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAccessControl} from "../interfaces/IAccessControl.sol";
import {IDiamondCut} from "../../compliance/interfaces/IDiamondCut.sol";
import {IAssetFactory} from "../../asset/interfaces/IAssetFactory.sol";
import {IAssetToken} from "../../asset/interfaces/IAssetToken.sol";
import {ICompliance} from "../../compliance/interfaces/ICompliance.sol";
import {IOracleDataBridge} from "../../oracle/interfaces/IOracleDataBridge.sol";
import {ITreasury} from "../../treasury/interfaces/ITreasury.sol";


/// @notice A library that converts every governance call in
///         the platform into ABI-encoded bytes ready to be
///         submitted as a proposal to MultiSigAdmin.


library ProposalEncoder {
    function encodeGrantRole(bytes32 role, address account) internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(IAccessControl.grantRole.selector, role, account);
    }

    function encodeRevokeRole(bytes32 role, address account) internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(IAccessControl.revokeRole.selector, role, account);
    }

    function encodeRenounceRole(bytes32 role, address account) internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(IAccessControl.renounceRole.selector, role, account);
    }

    function encodeDiamondCut(IDiamondCut.FacetCut[] memory cuts, address init, bytes memory initData)
        internal
        pure
        returns (bytes memory data)
    {
        return abi.encodeWithSelector(IDiamondCut.diamondCut.selector, cuts, init, initData);
    }

    function encodeCreateAsset(
        uint256 proposalId,
        bytes32 assetTypeId,
        string memory name,
        string memory symbol,
        uint256 maxSupply,
        bytes memory configData
    ) internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(
            IAssetFactory.createAsset.selector, proposalId, assetTypeId, name, symbol, maxSupply, configData
        );
    }

    function encodeRegisterAssetType(bytes32 assetTypeId, string memory assetTypeName, address implementation)
        internal
        pure
        returns (bytes memory data)
    {
        return abi.encodeWithSelector(
            IAssetFactory.registerAssetType.selector, assetTypeId, assetTypeName, implementation
        );
    }

    function encodeUnregisterAssetType(bytes32 assetTypeId) internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(IAssetFactory.unregisterAssetType.selector, assetTypeId);
    }

    function encodePauseFactory() internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(IAssetFactory.pauseFactory.selector);
    }

    function encodeUnpauseFactory() internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(IAssetFactory.unpauseFactory.selector);
    }

    function encodeSetAssetState(uint8 newState) internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(IAssetToken.setAssetState.selector, newState);
    }

    function encodeSetComplianceRegistry(address registry) internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(IAssetToken.setComplianceRegistry.selector, registry);
    }

    function encodeSetTreasury(address treasuryAddress) internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(IAssetToken.setTreasury.selector, treasuryAddress);
    }

    function encodeSetPricePerToken(uint256 newPrice) internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(IAssetToken.setPricePerToken.selector, newPrice);
    }

    function encodeSetRedemptionPricePerToken(uint256 newPrice) internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(IAssetToken.setRedemptionPricePerToken.selector, newPrice);
    }

    function encodeSetPricing(uint256 newSubscriptionPrice, uint256 newRedemptionPrice)
        internal
        pure
        returns (bytes memory data)
    {
        return abi.encodeWithSelector(IAssetToken.setPricing.selector, newSubscriptionPrice, newRedemptionPrice);
    }

    function encodeSetSelfServicePurchaseEnabled(bool enabled) internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(IAssetToken.setSelfServicePurchaseEnabled.selector, enabled);
    }

    function encodeSetMetadataHash(bytes32 newMetadataHash) internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(IAssetToken.setMetadataHash.selector, newMetadataHash);
    }

    function encodeDisableController() internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(IAssetToken.disableController.selector);
    }

    function encodeControllerTransfer(
        address from,
        address to,
        uint256 amount,
        bytes memory data,
        bytes memory operatorData
    ) internal pure returns (bytes memory encoded) {
        return abi.encodeWithSelector(IAssetToken.controllerTransfer.selector, from, to, amount, data, operatorData);
    }

    function encodeIssue(address to, uint256 amount, bytes memory data) internal pure returns (bytes memory encoded) {
        return abi.encodeWithSelector(IAssetToken.issue.selector, to, amount, data);
    }

    function encodeBurn(address from, uint256 amount) internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(IAssetToken.burn.selector, from, amount);
    }

    function encodeProcessRedemption(address investor, uint256 amount, address recipient, bytes memory data)
        internal
        pure
        returns (bytes memory encoded)
    {
        return abi.encodeWithSelector(IAssetToken.processRedemption.selector, investor, amount, recipient, data);
    }

    function encodeAddToWhitelist(address investor) internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(ICompliance.addToWhitelist.selector, investor);
    }

    function encodeRemoveFromWhitelist(address investor) internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(ICompliance.removeFromWhitelist.selector, investor);
    }

    function encodeBatchAddToWhitelist(address[] memory investors) internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(ICompliance.batchAddToWhitelist.selector, investors);
    }

    function encodeSetInvestorStatus(address investor, bool investorIsAccredited)
        internal
        pure
        returns (bytes memory data)
    {
        return abi.encodeWithSelector(ICompliance.setInvestorStatus.selector, investor, investorIsAccredited);
    }

    function encodeSetInvestorData(address investor, ICompliance.InvestorData memory data)
        internal
        pure
        returns (bytes memory encoded)
    {
        return abi.encodeWithSelector(ICompliance.setInvestorData.selector, investor, data);
    }

    function encodeBatchSetInvestorData(address[] calldata investors, ICompliance.InvestorData[] calldata data)
        internal
        pure
        returns (bytes memory encoded)
    {
        return abi.encodeWithSelector(ICompliance.batchSetInvestorData.selector, investors, data);
    }

    function encodeSetAssetRules(address asset, ICompliance.AssetRules memory rules)
        internal
        pure
        returns (bytes memory data)
    {
        return abi.encodeWithSelector(ICompliance.setAssetRules.selector, asset, rules);
    }

    function encodeSetJurisdictionRestriction(address asset, bytes32 jurisdiction, bool restricted)
        internal
        pure
        returns (bytes memory data)
    {
        return abi.encodeWithSelector(ICompliance.setJurisdictionRestriction.selector, asset, jurisdiction, restricted);
    }

    function encodeSetTrustedOracle(address oracle, bool trusted) internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(IOracleDataBridge.setTrustedOracle.selector, oracle, trusted);
    }

    function encodeSubmitValuation(address asset, uint256 assetValue, uint256 navPerToken, bytes32 referenceId)
        internal
        pure
        returns (bytes memory data)
    {
        return abi.encodeWithSelector(
            IOracleDataBridge.submitValuation.selector, asset, assetValue, navPerToken, referenceId
        );
    }

    function encodeSubmitValuationAndSyncPricing(
        address asset,
        uint256 assetValue,
        uint256 navPerToken,
        uint256 subscriptionPrice,
        uint256 redemptionPrice,
        bytes32 referenceId
    ) internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(
            IOracleDataBridge.submitValuationAndSyncPricing.selector,
            asset,
            assetValue,
            navPerToken,
            subscriptionPrice,
            redemptionPrice,
            referenceId
        );
    }

    function encodeAnchorDocument(address asset, bytes32 documentType, bytes32 documentHash, bytes32 referenceId)
        internal
        pure
        returns (bytes memory data)
    {
        return abi.encodeWithSelector(
            IOracleDataBridge.anchorDocument.selector, asset, documentType, documentHash, referenceId
        );
    }

    function encodeDepositAssetLiquidity(address asset, uint256 amount) internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(ITreasury.depositAssetLiquidity.selector, asset, amount);
    }

    function encodeReleaseCapital(address asset, uint256 amount, address to, bytes32 referenceId)
        internal
        pure
        returns (bytes memory data)
    {
        return abi.encodeWithSelector(ITreasury.releaseCapital.selector, asset, amount, to, referenceId);
    }

    function encodeDepositYield(address asset, uint256 amount, bytes memory data)
        internal
        pure
        returns (bytes memory encoded)
    {
        return abi.encodeWithSelector(ITreasury.depositYield.selector, asset, amount, data);
    }

    function encodeEmergencyWithdraw(address token, uint256 amount, address to)
        internal
        pure
        returns (bytes memory data)
    {
        return abi.encodeWithSelector(ITreasury.emergencyWithdraw.selector, token, amount, to);
    }

    function encodePauseTreasury() internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(ITreasury.pause.selector);
    }

    function encodeUnpauseTreasury() internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(ITreasury.unpause.selector);
    }

    function encodeAddSigner(address newSigner) internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(bytes4(keccak256("addSigner(address)")), newSigner);
    }

    function encodeRemoveSigner(address signerToRemove) internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(bytes4(keccak256("removeSigner(address)")), signerToRemove);
    }

    function encodeUpdateQuorum(uint256 newQuorum) internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(bytes4(keccak256("updateQuorum(uint256)")), newQuorum);
    }

    function encodeCancelProposal(uint256 proposalId) internal pure returns (bytes memory data) {
        return abi.encodeWithSelector(bytes4(keccak256("cancel(uint256)")), proposalId);
    }
}

