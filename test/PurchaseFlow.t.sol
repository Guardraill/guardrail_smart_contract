// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {AccessControl} from "../src/admin/contracts/AccessControl.sol";
import {Roles} from "../src/admin/libraries/Roles.sol";
import {AssetFactory} from "../src/asset/contracts/AssetFactory.sol";
import {BaseAssetToken} from "../src/asset/contracts/BaseAssetToken.sol";
import {IAssetToken} from "../src/asset/interfaces/IAssetToken.sol";
import {ComplianceDiamond} from "../src/compliance/diamond/ComplianceDiamond.sol";
import {DiamondCutFacet} from "../src/compliance/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../src/compliance/facets/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "../src/compliance/facets/OwnershipFacet.sol";
import {ComplianceWhitelistFacet} from "../src/compliance/facets/ComplianceWhitelistFacet.sol";
import {ComplianceRulesFacet} from "../src/compliance/facets/ComplianceRulesFacet.sol";
import {ComplianceCheckFacet} from "../src/compliance/facets/ComplianceCheckFacet.sol";
import {ComplianceInit} from "../src/compliance/diamond/ComplianceInit.sol";
import {IDiamondCut} from "../src/compliance/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../src/compliance/interfaces/IDiamondLoupe.sol";
import {LibComplianceStorage} from "../src/compliance/libraries/LibComplianceStorage.sol";
import {ICompliance} from "../src/compliance/interfaces/ICompliance.sol";
import {OracleDataBridge} from "../src/oracle/contracts/OracleDataBridge.sol";
import {Treasury} from "../src/treasury/contracts/Treasury.sol";
import {ITreasury} from "../src/treasury/interfaces/ITreasury.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";

