// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IAccessControl} from "../../admin/interfaces/IAccessControl.sol";
import {Roles} from "../../admin/libraries/Roles.sol";
import {IAssetToken} from "../../asset/interfaces/IAssetToken.sol";
import {ITreasury} from "../interfaces/ITreasury.sol";
import {Errors} from "../../admin/libraries/Errors.sol";

contract Treasury is ITreasury, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable paymentToken;
    IAccessControl public immutable accessControl;

    bool public paused;
    uint256 public totalTrackedBalance;
    uint256 public totalReservedYield;
    uint256 public totalReservedRedemptions;

    mapping(address asset => uint256 amount) public assetBalances;
    mapping(address asset => uint256 amount) public reservedYieldBalances;

    mapping(address asset => uint256 amount) public reservedRedemptionBalances;

    mapping(address token => bool registered) public registeredAssetTokens;

    modifier onlyTreasuryManager() {
        if (
            !accessControl.hasRole(Roles.TREASURY_ROLE, msg.sender)
                && !accessControl.hasRole(Roles.ADMIN_ROLE, msg.sender)
        ) {
            revert Unauthorized();
        }
        _;
    }

    modifier onlyPauser() {
        if (
            !accessControl.hasRole(Roles.PAUSER_ROLE, msg.sender)
                && !accessControl.hasRole(Roles.ADMIN_ROLE, msg.sender)
        ) {
            revert Unauthorized();
        }
        _;
    }

    modifier whenNotPaused() {
        require(!paused, Errors.ContractPaused());
        _;
    }

    modifier onlyRegisteredToken() {
        if (!registeredAssetTokens[msg.sender]) revert NotRegisteredAssetToken();
        _;
    }

    constructor(address paymentTokenAddress, address accessControlAddress) {
        if (paymentTokenAddress == address(0) || accessControlAddress == address(0)) {
            revert InvalidAddress();
        }

        paymentToken = paymentTokenAddress;
        accessControl = IAccessControl(accessControlAddress);
    }

    function collectPurchaseFunds(address investor, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        onlyRegisteredToken
    {
        if (investor == address(0)) {
            revert InvalidAddress();
        }
        if (amount == 0) {
            revert InvalidAmount();
        }

        _paymentToken().safeTransferFrom(investor, address(this), amount);

        assetBalances[msg.sender] += amount;
        totalTrackedBalance += amount;

        emit PurchaseFundsCollected(msg.sender, investor, amount, block.timestamp);
    }

    function depositAssetLiquidity(address asset, uint256 amount)
        external
        onlyTreasuryManager
        nonReentrant
        whenNotPaused
    {
        if (asset == address(0)) {
            revert InvalidAddress();
        }
        if (amount == 0) {
            revert InvalidAmount();
        }

        _paymentToken().safeTransferFrom(msg.sender, address(this), amount);

        assetBalances[asset] += amount;
        totalTrackedBalance += amount;

        emit AssetLiquidityDeposited(asset, amount, msg.sender, block.timestamp);
    }

    function releaseCapital(address asset, uint256 amount, address to, bytes32 referenceId)
        external
        onlyTreasuryManager
        nonReentrant
        whenNotPaused
    {
        if (asset == address(0) || to == address(0)) {
            revert InvalidAddress();
        }
        if (amount == 0) {
            revert InvalidAmount();
        }
        if (getAvailableLiquidity(asset) < amount) {
            revert InsufficientLiquidity();
        }

        assetBalances[asset] -= amount;
        totalTrackedBalance -= amount;
        _paymentToken().safeTransfer(to, amount);

        emit CapitalReleased(asset, amount, to, referenceId, block.timestamp);
    }

    function depositYield(address asset, uint256 amount, bytes calldata data)
        external
        onlyTreasuryManager
        nonReentrant
        whenNotPaused
    {
        if (!registeredAssetTokens[asset]) revert NotRegisteredAssetToken();
        if (asset == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();

        
        assetBalances[asset] += amount;
        reservedYieldBalances[asset] += amount;
        totalTrackedBalance += amount;
        totalReservedYield += amount;

        
        _paymentToken().safeTransferFrom(msg.sender, address(this), amount);

        
        IAssetToken(asset).distributeYield(amount, data);

        emit YieldFunded(asset, amount, msg.sender, block.timestamp);
    }

    function payoutYield(address investor, uint256 amount) external nonReentrant whenNotPaused {
        if (investor == address(0)) {
            revert InvalidAddress();
        }
        if (amount == 0) {
            revert InvalidAmount();
        }
        if (reservedYieldBalances[msg.sender] < amount) {
            revert InsufficientLiquidity();
        }

        reservedYieldBalances[msg.sender] -= amount;
        assetBalances[msg.sender] -= amount;
        totalReservedYield -= amount;
        totalTrackedBalance -= amount;

        _paymentToken().safeTransfer(investor, amount);

        emit YieldClaimPaid(msg.sender, investor, amount, block.timestamp);
    }

    function payoutRedemption(address investor, uint256 amount) external nonReentrant whenNotPaused {
        if (investor == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();

        
        if (reservedRedemptionBalances[msg.sender] < amount) {
            revert InsufficientRedemptionReservation();
        }

        
        reservedRedemptionBalances[msg.sender] -= amount;
        assetBalances[msg.sender] -= amount;
        totalReservedRedemptions -= amount;
        totalTrackedBalance -= amount;

        _paymentToken().safeTransfer(investor, amount);
        emit RedemptionPaid(msg.sender, investor, amount, block.timestamp);
    }

    function emergencyWithdraw(address token, uint256 amount, address to) external onlyTreasuryManager nonReentrant {
        if (!paused) {
            revert EmergencyWithdrawRequiresPause();
        }
        if (to == address(0)) {
            revert InvalidAddress();
        }

        if (token == address(paymentToken)) {
            uint256 excessBalance = IERC20(token).balanceOf(address(this)) - totalTrackedBalance;
            if (amount > excessBalance) {
                revert InsufficientLiquidity();
            }
        }

        IERC20(token).safeTransfer(to, amount);

        emit EmergencyWithdraw(token, amount, to, block.timestamp);
    }

    function getBalance(address asset) external view returns (uint256) {
        return assetBalances[asset];
    }

    function getReservedYield(address asset) external view returns (uint256) {
        return reservedYieldBalances[asset];
    }

    function getAvailableLiquidity(address asset) public view returns (uint256) {
        uint256 total = assetBalances[asset];
        uint256 reserved = reservedYieldBalances[asset] + reservedRedemptionBalances[asset];
        if (reserved >= total) return 0;
        return total - reserved;
    }

    function pause() external onlyPauser {
        paused = true;
        emit TreasuryPaused(msg.sender, block.timestamp);
    }

    function unpause() external onlyPauser {
        paused = false;
        emit TreasuryUnpaused(msg.sender, block.timestamp);
    }

    function _paymentToken() internal view returns (IERC20) {
        return IERC20(paymentToken);
    }

    function reserveRedemption(address investor, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        onlyRegisteredToken
    {
        if (investor == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();

        
        if (getAvailableLiquidity(msg.sender) < amount) {
            revert InsufficientLiquidity();
        }

        reservedRedemptionBalances[msg.sender] += amount;
        totalReservedRedemptions += amount;

        emit RedemptionReserved(msg.sender, investor, amount, block.timestamp);
    }

    function releaseRedemptionReservation(address investor, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        onlyRegisteredToken
    {
        if (investor == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();

        if (reservedRedemptionBalances[msg.sender] < amount) {
            revert InsufficientRedemptionReservation();
        }

        reservedRedemptionBalances[msg.sender] -= amount;
        totalReservedRedemptions -= amount;

        emit RedemptionReservationReleased(msg.sender, investor, amount, block.timestamp);
    }

    function getReservedRedemptions(address asset) external view returns (uint256) {
        return reservedRedemptionBalances[asset];
    }

    function registerAssetToken(address token) external onlyTreasuryManager {
        if (token == address(0)) revert InvalidAddress();
        registeredAssetTokens[token] = true;
        emit AssetTokenRegistered(token, block.timestamp);
    }
}
