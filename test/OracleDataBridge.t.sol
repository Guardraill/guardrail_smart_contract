// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

// Admin
import {AccessControl} from "../src/admin/contracts/AccessControl.sol";
import {Roles} from "../src/admin/libraries/Roles.sol";

// Asset
import {AssetFactory} from "../src/asset/contracts/AssetFactory.sol";
import {BaseAssetToken} from "../src/asset/contracts/BaseAssetToken.sol";

// Compliance diamond — replaces deleted ComplianceRegistry
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

// Oracle
import {OracleDataBridge} from "../src/oracle/contracts/OracleDataBridge.sol";
import {IOracleDataBridge} from "../src/oracle/interfaces/IOracleDataBridge.sol";

// Treasury and mock
import {Treasury} from "../src/treasury/contracts/Treasury.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";

contract OracleDataBridgeTest is Test {
    
    AccessControl public accessControl;
    MockUSDC public usdc;
    address public complianceDiamond; // ← replaces ComplianceRegistry
    Treasury public treasury;
    OracleDataBridge public oracle;
    AssetFactory public factory;
    BaseAssetToken public assetToken;

    
    address public admin = address(11);
    address public oracleSigner = address(12);

    
    function setUp() public {
        vm.startPrank(admin);

        
        accessControl = new AccessControl(admin, admin);

        
        usdc = new MockUSDC();

        
        complianceDiamond = _deployComplianceDiamond();

        
        treasury = new Treasury(address(usdc), address(accessControl));

        
        oracle = new OracleDataBridge(address(accessControl));

        
        factory = new AssetFactory(
            address(accessControl),
            complianceDiamond, 
            address(treasury)
        );

        
        accessControl.grantRole(Roles.ISSUER_ROLE, admin);
        accessControl.grantRole(Roles.COMPLIANCE_ROLE, admin);
        accessControl.grantRole(Roles.TREASURY_ROLE, admin);
        accessControl.grantRole(Roles.ORACLE_ROLE, oracleSigner);
        accessControl.grantRole(Roles.ORACLE_ROLE, address(oracle));
        accessControl.grantRole(Roles.TREASURY_ROLE, address(factory));

        
        factory.registerAssetType(keccak256("PRIVATE_CREDIT"), "Private Credit", address(0));
        

        address tokenAddress = factory.createAsset(
            7,
            keccak256("PRIVATE_CREDIT"),
            "Fund Token",
            "FUND",
            500_000 * 1e18,
            abi.encode(
                AssetFactory.AssetCreationConfig({
                    subscriptionPrice: 1e6,
                    redemptionPrice: 95e4,
                    selfServicePurchaseEnabled: true,
                    metadataHash: keccak256("fund")
                })
            )
        );
        assetToken = BaseAssetToken(tokenAddress);

        
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

        vm.stopPrank();
    }

  

    function testOracleCanSubmitValuationAndSyncPricing() public {
        vm.prank(oracleSigner);
        oracle.submitValuationAndSyncPricing(
            address(assetToken), 25_000_000 * 1e6, 102e4, 101e4, 99e4, keccak256("valuation-1")
        );

        IOracleDataBridge.AssetValuation memory valuation = oracle.getLatestValuation(address(assetToken));

        assertEq(valuation.assetValue, 25_000_000 * 1e6);
        assertEq(valuation.navPerToken, 102e4);
        assertEq(assetToken.pricePerToken(), 101e4);
        assertEq(assetToken.redemptionPricePerToken(), 99e4);
    }

    function testOracleCanAnchorDocuments() public {
        bytes32 documentHash = keccak256("ipfs://term-sheet");
        bytes32 documentType = keccak256("TERM_SHEET");

        vm.prank(oracleSigner);
        oracle.anchorDocument(address(assetToken), documentType, documentHash, keccak256("doc-1"));

        assertEq(oracle.getDocumentHash(address(assetToken), documentType), documentHash);
    }

    function testUntrustedAccountCannotSubmitOracleUpdates() public {
        vm.prank(address(99));
        vm.expectRevert(OracleDataBridge.Unauthorized.selector);
        oracle.submitValuation(address(assetToken), 1, 1, keccak256("bad"));
    }

    function testAdminCanTrustExternalOracleSigner() public {
        address externalOracle = address(13);

        vm.prank(admin);
        oracle.setTrustedOracle(externalOracle, true);

        vm.prank(externalOracle);
        oracle.submitValuation(address(assetToken), 10_000_000 * 1e6, 101e4, keccak256("trusted"));

        IOracleDataBridge.AssetValuation memory valuation = oracle.getLatestValuation(address(assetToken));

        assertEq(valuation.navPerToken, 101e4);
    }

    
    function _deployComplianceDiamond() internal returns (address diamond) {
        // Deploy bootstrap cut facet
        DiamondCutFacet cutFacet = new DiamondCutFacet();

        // Deploy the diamond proxy — admin owns it for tests
        ComplianceDiamond d = new ComplianceDiamond(admin, address(cutFacet));

        // Deploy all compliance facets
        DiamondLoupeFacet loupeFacet = new DiamondLoupeFacet();
        OwnershipFacet ownerFacet = new OwnershipFacet();
        ComplianceWhitelistFacet whitelist = new ComplianceWhitelistFacet();
        ComplianceRulesFacet rulesFacet = new ComplianceRulesFacet();
        ComplianceCheckFacet checkFacet = new ComplianceCheckFacet();
        ComplianceInit cInit = new ComplianceInit();

        // Build the FacetCut array
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](5);

        // DiamondLoupeFacet
        bytes4[] memory loupeSelectors = new bytes4[](5);
        loupeSelectors[0] = IDiamondLoupe.facets.selector;
        loupeSelectors[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        loupeSelectors[2] = IDiamondLoupe.facetAddresses.selector;
        loupeSelectors[3] = IDiamondLoupe.facetAddress.selector;
        loupeSelectors[4] = bytes4(keccak256("supportsInterface(bytes4)"));
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(loupeFacet), action: IDiamondCut.FacetCutAction.Add, functionSelectors: loupeSelectors
        });

        // OwnershipFacet
        bytes4[] memory ownerSelectors = new bytes4[](2);
        ownerSelectors[0] = bytes4(keccak256("transferOwnership(address)"));
        ownerSelectors[1] = bytes4(keccak256("owner()"));
        cut[1] = IDiamondCut.FacetCut({
            facetAddress: address(ownerFacet), action: IDiamondCut.FacetCutAction.Add, functionSelectors: ownerSelectors
        });

        // ComplianceWhitelistFacet — 9 selectors
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

        // ComplianceRulesFacet — 5 selectors
        bytes4[] memory rulesSelectors = new bytes4[](5);
        rulesSelectors[0] = bytes4(keccak256("setAssetRules(address,(bool,bool,bool,bool,uint256,uint256))"));
        rulesSelectors[1] = bytes4(keccak256("setJurisdictionRestriction(address,bytes32,bool)"));
        rulesSelectors[2] = bytes4(keccak256("setAccessControl(address)"));
        rulesSelectors[3] = bytes4(keccak256("getAssetRules(address)"));
        rulesSelectors[4] = bytes4(keccak256("isJurisdictionRestricted(address,bytes32)"));
        cut[3] = IDiamondCut.FacetCut({
            facetAddress: address(rulesFacet), action: IDiamondCut.FacetCutAction.Add, functionSelectors: rulesSelectors
        });

        // ComplianceCheckFacet — 3 selectors
        bytes4[] memory checkSelectors = new bytes4[](3);
        checkSelectors[0] = bytes4(keccak256("canTransfer(address,address,address,uint256,uint256)"));
        checkSelectors[1] = bytes4(keccak256("canSubscribe(address,address,uint256,uint256)"));
        checkSelectors[2] = bytes4(keccak256("canRedeem(address,address,uint256)"));
        cut[4] = IDiamondCut.FacetCut({
            facetAddress: address(checkFacet), action: IDiamondCut.FacetCutAction.Add, functionSelectors: checkSelectors
        });

        // Execute the initial cut and initialise storage
        IDiamondCut(address(d))
            .diamondCut(
                cut, address(cInit), abi.encodeWithSelector(ComplianceInit.initialize.selector, address(accessControl))
            );

        return address(d);
    }
}