contract PurchaseFlowTest is Test {
    AccessControl public accessControl;
    MockUSDC public usdc;
    address public complianceDiamond;
    Treasury public treasury;
    OracleDataBridge public oracle;
    AssetFactory public factory;
    BaseAssetToken public assetToken;

    address public admin = address(1);
    address public treasuryManager = address(2);
    address public complianceOfficer = address(3);
    address public oracleSigner = address(4);
    address public user = address(5);
    address public user2 = address(6);
    address public capitalDestination = address(7);

    bytes32 public realEstateType = keccak256("REAL_ESTATE");
    bytes32 public jurisdictionUs = bytes32("US");
    bytes32 public jurisdictionGb = bytes32("GB");

    function setUp() public {
        vm.startPrank(admin);

        accessControl = new AccessControl(admin, admin);
        usdc = new MockUSDC();
        complianceDiamond = _deployComplianceDiamond();
        treasury = new Treasury(address(usdc), address(accessControl));
        oracle = new OracleDataBridge(address(accessControl));
        factory = new AssetFactory(address(accessControl), complianceDiamond, address(treasury));

        accessControl.grantRole(Roles.ISSUER_ROLE, admin);
        accessControl.grantRole(Roles.COMPLIANCE_ROLE, complianceOfficer);
        accessControl.grantRole(Roles.TREASURY_ROLE, treasuryManager);
        accessControl.grantRole(Roles.ORACLE_ROLE, oracleSigner);
        accessControl.grantRole(Roles.ORACLE_ROLE, address(oracle));
        accessControl.grantRole(Roles.PAUSER_ROLE, admin);
        accessControl.grantRole(Roles.TREASURY_ROLE, address(factory));

        factory.registerAssetType(realEstateType, "Real Estate", address(0));

        address tokenAddress = factory.createAsset(
            1,
            realEstateType,
            "Property Token 1",
            "PROP1",
            1_000_000 * 1e18,
            abi.encode(
                AssetFactory.AssetCreationConfig({
                    subscriptionPrice: 1e6,
                    redemptionPrice: 1e6,
                    selfServicePurchaseEnabled: true,
                    metadataHash: keccak256("property-1")
                })
            )
        );

        assetToken = BaseAssetToken(tokenAddress);

        vm.stopPrank();

        vm.prank(complianceOfficer);
        ComplianceRulesFacet(complianceDiamond)
            .setAssetRules(
                tokenAddress,
                LibComplianceStorage.AssetRules({
                transfersEnabled: true,
                subscriptionsEnabled: true,
                redemptionsEnabled: true,
                requiresAccreditation: false,
                minInvestment: 1e18,
                maxInvestorBalance: 500_000 * 1e18
            })
            );
    }

   

    function testPurchaseRequiresWhitelistedInvestor() public {
        vm.startPrank(user);
        usdc.faucet();
        usdc.approve(address(treasury), 100 * 1e6);

        
        vm.expectRevert(
            abi.encodeWithSelector(IAssetToken.ComplianceFailure.selector, keccak256("INVESTOR_NOT_ELIGIBLE"))
        );
        assetToken.purchase(100 * 1e18);
        vm.stopPrank();

        _setInvestor(user, true, false, jurisdictionUs, "user-1");

        vm.startPrank(user);
        assetToken.purchase(100 * 1e18);
        vm.stopPrank();

        assertEq(assetToken.balanceOf(user), 100 * 1e18);
        assertEq(usdc.balanceOf(address(treasury)), 100 * 1e6);
    }

    function testDirectTransfersRespectCompliance() public {
        _setInvestor(user, true, false, jurisdictionUs, "user-1");

        vm.startPrank(user);
        usdc.faucet();
        usdc.approve(address(treasury), 100 * 1e6);
        assetToken.purchase(100 * 1e18);

        vm.expectRevert(
            abi.encodeWithSelector(IAssetToken.ComplianceFailure.selector, keccak256("RECIPIENT_NOT_ELIGIBLE"))
        );
        assetToken.transfer(user2, 10 * 1e18);
        vm.stopPrank();

        _setInvestor(user2, true, false, jurisdictionGb, "user-2");

        vm.prank(user);
        assertTrue(assetToken.transfer(user2, 10 * 1e18));

        assertEq(assetToken.balanceOf(user), 90 * 1e18);
        assertEq(assetToken.balanceOf(user2), 10 * 1e18);
    }

    function testYieldDistributionAndClaim() public {
        _setInvestor(user, true, false, jurisdictionUs, "user-1");
        _setInvestor(user2, true, false, jurisdictionGb, "user-2");

        _purchase(user, 100 * 1e18);
        _purchase(user2, 300 * 1e18);

        usdc.mint(treasuryManager, 400 * 1e6);
        vm.startPrank(treasuryManager);
        usdc.approve(address(treasury), 400 * 1e6);
        treasury.depositYield(address(assetToken), 400 * 1e6, "");
        vm.stopPrank();

        uint256 userBalanceBefore = usdc.balanceOf(user);
        uint256 user2BalanceBefore = usdc.balanceOf(user2);

        vm.prank(user);
        assetToken.claimYield(user);

        vm.prank(user2);
        assetToken.claimYield(user2);

        assertApproxEqAbs(usdc.balanceOf(user), userBalanceBefore + 100 * 1e6, 1);
        assertApproxEqAbs(usdc.balanceOf(user2), user2BalanceBefore + 300 * 1e6, 1);
        assertEq(assetToken.claimableYieldOf(user), 0);
        assertEq(assetToken.claimableYieldOf(user2), 0);
    }

    function testRedemptionRequestLocksTransfersAndSettlementPaysCash() public {
        _setInvestor(user, true, false, jurisdictionUs, "user-1");
        _purchase(user, 200 * 1e18);

        vm.prank(user);
        uint256 redemptionValue = assetToken.redeem(50 * 1e18, "request");
        assertEq(redemptionValue, 50 * 1e6);

        vm.prank(user);
        vm.expectRevert(IAssetToken.InsufficientUnlockedBalance.selector);
        assetToken.transfer(user2, 200 * 1e18);

        uint256 userUsdcBefore = usdc.balanceOf(user);

        vm.prank(treasuryManager);
        assetToken.processRedemption(user, 50 * 1e18, user, "settled");

        assertEq(assetToken.balanceOf(user), 150 * 1e18);
        assertEq(assetToken.lockedBalanceOf(user), 0);
        assertEq(usdc.balanceOf(user), userUsdcBefore + 50 * 1e6);
    }

    function testCapitalReleaseProtectsYieldReserves() public {
        _setInvestor(user, true, false, jurisdictionUs, "user-1");
        _purchase(user, 100 * 1e18);

        usdc.mint(treasuryManager, 10 * 1e6);
        vm.startPrank(treasuryManager);
        usdc.approve(address(treasury), 10 * 1e6);
        treasury.depositYield(address(assetToken), 10 * 1e6, "");

        assertEq(treasury.getBalance(address(assetToken)), 110 * 1e6);
        assertEq(treasury.getReservedYield(address(assetToken)), 10 * 1e6);
        assertEq(treasury.getAvailableLiquidity(address(assetToken)), 100 * 1e6);

        vm.expectRevert(ITreasury.InsufficientLiquidity.selector);
        treasury.releaseCapital(address(assetToken), 101 * 1e6, capitalDestination, keccak256("too-much"));

        treasury.releaseCapital(address(assetToken), 100 * 1e6, capitalDestination, keccak256("draw-1"));
        vm.stopPrank();

        assertEq(usdc.balanceOf(capitalDestination), 100 * 1e6);
        assertEq(treasury.getBalance(address(assetToken)), 10 * 1e6);
        assertEq(treasury.getReservedYield(address(assetToken)), 10 * 1e6);
    }

    function testJurisdictionRestrictionBlocksPurchase() public {
        _setInvestor(user, true, false, jurisdictionUs, "user-1");

        vm.prank(complianceOfficer);
        ComplianceRulesFacet(complianceDiamond).setJurisdictionRestriction(address(assetToken), jurisdictionUs, true);

        vm.startPrank(user);
        usdc.faucet();
        usdc.approve(address(treasury), 100 * 1e6);
        vm.expectRevert(
            abi.encodeWithSelector(IAssetToken.ComplianceFailure.selector, keccak256("JURISDICTION_RESTRICTED"))
        );
        assetToken.purchase(100 * 1e18);
        vm.stopPrank();
    }

    function testPausedAssetBlocksPurchaseUntilResumed() public {
        _setInvestor(user, true, false, jurisdictionUs, "user-1");

        vm.prank(admin);
        assetToken.setAssetState(IAssetToken.AssetState.Paused);

        vm.startPrank(user);
        usdc.faucet();
        usdc.approve(address(treasury), 100 * 1e6);
        vm.expectRevert(IAssetToken.InvalidState.selector);
        assetToken.purchase(100 * 1e18);
        vm.stopPrank();

        vm.prank(admin);
        assetToken.setAssetState(IAssetToken.AssetState.Active);

        _purchase(user, 100 * 1e18);
        assertEq(assetToken.balanceOf(user), 100 * 1e18);
    }

    function testCancelRedemptionRestoresUnlockedBalance() public {
        _setInvestor(user, true, false, jurisdictionUs, "user-1");
        _setInvestor(user2, true, false, jurisdictionGb, "user-2");
        _purchase(user, 100 * 1e18);

        vm.prank(user);
        assetToken.redeem(40 * 1e18, "request");
        assertEq(assetToken.lockedBalanceOf(user), 40 * 1e18);

        vm.prank(user);
        assetToken.cancelRedemption(40 * 1e18);
        assertEq(assetToken.lockedBalanceOf(user), 0);

        vm.prank(user);
        assertTrue(assetToken.transfer(user2, 100 * 1e18));
        assertEq(assetToken.balanceOf(user2), 100 * 1e18);
    }

    function testEmergencyWithdrawOnlyUsesExcessBalance() public {
        _setInvestor(user, true, false, jurisdictionUs, "user-1");
        _purchase(user, 100 * 1e18);

        usdc.mint(address(treasury), 5 * 1e6);

        vm.prank(admin);
        treasury.pause();

        vm.prank(treasuryManager);
        treasury.emergencyWithdraw(address(usdc), 5 * 1e6, capitalDestination);

        vm.prank(treasuryManager);
        vm.expectRevert(ITreasury.InsufficientLiquidity.selector);
        treasury.emergencyWithdraw(address(usdc), 1, capitalDestination);

        assertEq(usdc.balanceOf(capitalDestination), 5 * 1e6);
    }

    function testAccreditedOnlyRuleBlocksUnaccreditedInvestor() public {
        vm.prank(complianceOfficer);
        ComplianceRulesFacet(complianceDiamond)
            .setAssetRules(
                address(assetToken),
                LibComplianceStorage.AssetRules({
                transfersEnabled: true,
                subscriptionsEnabled: true,
                redemptionsEnabled: true,
                requiresAccreditation: true,
                minInvestment: 1e18,
                maxInvestorBalance: 500_000 * 1e18
            })
            );

        _setInvestor(user, true, false, jurisdictionUs, "user-1");

        vm.startPrank(user);
        usdc.faucet();
        usdc.approve(address(treasury), 100 * 1e6);
        vm.expectRevert(
            abi.encodeWithSelector(IAssetToken.ComplianceFailure.selector, keccak256("ACCREDITATION_REQUIRED"))
        );
        assetToken.purchase(100 * 1e18);
        vm.stopPrank();

        _setInvestor(user, true, true, jurisdictionUs, "user-1");
        _purchase(user, 100 * 1e18);
        assertEq(assetToken.balanceOf(user), 100 * 1e18);
    }

    function testOnlyTreasuryRoleCanFundYield() public {
        _setInvestor(user, true, false, jurisdictionUs, "user-1");
        _purchase(user, 100 * 1e18);

        usdc.mint(user2, 10 * 1e6);
        vm.startPrank(user2);
        usdc.approve(address(treasury), 10 * 1e6);
        vm.expectRevert(ITreasury.Unauthorized.selector);
        treasury.depositYield(address(assetToken), 10 * 1e6, "");
        vm.stopPrank();
    }

    function testRedemptionRevertsWhenNoTreasuryLiquidity() public {
        _setInvestor(user, true, false, jurisdictionUs, "user-1");
        _purchase(user, 100 * 1e18);

        vm.prank(treasuryManager);
        treasury.releaseCapital(address(assetToken), 100 * 1e6, capitalDestination, keccak256("draw-all"));

        assertEq(treasury.getAvailableLiquidity(address(assetToken)), 0);

        vm.prank(user);
        vm.expectRevert(ITreasury.InsufficientLiquidity.selector);
        assetToken.redeem(50 * 1e18, "attempt");

        assertEq(assetToken.lockedBalanceOf(user), 0);
    }

    function testCapitalReleaseCannotExceedReservations() public {
        _setInvestor(user, true, false, jurisdictionUs, "user-1");
        _purchase(user, 100 * 1e18);

        vm.prank(user);
        assetToken.redeem(40 * 1e18, "request");

        assertEq(treasury.getBalance(address(assetToken)), 100 * 1e6);
        assertEq(treasury.getReservedRedemptions(address(assetToken)), 40 * 1e6);
        assertEq(treasury.getAvailableLiquidity(address(assetToken)), 60 * 1e6);

        vm.prank(treasuryManager);
        vm.expectRevert(ITreasury.InsufficientLiquidity.selector);
        treasury.releaseCapital(address(assetToken), 61 * 1e6, capitalDestination, keccak256("too-much"));

        vm.prank(treasuryManager);
        treasury.releaseCapital(address(assetToken), 60 * 1e6, capitalDestination, keccak256("exact-available"));

        assertEq(usdc.balanceOf(capitalDestination), 60 * 1e6);
        assertEq(treasury.getReservedRedemptions(address(assetToken)), 40 * 1e6);
        assertEq(treasury.getAvailableLiquidity(address(assetToken)), 0);
    }

    function testCancelRedemptionReleasesReservation() public {
        _setInvestor(user, true, false, jurisdictionUs, "user-1");
        _purchase(user, 100 * 1e18);

        vm.prank(user);
        assetToken.redeem(40 * 1e18, "request");
        assertEq(treasury.getReservedRedemptions(address(assetToken)), 40 * 1e6);
        assertEq(treasury.getAvailableLiquidity(address(assetToken)), 60 * 1e6);

        vm.prank(user);
        assetToken.cancelRedemption(40 * 1e18);

        assertEq(treasury.getReservedRedemptions(address(assetToken)), 0);
        assertEq(treasury.getAvailableLiquidity(address(assetToken)), 100 * 1e6);
        assertEq(assetToken.lockedBalanceOf(user), 0);

        vm.prank(treasuryManager);
        treasury.releaseCapital(address(assetToken), 100 * 1e6, capitalDestination, keccak256("after-cancel"));
        assertEq(usdc.balanceOf(capitalDestination), 100 * 1e6);
    }

    function testProcessRedemptionDrawsFromReservation() public {
        _setInvestor(user, true, false, jurisdictionUs, "user-1");
        _setInvestor(user2, true, false, jurisdictionGb, "user-2");

        _purchase(user, 200 * 1e18);
        _purchase(user2, 100 * 1e18);

        assertEq(treasury.getBalance(address(assetToken)), 300 * 1e6);

        vm.prank(user);
        assetToken.redeem(50 * 1e18, "request");

        assertEq(treasury.getReservedRedemptions(address(assetToken)), 50 * 1e6);
        assertEq(treasury.getAvailableLiquidity(address(assetToken)), 250 * 1e6);

        uint256 userUsdcBefore = usdc.balanceOf(user);

        vm.prank(treasuryManager);
        assetToken.processRedemption(user, 50 * 1e18, user, "settled");

        assertEq(treasury.getReservedRedemptions(address(assetToken)), 0);
        assertEq(treasury.getBalance(address(assetToken)), 250 * 1e6);
        assertEq(assetToken.balanceOf(user), 150 * 1e18);
        assertEq(usdc.balanceOf(user), userUsdcBefore + 50 * 1e6);
        assertEq(treasury.getAvailableLiquidity(address(assetToken)), 250 * 1e6);
    }

    function testMultipleSimultaneousReservations() public {
        _setInvestor(user, true, false, jurisdictionUs, "user-1");
        _setInvestor(user2, true, false, jurisdictionGb, "user-2");

        _purchase(user, 100 * 1e18);
        _purchase(user2, 100 * 1e18);

        vm.prank(user);
        assetToken.redeem(60 * 1e18, "user-request");

        vm.prank(user2);
        assetToken.redeem(60 * 1e18, "user2-request");

        assertEq(treasury.getReservedRedemptions(address(assetToken)), 120 * 1e6);
        assertEq(treasury.getAvailableLiquidity(address(assetToken)), 80 * 1e6);

        address user3 = address(8);
        _setInvestor(user3, true, false, jurisdictionUs, "user-3");
        _purchase(user3, 100 * 1e18);

        assertEq(treasury.getAvailableLiquidity(address(assetToken)), 180 * 1e6);

        vm.prank(user3);
        assetToken.redeem(90 * 1e18, "user3-request");

        assertEq(treasury.getReservedRedemptions(address(assetToken)), 210 * 1e6);
        assertEq(treasury.getAvailableLiquidity(address(assetToken)), 90 * 1e6);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _purchase(address investor, uint256 tokenAmount) internal {
        uint256 cost = assetToken.previewPurchase(tokenAmount);
        vm.startPrank(investor);
        usdc.faucet();
        usdc.approve(address(treasury), cost);
        assetToken.purchase(tokenAmount);
        vm.stopPrank();
    }

    function _setInvestor(address investor, bool verified, bool accredited, bytes32 jurisdiction, bytes32 externalRef)
        internal
    {
        vm.prank(complianceOfficer);
        ComplianceWhitelistFacet(complianceDiamond)
            .setInvestorData(
                investor,
                LibComplianceStorage.InvestorData({
                isVerified: verified,
                isAccredited: accredited,
                isFrozen: false,
                validUntil: uint64(block.timestamp + 365 days),
                jurisdiction: jurisdiction,
                externalRef: externalRef
            })
            );
    }

    function _deployComplianceDiamond() internal returns (address) {
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        ComplianceDiamond d = new ComplianceDiamond(admin, address(cutFacet));
        DiamondLoupeFacet loupeFacet = new DiamondLoupeFacet();
        OwnershipFacet ownerFacet = new OwnershipFacet();
        ComplianceWhitelistFacet whitelist = new ComplianceWhitelistFacet();
        ComplianceRulesFacet rulesFacet = new ComplianceRulesFacet();
        ComplianceCheckFacet checkFacet = new ComplianceCheckFacet();
        ComplianceInit cInit = new ComplianceInit();

        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](5);

        bytes4[] memory loupeSelectors = new bytes4[](5);
        loupeSelectors[0] = IDiamondLoupe.facets.selector;
        loupeSelectors[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        loupeSelectors[2] = IDiamondLoupe.facetAddresses.selector;
        loupeSelectors[3] = IDiamondLoupe.facetAddress.selector;
        loupeSelectors[4] = bytes4(keccak256("supportsInterface(bytes4)"));
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(loupeFacet), action: IDiamondCut.FacetCutAction.Add, functionSelectors: loupeSelectors
        });

        bytes4[] memory ownerSelectors = new bytes4[](2);
        ownerSelectors[0] = bytes4(keccak256("transferOwnership(address)"));
        ownerSelectors[1] = bytes4(keccak256("owner()"));
        cut[1] = IDiamondCut.FacetCut({
            facetAddress: address(ownerFacet), action: IDiamondCut.FacetCutAction.Add, functionSelectors: ownerSelectors
        });

        // ALL 9 selectors set BEFORE cut[2] is assigned
        bytes4[] memory whitelistSelectors = new bytes4[](9);
        whitelistSelectors[0] = bytes4(keccak256("addToWhitelist(address)"));
        whitelistSelectors[1] = bytes4(keccak256("removeFromWhitelist(address)"));
        whitelistSelectors[2] = bytes4(keccak256("batchAddToWhitelist(address[])"));
        whitelistSelectors[3] = bytes4(keccak256("setInvestorStatus(address,bool)"));
        whitelistSelectors[4] = bytes4(keccak256("setInvestorData(address,(bool,bool,bool,uint64,bytes32,bytes32))"));
        whitelistSelectors[5] =
            bytes4(keccak256("batchSetInvestorData(address[],(bool,bool,bool,uint64,bytes32,bytes32)[])"));
        whitelistSelectors[6] = bytes4(keccak256("getInvestorData(address)"));
        whitelistSelectors[7] = bytes4(keccak256("isWhitelisted(address)"));
        whitelistSelectors[8] = bytes4(keccak256("isAccredited(address)"));
        cut[2] = IDiamondCut.FacetCut({
            facetAddress: address(whitelist),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: whitelistSelectors
        });

        bytes4[] memory rulesSelectors = new bytes4[](5);
        rulesSelectors[0] = bytes4(keccak256("setAssetRules(address,(bool,bool,bool,bool,uint256,uint256))"));
        rulesSelectors[1] = bytes4(keccak256("setJurisdictionRestriction(address,bytes32,bool)"));
        rulesSelectors[2] = bytes4(keccak256("setAccessControl(address)"));
        rulesSelectors[3] = bytes4(keccak256("getAssetRules(address)"));
        rulesSelectors[4] = bytes4(keccak256("isJurisdictionRestricted(address,bytes32)"));
        cut[3] = IDiamondCut.FacetCut({
            facetAddress: address(rulesFacet), action: IDiamondCut.FacetCutAction.Add, functionSelectors: rulesSelectors
        });

        bytes4[] memory checkSelectors = new bytes4[](3);
        checkSelectors[0] = bytes4(keccak256("canTransfer(address,address,address,uint256,uint256)"));
        checkSelectors[1] = bytes4(keccak256("canSubscribe(address,address,uint256,uint256)"));
        checkSelectors[2] = bytes4(keccak256("canRedeem(address,address,uint256)"));
        cut[4] = IDiamondCut.FacetCut({
            facetAddress: address(checkFacet), action: IDiamondCut.FacetCutAction.Add, functionSelectors: checkSelectors
        });

        IDiamondCut(address(d))
            .diamondCut(
                cut, address(cInit), abi.encodeWithSelector(ComplianceInit.initialize.selector, address(accessControl))
            );

        return address(d);
    }
}
