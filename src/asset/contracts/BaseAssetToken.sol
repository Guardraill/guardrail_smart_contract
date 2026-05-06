// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IAccessControl} from "../../admin/interfaces/IAccessControl.sol";
import {Roles} from "../../admin/libraries/Roles.sol";
import {ICompliance} from "../../compliance/interfaces/ICompliance.sol";
import {ITreasury} from "../../treasury/interfaces/ITreasury.sol";
import {IAssetToken} from "../interfaces/IAssetToken.sol";

contract BaseAssetToken is ERC20, ReentrancyGuard, IAssetToken {
    using SafeCast for int256;
    using SafeCast for uint256;

    uint256 private constant MAGNITUDE = 2 ** 128;

    uint256 public immutable proposalId;
    bytes32 public immutable assetTypeId;
    uint256 public immutable maxSupply;

    IAccessControl public immutable accessControl;

    ICompliance public complianceRegistry;
    address public treasury;

    AssetState public assetState;
    bool public controllable;
    bool public selfServicePurchaseEnabled;

    uint256 public pricePerToken;
    uint256 public redemptionPricePerToken;
    bytes32 public metadataHash;
    uint256 public holderCount;
    uint256 public totalPendingRedemptions;

    mapping(address account => uint256 amount) private _pendingRedemptions;
    mapping(address account => int256 correction) private _magnifiedYieldCorrections;
    mapping(address account => uint256 withdrawnAmount) private _withdrawnYield;

    uint256 public magnifiedYieldPerShare;

    modifier onlyAdmin() {
        _requireRole(Roles.ADMIN_ROLE);
        _;
    }

    modifier onlyIssuer() {
        _requireRoleOrAdmin(Roles.ISSUER_ROLE);
        _;
    }

    modifier onlyOperator() {
        _requireRoleOrAdmin(Roles.OPERATOR_ROLE);
        _;
    }

    modifier onlyPricingManager() {
        require(
            accessControl.hasRole(Roles.ORACLE_ROLE, msg.sender) || accessControl.hasRole(Roles.ADMIN_ROLE, msg.sender),
            Unauthorized()
        );
        _;
    }

    modifier onlyTreasuryManager() {
        require(
            msg.sender == treasury || accessControl.hasRole(Roles.TREASURY_ROLE, msg.sender)
                || accessControl.hasRole(Roles.ADMIN_ROLE, msg.sender),
            Unauthorized()
        );
        _;
    }

    modifier whenSubscriptionsOpen() {
        if (assetState != AssetState.Active) {
            revert InvalidState();
        }
        _;
    }

    modifier whenRedeemable() {
        if (assetState != AssetState.Active && assetState != AssetState.Matured) {
            revert InvalidState();
        }
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        uint256 proposalId_,
        bytes32 assetTypeId_,
        address accessControlAddress_,
        address complianceRegistryAddress_,
        address treasuryAddress_,
        uint256 subscriptionPrice_,
        uint256 redemptionPrice_,
        bool selfServicePurchaseEnabled_,
        bytes32 metadataHash_
    ) ERC20(name_, symbol_) {
        if (
            accessControlAddress_ == address(0) || complianceRegistryAddress_ == address(0)
                || treasuryAddress_ == address(0)
        ) {
            revert InvalidAddress();
        }
        if (maxSupply_ == 0 || subscriptionPrice_ == 0 || redemptionPrice_ == 0) {
            revert InvalidAmount();
        }

        proposalId = proposalId_;
        assetTypeId = assetTypeId_;
        maxSupply = maxSupply_;
        accessControl = IAccessControl(accessControlAddress_);
        complianceRegistry = ICompliance(complianceRegistryAddress_);
        treasury = treasuryAddress_;
        assetState = AssetState.Active;
        controllable = true;
        selfServicePurchaseEnabled = selfServicePurchaseEnabled_;
        pricePerToken = subscriptionPrice_;
        redemptionPricePerToken = redemptionPrice_;
        metadataHash = metadataHash_;
    }

    function issue(address to, uint256 amount, bytes memory data)
        external
        onlyIssuer
        whenSubscriptionsOpen
        returns (bool success)
    {
        _validateMint(to, amount);
        _mint(to, amount);
        emit Issued(msg.sender, to, amount, data, block.timestamp);
        return true;
    }

    function burn(address from, uint256 amount) external onlyIssuer returns (bool success) {
        if (amount == 0) revert InvalidAmount();
        if (from == address(0)) revert InvalidAddress();
        // Tokens can only be burned if a redemption was already requested
        // This ensures the USDC reservation exists in Treasury before destruction
        if (_pendingRedemptions[from] < amount) revert BurnRequiresPendingRedemption();
        _burn(from, amount);
        return true;
    }

    function distributeYield(uint256 amount, bytes memory)
        external
        onlyTreasuryManager
        whenRedeemable
        returns (bool success)
    {
        if (amount == 0) {
            revert InvalidAmount();
        }
        if (totalSupply() == 0) {
            revert InvalidState();
        }

        magnifiedYieldPerShare += (amount * MAGNITUDE) / totalSupply();

        emit YieldDistributed(msg.sender, amount, holderCount, block.timestamp);
        return true;
    }

    function claimYield(address recipient) external nonReentrant returns (uint256 claimedAmount) {
        if (recipient == address(0)) {
            revert InvalidAddress();
        }

        claimedAmount = claimableYieldOf(msg.sender);
        if (claimedAmount == 0) {
            revert NoClaimableYield();
        }

        _withdrawnYield[msg.sender] += claimedAmount;
        _treasuryContract().payoutYield(recipient, claimedAmount);

        emit YieldClaimed(msg.sender, recipient, claimedAmount, block.timestamp);
    }

    // This function creates a redemption request that backend/off-chain ops can review and settle.
    function redeem(uint256 amount, bytes memory data)
        external
        whenRedeemable
        nonReentrant
        returns (uint256 valueReturned)
    {
        if (amount == 0) revert InvalidAmount();
        if (lockedBalanceOf(msg.sender) + amount > balanceOf(msg.sender)) {
            revert InsufficientUnlockedBalance();
        }

        (bool isValid, bytes32 reason) = complianceRegistry.canRedeem(address(this), msg.sender, amount);
        if (!isValid) revert ComplianceFailure(reason);

        valueReturned = previewRedemption(amount);

        _pendingRedemptions[msg.sender] += amount;
        totalPendingRedemptions += amount;

        _treasuryContract().reserveRedemption(msg.sender, valueReturned);

        emit RedemptionRequested(msg.sender, amount, data, block.timestamp);
    }

    function processRedemption(address investor, uint256 amount, address recipient, bytes memory data)
        external
        onlyTreasuryManager
        whenRedeemable
        nonReentrant
        returns (uint256 valueReturned)
    {
        if (recipient == address(0)) {
            revert InvalidAddress();
        }
        if (amount == 0) {
            revert InvalidAmount();
        }
        if (_pendingRedemptions[investor] < amount) {
            revert PendingRedemptionTooLarge();
        }

        _pendingRedemptions[investor] -= amount;
        totalPendingRedemptions -= amount;

        valueReturned = previewRedemption(amount);

        _burn(investor, amount);
        _treasuryContract().payoutRedemption(recipient, valueReturned);

        emit Redeemed(msg.sender, investor, amount, valueReturned, data, block.timestamp);
    }

    function cancelRedemption(uint256 amount) external nonReentrant returns (bool cancelled) {
        if (amount == 0) revert InvalidAmount();
        if (_pendingRedemptions[msg.sender] < amount) {
            revert PendingRedemptionTooLarge();
        }

        uint256 valueReturned = previewRedemption(amount);

        _pendingRedemptions[msg.sender] -= amount;
        totalPendingRedemptions -= amount;

        _treasuryContract().releaseRedemptionReservation(msg.sender, valueReturned);

        emit RedemptionCancelled(msg.sender, amount, block.timestamp);
        return true;
    }

    function previewPurchase(uint256 tokenAmount) public view returns (uint256 cost) {
        return (tokenAmount * pricePerToken) / 1e18;
    }

    function previewRedemption(uint256 tokenAmount) public view returns (uint256 valueReturned) {
        return (tokenAmount * redemptionPricePerToken) / 1e18;
    }

    function claimableYieldOf(address account) public view returns (uint256 amount) {
        uint256 accumulated = accumulativeYieldOf(account);
        uint256 withdrawn = _withdrawnYield[account];
        if (accumulated <= withdrawn) {
            return 0;
        }
        return accumulated - withdrawn;
    }

    function pendingRedemptionOf(address account) external view returns (uint256 amount) {
        return _pendingRedemptions[account];
    }

    function lockedBalanceOf(address account) public view returns (uint256 amount) {
        return _pendingRedemptions[account];
    }

    function canTransfer(address to, uint256 amount, bytes memory)
        external
        view
        returns (bytes1 statusCode, bytes32 reasonCode)
    {
        if (assetState != AssetState.Active) {
            return (0x54, "ASSET_NOT_ACTIVE");
        }
        if (_unlockedBalanceOf(msg.sender) < amount) {
            return (0x57, "BALANCE_LOCKED");
        }
        if (address(complianceRegistry) != address(0)) {
            (bool isValid, bytes32 reason) =
                complianceRegistry.canTransfer(address(this), msg.sender, to, amount, balanceOf(to));
            if (!isValid) {
                return (0x50, reason);
            }
        }

        return (0x51, "SUCCESS");
    }

    function getAssetState() external view returns (AssetState state) {
        return assetState;
    }

    function getAssetTypeId() external view returns (bytes32) {
        return assetTypeId;
    }

    function getProposalId() external view returns (uint256) {
        return proposalId;
    }

    function isControllable() external view returns (bool) {
        return controllable;
    }

    function paymentToken() public view returns (address) {
        return _treasuryContract().paymentToken();
    }

    function accumulativeYieldOf(address account) public view returns (uint256 amount) {
        int256 corrected =
            (magnifiedYieldPerShare * balanceOf(account)).toInt256() + _magnifiedYieldCorrections[account];
        if (corrected <= 0) {
            return 0;
        }
        return corrected.toUint256() / MAGNITUDE;
    }

    function setAssetState(AssetState newState) external {
        if (newState == AssetState.Paused) {
            require(
                accessControl.hasRole(Roles.PAUSER_ROLE, msg.sender)
                    || accessControl.hasRole(Roles.ADMIN_ROLE, msg.sender),
                Unauthorized()
            );
        } else {
            _requireRole(Roles.ADMIN_ROLE);
        }

        AssetState oldState = assetState;
        assetState = newState;
        emit AssetStateChanged(oldState, newState, block.timestamp);
    }

    function setComplianceRegistry(address registry) external onlyAdmin {
        if (registry == address(0)) {
            revert InvalidAddress();
        }

        complianceRegistry = ICompliance(registry);
        emit ComplianceRegistryUpdated(registry, block.timestamp);
    }

    function setTreasury(address treasuryAddress) external onlyAdmin {
        if (treasuryAddress == address(0)) {
            revert InvalidAddress();
        }

        treasury = treasuryAddress;
        emit TreasuryUpdated(treasuryAddress, block.timestamp);
    }

    function setPricePerToken(uint256 newPrice) external onlyPricingManager {
        _setPricing(newPrice, redemptionPricePerToken);
    }

    function setRedemptionPricePerToken(uint256 newPrice) external onlyPricingManager {
        _setPricing(pricePerToken, newPrice);
    }

    function setPricing(uint256 newSubscriptionPrice, uint256 newRedemptionPrice) external onlyPricingManager {
        _setPricing(newSubscriptionPrice, newRedemptionPrice);
    }

    function setSelfServicePurchaseEnabled(bool enabled) external onlyAdmin {
        selfServicePurchaseEnabled = enabled;
        emit SelfServicePurchaseUpdated(enabled, block.timestamp);
    }

    function setMetadataHash(bytes32 newMetadataHash) external onlyAdmin {
        metadataHash = newMetadataHash;
        emit MetadataHashUpdated(newMetadataHash, block.timestamp);
    }

    function disableController() external onlyAdmin {
        controllable = false;
    }

    function controllerTransfer(address from, address to, uint256 amount, bytes memory data, bytes memory operatorData)
        external
        onlyOperator
        nonReentrant
    {
        if (!controllable) {
            revert InvalidState();
        }

        _transfer(from, to, amount);
        emit ControllerTransfer(msg.sender, from, to, amount, data, operatorData);
    }

    function purchase(uint256 tokenAmount) external whenSubscriptionsOpen nonReentrant {
        if (!selfServicePurchaseEnabled) {
            revert SelfServicePurchaseDisabled();
        }
        if (tokenAmount == 0) {
            revert InvalidAmount();
        }

        uint256 cost = previewPurchase(tokenAmount);

        _mint(msg.sender, tokenAmount);

        _treasuryContract().collectPurchaseFunds(msg.sender, cost);

        emit TokensPurchased(msg.sender, tokenAmount, cost, block.timestamp);
    }

    function _update(address from, address to, uint256 value) internal override {
        uint256 fromBalanceBefore = from == address(0) ? 0 : balanceOf(from);
        uint256 toBalanceBefore = to == address(0) ? 0 : balanceOf(to);

        _enforceTransferRules(from, to, value);
        _updateYieldCorrections(from, to, value);

        super._update(from, to, value);

        if (from != address(0) && fromBalanceBefore == value) {
            holderCount--;
        }
        if (to != address(0) && toBalanceBefore == 0 && value > 0) {
            holderCount++;
        }
    }

    function _enforceTransferRules(address from, address to, uint256 value) internal view {
        if (value == 0) {
            return;
        }

        if (from == address(0)) {
            _validateMint(to, value);
            return;
        }

        if (_unlockedBalanceOf(from) < value) {
            revert InsufficientUnlockedBalance();
        }

        if (to == address(0)) {
            return;
        }

        if (assetState != AssetState.Active) {
            revert InvalidState();
        }

        if (address(complianceRegistry) != address(0)) {
            (bool isValid, bytes32 reason) =
                complianceRegistry.canTransfer(address(this), from, to, value, balanceOf(to));
            if (!isValid) {
                revert ComplianceFailure(reason);
            }
        }
    }

    function _updateYieldCorrections(address from, address to, uint256 value) internal {
        int256 correction = (magnifiedYieldPerShare * value).toInt256();

        if (from == address(0)) {
            _magnifiedYieldCorrections[to] -= correction;
        } else if (to == address(0)) {
            _magnifiedYieldCorrections[from] += correction;
        } else {
            _magnifiedYieldCorrections[from] += correction;
            _magnifiedYieldCorrections[to] -= correction;
        }
    }

    function _unlockedBalanceOf(address account) internal view returns (uint256) {
        return balanceOf(account) - _pendingRedemptions[account];
    }

    function _validateMint(address to, uint256 amount) internal view {
        if (to == address(0)) {
            revert InvalidAddress();
        }
        if (amount == 0) {
            revert InvalidAmount();
        }
        if (totalSupply() + amount > maxSupply) {
            revert MaxSupplyExceeded();
        }

        if (address(complianceRegistry) != address(0)) {
            (bool isValid, bytes32 reason) =
                complianceRegistry.canSubscribe(address(this), to, amount, balanceOf(to) + amount);
            if (!isValid) {
                revert ComplianceFailure(reason);
            }
        }
    }

    function _setPricing(uint256 newSubscriptionPrice, uint256 newRedemptionPrice) internal {
        if (newSubscriptionPrice == 0 || newRedemptionPrice == 0) {
            revert InvalidAmount();
        }

        pricePerToken = newSubscriptionPrice;
        redemptionPricePerToken = newRedemptionPrice;

        emit PricingUpdated(newSubscriptionPrice, newRedemptionPrice, block.timestamp);
    }

    function _requireRole(bytes32 role) internal view {
        if (!accessControl.hasRole(role, msg.sender)) {
            revert Unauthorized();
        }
    }

    function _requireRoleOrAdmin(bytes32 role) internal view {
        if (!accessControl.hasRole(role, msg.sender) && !accessControl.hasRole(Roles.ADMIN_ROLE, msg.sender)) {
            revert Unauthorized();
        }
    }

    function _treasuryContract() internal view returns (ITreasury) {
        return ITreasury(treasury);
    }
}
