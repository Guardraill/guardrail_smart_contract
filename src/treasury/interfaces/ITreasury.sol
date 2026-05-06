// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ITreasury {
    event PurchaseFundsCollected(address indexed asset, address indexed investor, uint256 amount, uint256 timestamp);
    event AssetLiquidityDeposited(address indexed asset, uint256 amount, address indexed depositor, uint256 timestamp);
    event CapitalReleased(
        address indexed asset, uint256 amount, address indexed to, bytes32 indexed referenceId, uint256 timestamp
    );
    event YieldFunded(address indexed asset, uint256 amount, address indexed depositor, uint256 timestamp);
    event YieldClaimPaid(address indexed asset, address indexed investor, uint256 amount, uint256 timestamp);
    event RedemptionPaid(address indexed asset, address indexed investor, uint256 amount, uint256 timestamp);
    event EmergencyWithdraw(address indexed token, uint256 amount, address indexed to, uint256 timestamp);
    event RedemptionReserved(address indexed asset, address indexed investor, uint256 amount, uint256 timestamp);
    event RedemptionReservationReleased(
        address indexed asset, address indexed investor, uint256 amount, uint256 timestamp
    );
    event TreasuryPaused(address indexed by, uint256 timestamp);
    event TreasuryUnpaused(address indexed by, uint256 timestamp);

    event AssetTokenRegistered(address indexed token, uint256 timestamp);

    function collectPurchaseFunds(address investor, uint256 amount) external;
    function depositAssetLiquidity(address asset, uint256 amount) external;
    function releaseCapital(address asset, uint256 amount, address to, bytes32 referenceId) external;
    function depositYield(address asset, uint256 amount, bytes calldata data) external;
    function payoutYield(address investor, uint256 amount) external;
    function payoutRedemption(address investor, uint256 amount) external;
    function emergencyWithdraw(address token, uint256 amount, address to) external;
    function getBalance(address asset) external view returns (uint256);
    function getReservedYield(address asset) external view returns (uint256);
    function getAvailableLiquidity(address asset) external view returns (uint256);
    function paymentToken() external view returns (address);
    function reserveRedemption(address investor, uint256 amount) external;
    function releaseRedemptionReservation(address investor, uint256 amount) external;
    function getReservedRedemptions(address asset) external view returns (uint256);

    function pause() external;
    function unpause() external;

    
    function registerAssetToken(address token) external;

    error Unauthorized();
    error InvalidAddress();
    error InvalidAmount();
    error InsufficientRedemptionReservation();
    error InsufficientLiquidity();
    error EmergencyWithdrawRequiresPause();
    error NotRegisteredAssetToken();
}
