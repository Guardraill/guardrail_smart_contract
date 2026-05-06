// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {AccessControl} from "../src/admin/contracts/AccessControl.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
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
import {OracleDataBridge} from "../src/oracle/contracts/OracleDataBridge.sol";
import {Treasury} from "../src/treasury/contracts/Treasury.sol";
import {AssetFactory} from "../src/asset/contracts/AssetFactory.sol";
import {BaseAssetToken} from "../src/asset/contracts/BaseAssetToken.sol";

contract DeployTestnet is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console2.log("Guardrail Platform - Testnet Deployment");
        console2.log("Deployer:", deployer);

        AccessControl accessControl = new AccessControl(deployer, deployer);
        console2.log("[1/8] AccessControl deployed at:", address(accessControl));

        accessControl.grantRole(accessControl.ISSUER_ROLE(), deployer);
        accessControl.grantRole(accessControl.COMPLIANCE_ROLE(), deployer);
        accessControl.grantRole(accessControl.TREASURY_ROLE(), deployer);
        accessControl.grantRole(accessControl.ORACLE_ROLE(), deployer);
        accessControl.grantRole(accessControl.PAUSER_ROLE(), deployer);

        MockUSDC usdc = new MockUSDC();
        console2.log("[2/8] MockUSDC deployed at:", address(usdc));

        console2.log("[3/8] Deploying ComplianceDiamond system...");
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        ComplianceDiamond diamond = new ComplianceDiamond(deployer, address(cutFacet));
        DiamondLoupeFacet loupeFacet = new DiamondLoupeFacet();
        OwnershipFacet ownerFacet = new OwnershipFacet();
        ComplianceWhitelistFacet whitelist = new ComplianceWhitelistFacet();
        ComplianceRulesFacet rules = new ComplianceRulesFacet();
        ComplianceCheckFacet checker = new ComplianceCheckFacet();
        ComplianceInit cInit = new ComplianceInit();

        IDiamondCut(address(diamond))
            .diamondCut(
                _buildFacetCuts(
                    address(loupeFacet), address(ownerFacet), address(whitelist), address(rules), address(checker)
                ),
                address(cInit),
                abi.encodeWithSelector(ComplianceInit.initialize.selector, address(accessControl))
            );
        console2.log("  ComplianceDiamond:", address(diamond));
        console2.log("  diamondCut executed - all facets registered");

        Treasury treasury = new Treasury(address(usdc), address(accessControl));
        console2.log("[4/8] Treasury deployed at:", address(treasury));

        OracleDataBridge oracle = new OracleDataBridge(address(accessControl));
        accessControl.grantRole(accessControl.ORACLE_ROLE(), address(oracle));
        console2.log("[5/8] OracleDataBridge deployed at:", address(oracle));

        AssetFactory factory = new AssetFactory(address(accessControl), address(diamond), address(treasury));
        console2.log("[6/8] AssetFactory deployed at:", address(factory));
        accessControl.grantRole(accessControl.TREASURY_ROLE(), address(factory));
        console2.log("  AssetFactory granted TREASURY_ROLE");

        bytes32 realEstateType = keccak256("REAL_ESTATE");
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
                    metadataHash: bytes32(0)
                })
            )
        );
        console2.log("[7/8] Sample asset token PROP1 deployed at:", tokenAddress);

        ComplianceRulesFacet(address(diamond))
            .setAssetRules(
                tokenAddress,
                LibComplianceStorage.AssetRules({
                transfersEnabled: true,
                subscriptionsEnabled: true,
                redemptionsEnabled: true,
                requiresAccreditation: false,
                minInvestment: 1e18,
                maxInvestorBalance: 250_000 * 1e18
            })
            );
        console2.log("[8/8] Compliance rules configured for PROP1");

        vm.stopBroadcast();

        console2.log("=== Deployment Summary ===");
        console2.log("AccessControl:     ", address(accessControl));
        console2.log("MockUSDC:          ", address(usdc));
        console2.log("ComplianceDiamond: ", address(diamond));
        console2.log("Treasury:          ", address(treasury));
        console2.log("OracleDataBridge:  ", address(oracle));
        console2.log("AssetFactory:      ", address(factory));
        console2.log("Sample Asset PROP1:", tokenAddress);
    }

    function _buildFacetCuts(
        address loupeFacet,
        address ownershipFacet,
        address whitelistFacet,
        address rulesFacet,
        address checkFacet
    ) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        cut = new IDiamondCut.FacetCut[](5);

        bytes4[] memory loupeSelectors = new bytes4[](5);
        loupeSelectors[0] = IDiamondLoupe.facets.selector;
        loupeSelectors[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        loupeSelectors[2] = IDiamondLoupe.facetAddresses.selector;
        loupeSelectors[3] = IDiamondLoupe.facetAddress.selector;
        loupeSelectors[4] = bytes4(keccak256("supportsInterface(bytes4)"));
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: loupeFacet, action: IDiamondCut.FacetCutAction.Add, functionSelectors: loupeSelectors
        });

        bytes4[] memory ownershipSelectors = new bytes4[](3);
        ownershipSelectors[0] = bytes4(keccak256("transferOwnership(address)"));
        ownershipSelectors[1] = bytes4(keccak256("owner()"));
        ownershipSelectors[2] = bytes4(keccak256("rescueETH(address,uint256)"));
        cut[1] = IDiamondCut.FacetCut({
            facetAddress: ownershipFacet, action: IDiamondCut.FacetCutAction.Add, functionSelectors: ownershipSelectors
        });

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
            facetAddress: whitelistFacet, action: IDiamondCut.FacetCutAction.Add, functionSelectors: whitelistSelectors
        });

        bytes4[] memory rulesSelectors = new bytes4[](5);
        rulesSelectors[0] = bytes4(keccak256("setAssetRules(address,(bool,bool,bool,bool,uint256,uint256))"));
        rulesSelectors[1] = bytes4(keccak256("setJurisdictionRestriction(address,bytes32,bool)"));
        rulesSelectors[2] = bytes4(keccak256("setAccessControl(address)"));
        rulesSelectors[3] = bytes4(keccak256("getAssetRules(address)"));
        rulesSelectors[4] = bytes4(keccak256("isJurisdictionRestricted(address,bytes32)"));
        cut[3] = IDiamondCut.FacetCut({
            facetAddress: rulesFacet, action: IDiamondCut.FacetCutAction.Add, functionSelectors: rulesSelectors
        });

        bytes4[] memory checkSelectors = new bytes4[](3);
        checkSelectors[0] = bytes4(keccak256("canTransfer(address,address,address,uint256,uint256)"));
        checkSelectors[1] = bytes4(keccak256("canSubscribe(address,address,uint256,uint256)"));
        checkSelectors[2] = bytes4(keccak256("canRedeem(address,address,uint256)"));
        cut[4] = IDiamondCut.FacetCut({
            facetAddress: checkFacet, action: IDiamondCut.FacetCutAction.Add, functionSelectors: checkSelectors
        });
    }
}
