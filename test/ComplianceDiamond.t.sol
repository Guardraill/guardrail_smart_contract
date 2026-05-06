// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {ComplianceDiamond} from "../src/compliance/diamond/ComplianceDiamond.sol";
import {DiamondCutFacet} from "../src/compliance/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../src/compliance/facets/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "../src/compliance/facets/OwnershipFacet.sol";
import {IDiamondCut} from "../src/compliance/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../src/compliance/interfaces/IDiamondLoupe.sol";

import {ComplianceWhitelistFacet} from "../src/compliance/facets/ComplianceWhitelistFacet.sol";
import {ComplianceRulesFacet} from "../src/compliance/facets/ComplianceRulesFacet.sol";
import {ComplianceCheckFacet} from "../src/compliance/facets/ComplianceCheckFacet.sol";
import {ComplianceInit} from "../src/compliance/diamond/ComplianceInit.sol";
import {LibComplianceStorage} from "../src/compliance/libraries/LibComplianceStorage.sol";

import {AccessControl} from "../src/admin/contracts/AccessControl.sol";
import {Roles} from "../src/admin/libraries/Roles.sol";

contract ComplianceDiamondTest is Test {

    // ── Addresses ─────────────────────────────────────────────────────────────
    address internal owner      = address(1);
    address internal admin      = address(2);
    address internal compliance = address(3);
    address internal investor1  = address(4);
    address internal investor2  = address(5);
    address internal asset      = address(6);
    address internal stranger   = address(99);

    // ── Contracts ─────────────────────────────────────────────────────────────
    AccessControl            internal accessControl;
    ComplianceDiamond        internal diamond;
    ComplianceWhitelistFacet internal whitelist;
    ComplianceRulesFacet     internal rules;
    ComplianceCheckFacet     internal checker;

    bytes32 internal constant JURISDICTION_NG = keccak256("NG");
    bytes32 internal constant JURISDICTION_US = keccak256("US");


    function setUp() public {

       
        accessControl = new AccessControl(owner, admin);

        
        vm.prank(admin);
        accessControl.grantRole(Roles.COMPLIANCE_ROLE, compliance);

        
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        diamond = new ComplianceDiamond(owner, address(cutFacet));

       
        DiamondLoupeFacet        loupeFacet     = new DiamondLoupeFacet();
        OwnershipFacet           ownershipFacet = new OwnershipFacet();
        ComplianceWhitelistFacet whitelistFacet = new ComplianceWhitelistFacet();
        ComplianceRulesFacet     rulesFacet     = new ComplianceRulesFacet();
        ComplianceCheckFacet     checkFacet     = new ComplianceCheckFacet();
        ComplianceInit           complianceInit = new ComplianceInit();

        
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](5);

        
        bytes4[] memory loupeSelectors = new bytes4[](5);
        loupeSelectors[0] = IDiamondLoupe.facets.selector;
        loupeSelectors[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        loupeSelectors[2] = IDiamondLoupe.facetAddresses.selector;
        loupeSelectors[3] = IDiamondLoupe.facetAddress.selector;
        loupeSelectors[4] = bytes4(keccak256("supportsInterface(bytes4)"));
        cut[0] = IDiamondCut.FacetCut({
            facetAddress:      address(loupeFacet),
            action:            IDiamondCut.FacetCutAction.Add,
            functionSelectors: loupeSelectors
        });

        
        bytes4[] memory ownershipSelectors = new bytes4[](2);
        ownershipSelectors[0] = bytes4(keccak256("transferOwnership(address)"));
        ownershipSelectors[1] = bytes4(keccak256("owner()"));
        cut[1] = IDiamondCut.FacetCut({
            facetAddress:      address(ownershipFacet),
            action:            IDiamondCut.FacetCutAction.Add,
            functionSelectors: ownershipSelectors
        });

       
        bytes4[] memory whitelistSelectors = new bytes4[](9);
        whitelistSelectors[0] = bytes4(keccak256("addToWhitelist(address)"));
        whitelistSelectors[1] = bytes4(keccak256("removeFromWhitelist(address)"));
        whitelistSelectors[2] = bytes4(keccak256("batchAddToWhitelist(address[])"));
        whitelistSelectors[3] = bytes4(keccak256("setInvestorStatus(address,bool)"));
        whitelistSelectors[4] = bytes4(keccak256(
            "setInvestorData(address,(bool,bool,bool,uint64,bytes32,bytes32))"
        ));
        whitelistSelectors[5] = bytes4(keccak256(
            "batchSetInvestorData(address[],(bool,bool,bool,uint64,bytes32,bytes32)[])"
        ));
        whitelistSelectors[6] = bytes4(keccak256("getInvestorData(address)"));
        whitelistSelectors[7] = bytes4(keccak256("isWhitelisted(address)"));
        whitelistSelectors[8] = bytes4(keccak256("isAccredited(address)"));
        // All 9 values populated — NOW safe to assign
        cut[2] = IDiamondCut.FacetCut({
            facetAddress:      address(whitelistFacet),
            action:            IDiamondCut.FacetCutAction.Add,
            functionSelectors: whitelistSelectors
        });

        
        bytes4[] memory rulesSelectors = new bytes4[](5);
        rulesSelectors[0] = bytes4(keccak256(
            "setAssetRules(address,(bool,bool,bool,bool,uint256,uint256))"
        ));
        rulesSelectors[1] = bytes4(keccak256(
            "setJurisdictionRestriction(address,bytes32,bool)"
        ));
        rulesSelectors[2] = bytes4(keccak256("setAccessControl(address)"));
        rulesSelectors[3] = bytes4(keccak256("getAssetRules(address)"));
        rulesSelectors[4] = bytes4(keccak256(
            "isJurisdictionRestricted(address,bytes32)"
        ));
        cut[3] = IDiamondCut.FacetCut({
            facetAddress:      address(rulesFacet),
            action:            IDiamondCut.FacetCutAction.Add,
            functionSelectors: rulesSelectors
        });

        
        bytes4[] memory checkSelectors = new bytes4[](3);
        checkSelectors[0] = bytes4(keccak256(
            "canTransfer(address,address,address,uint256,uint256)"
        ));
        checkSelectors[1] = bytes4(keccak256(
            "canSubscribe(address,address,uint256,uint256)"  // 4 params
        ));
        checkSelectors[2] = bytes4(keccak256(
            "canRedeem(address,address,uint256)"
        ));
        cut[4] = IDiamondCut.FacetCut({
            facetAddress:      address(checkFacet),
            action:            IDiamondCut.FacetCutAction.Add,
            functionSelectors: checkSelectors
        });

        
        bytes memory initCalldata = abi.encodeWithSelector(
            ComplianceInit.initialize.selector,
            address(accessControl)
        );
        vm.prank(owner);
        IDiamondCut(address(diamond)).diamondCut(cut, address(complianceInit), initCalldata);

        
        whitelist = ComplianceWhitelistFacet(address(diamond));
        rules     = ComplianceRulesFacet(address(diamond));
        checker   = ComplianceCheckFacet(address(diamond));

        
        vm.prank(compliance);
        rules.setAssetRules(
            asset,
            LibComplianceStorage.AssetRules({
                transfersEnabled:      true,
                subscriptionsEnabled:  true,
                redemptionsEnabled:    true,
                requiresAccreditation: false,
                minInvestment:         1e18,
                maxInvestorBalance:    100_000 * 1e18
            })
        );
    }

  

    function testDiamondDeployedCorrectly() public view {
        address diamondOwner = OwnershipFacet(address(diamond)).owner();
        assertEq(diamondOwner, owner);

        IDiamondLoupe.Facet[] memory facets =
            IDiamondLoupe(address(diamond)).facets();
        assertEq(facets.length, 6);
    }

    function testInitializerCannotBeCalledTwice() public {
        ComplianceInit init = new ComplianceInit();
        bytes memory call = abi.encodeWithSelector(
            ComplianceInit.initialize.selector,
            address(accessControl)
        );
        IDiamondCut.FacetCut[] memory empty;
        vm.prank(owner);
        vm.expectRevert();
        IDiamondCut(address(diamond)).diamondCut(empty, address(init), call);
    }

    

    function testAddAndRemoveFromWhitelist() public {
        vm.prank(compliance);
        whitelist.addToWhitelist(investor1);

        LibComplianceStorage.InvestorData memory data =
            whitelist.getInvestorData(investor1);
        assertTrue(data.isVerified);
        assertFalse(data.isFrozen);

        vm.prank(compliance);
        whitelist.removeFromWhitelist(investor1);
        data = whitelist.getInvestorData(investor1);
        assertFalse(data.isVerified);
    }

    function testSetInvestorDataFull() public {
        LibComplianceStorage.InvestorData memory profile =
            LibComplianceStorage.InvestorData({
                isVerified:   true,
                isAccredited: true,
                isFrozen:     false,
                validUntil:   uint64(block.timestamp + 365 days),
                jurisdiction: JURISDICTION_NG,
                externalRef:  keccak256("KYC-001")
            });

        vm.prank(compliance);
        whitelist.setInvestorData(investor1, profile);

        LibComplianceStorage.InvestorData memory stored =
            whitelist.getInvestorData(investor1);
        assertTrue(stored.isVerified);
        assertTrue(stored.isAccredited);
        assertEq(stored.jurisdiction, JURISDICTION_NG);
        assertEq(stored.externalRef, keccak256("KYC-001"));
    }

    function testBatchWhitelist() public {
        address[] memory investors = new address[](3);
        investors[0] = investor1;
        investors[1] = investor2;
        investors[2] = address(7);

        vm.prank(compliance);
        whitelist.batchAddToWhitelist(investors);

        assertTrue(whitelist.getInvestorData(investor1).isVerified);
        assertTrue(whitelist.getInvestorData(investor2).isVerified);
        assertTrue(whitelist.getInvestorData(address(7)).isVerified);
    }

    function testUnauthorizedWhitelistCallReverts() public {
        vm.prank(stranger);
        vm.expectRevert(ComplianceWhitelistFacet.Unauthorized.selector);
        whitelist.addToWhitelist(investor1);
    }

    

    function testSetAndGetAssetRules() public view {
        LibComplianceStorage.AssetRules memory r = rules.getAssetRules(asset);
        assertTrue(r.transfersEnabled);
        assertTrue(r.subscriptionsEnabled);
        assertFalse(r.requiresAccreditation);
        assertEq(r.minInvestment, 1e18);
    }

    function testJurisdictionRestriction() public {
        assertFalse(rules.isJurisdictionRestricted(asset, JURISDICTION_US));

        vm.prank(compliance);
        rules.setJurisdictionRestriction(asset, JURISDICTION_US, true);
        assertTrue(rules.isJurisdictionRestricted(asset, JURISDICTION_US));

        vm.prank(compliance);
        rules.setJurisdictionRestriction(asset, JURISDICTION_US, false);
        assertFalse(rules.isJurisdictionRestricted(asset, JURISDICTION_US));
    }



    function testCanTransferHappyPath() public {
        vm.startPrank(compliance);
        whitelist.setInvestorData(investor1, LibComplianceStorage.InvestorData({
            isVerified: true, isAccredited: false, isFrozen: false,
            validUntil: 0, jurisdiction: JURISDICTION_NG, externalRef: bytes32(0)
        }));
        whitelist.setInvestorData(investor2, LibComplianceStorage.InvestorData({
            isVerified: true, isAccredited: false, isFrozen: false,
            validUntil: 0, jurisdiction: JURISDICTION_NG, externalRef: bytes32(0)
        }));
        vm.stopPrank();

        (bool ok, bytes32 reason) = checker.canTransfer(
            asset, investor1, investor2, 1e18, 0
        );
        assertTrue(ok);
        assertEq(reason, bytes32(0));
    }

    function testCanTransferBlockedWhenDisabled() public {
        vm.prank(compliance);
        rules.setAssetRules(asset, LibComplianceStorage.AssetRules({
            transfersEnabled:      false,
            subscriptionsEnabled:  true,
            redemptionsEnabled:    true,
            requiresAccreditation: false,
            minInvestment:         0,
            maxInvestorBalance:    0
        }));

        (bool ok, bytes32 reason) = checker.canTransfer(
            asset, investor1, investor2, 1e18, 0
        );
        assertFalse(ok);
        assertEq(reason, keccak256("TRANSFERS_DISABLED"));
    }

    function testCanTransferBlockedWhenSenderNotVerified() public {
        vm.prank(compliance);
        whitelist.setInvestorData(investor2, LibComplianceStorage.InvestorData({
            isVerified: true, isAccredited: false, isFrozen: false,
            validUntil: 0, jurisdiction: JURISDICTION_NG, externalRef: bytes32(0)
        }));

        (bool ok, bytes32 reason) = checker.canTransfer(
            asset, investor1, investor2, 1e18, 0
        );
        assertFalse(ok);
        assertEq(reason, keccak256("SENDER_NOT_ELIGIBLE"));
    }

    function testCanTransferBlockedByJurisdiction() public {
        vm.startPrank(compliance);
        whitelist.setInvestorData(investor1, LibComplianceStorage.InvestorData({
            isVerified: true, isAccredited: false, isFrozen: false,
            validUntil: 0, jurisdiction: JURISDICTION_NG, externalRef: bytes32(0)
        }));
        whitelist.setInvestorData(investor2, LibComplianceStorage.InvestorData({
            isVerified: true, isAccredited: false, isFrozen: false,
            validUntil: 0, jurisdiction: JURISDICTION_US, externalRef: bytes32(0)
        }));
        rules.setJurisdictionRestriction(asset, JURISDICTION_US, true);
        vm.stopPrank();

        (bool ok, bytes32 reason) = checker.canTransfer(
            asset, investor1, investor2, 1e18, 0
        );
        assertFalse(ok);
        assertEq(reason, keccak256("RECIPIENT_JURISDICTION_RESTRICTED"));
    }

    function testCanTransferBlockedByMaxBalance() public {
        vm.startPrank(compliance);
        whitelist.setInvestorData(investor1, LibComplianceStorage.InvestorData({
            isVerified: true, isAccredited: false, isFrozen: false,
            validUntil: 0, jurisdiction: JURISDICTION_NG, externalRef: bytes32(0)
        }));
        whitelist.setInvestorData(investor2, LibComplianceStorage.InvestorData({
            isVerified: true, isAccredited: false, isFrozen: false,
            validUntil: 0, jurisdiction: JURISDICTION_NG, externalRef: bytes32(0)
        }));
        vm.stopPrank();

        // receiving 2e18 on top of 99_999e18 would exceed the 100_000e18 cap
        (bool ok, bytes32 reason) = checker.canTransfer(
            asset, investor1, investor2, 2e18, 99_999 * 1e18
        );
        assertFalse(ok);
        assertEq(reason, keccak256("MAX_BALANCE_EXCEEDED"));
    }

    

    function testCanSubscribeHappyPath() public {
        vm.prank(compliance);
        whitelist.setInvestorData(investor1, LibComplianceStorage.InvestorData({
            isVerified: true, isAccredited: false, isFrozen: false,
            validUntil: 0, jurisdiction: JURISDICTION_NG, externalRef: bytes32(0)
        }));

        
        (bool ok, bytes32 reason) = checker.canSubscribe(
            asset, investor1, 1e18, 1e18
        );
        assertTrue(ok);
        assertEq(reason, bytes32(0));
    }

    function testCanSubscribeBlockedBelowMinInvestment() public {
        vm.prank(compliance);
        whitelist.setInvestorData(investor1, LibComplianceStorage.InvestorData({
            isVerified: true, isAccredited: false, isFrozen: false,
            validUntil: 0, jurisdiction: JURISDICTION_NG, externalRef: bytes32(0)
        }));

        // minInvestment is 1e18 — buying 0.5e18 should fail
        (bool ok, bytes32 reason) = checker.canSubscribe(
            asset, investor1, 0.5e18, 0.5e18
        );
        assertFalse(ok);
        assertEq(reason, keccak256("BELOW_MIN_INVESTMENT"));
    }


    function testUpgradeWhitelistFacet() public {
        vm.prank(compliance);
        whitelist.addToWhitelist(investor1);
        assertTrue(whitelist.getInvestorData(investor1).isVerified);

       
        ComplianceWhitelistFacet newFacet = new ComplianceWhitelistFacet();

        bytes4[] memory replaceSelectors = new bytes4[](1);
        replaceSelectors[0] = bytes4(keccak256("addToWhitelist(address)"));

        IDiamondCut.FacetCut[] memory upgradeCut = new IDiamondCut.FacetCut[](1);
        upgradeCut[0] = IDiamondCut.FacetCut({
            facetAddress:      address(newFacet),
            action:            IDiamondCut.FacetCutAction.Replace,
            functionSelectors: replaceSelectors
        });

        vm.prank(owner);
        IDiamondCut(address(diamond)).diamondCut(upgradeCut, address(0), "");

        
        assertTrue(whitelist.getInvestorData(investor1).isVerified);

        
        vm.prank(compliance);
        whitelist.addToWhitelist(investor2);
        assertTrue(whitelist.getInvestorData(investor2).isVerified);
    }
}