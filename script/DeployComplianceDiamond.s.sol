// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

// Diamond infrastructure
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

// Platform contracts
import {AccessControl} from "../src/admin/contracts/AccessControl.sol";
import {MultiSigAdmin} from "../src/admin/contracts/MultiSigAdmin.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {Treasury} from "../src/treasury/contracts/Treasury.sol";
import {OracleDataBridge} from "../src/oracle/contracts/OracleDataBridge.sol";
import {AssetFactory} from "../src/asset/contracts/AssetFactory.sol";
import {BaseAssetToken} from "../src/asset/contracts/BaseAssetToken.sol";

/// @title DeployComplianceDiamond
/// @notice Deployment script that replaces the old ComplianceRegistry.sol
///         with the ComplianceDiamond and wires it into the full platform.
///

contract DeployComplianceDiamond is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address[] memory multisigSigners = vm.envOr(
            "MULTISIG_SIGNERS",
            ",",
            new address[](0)
        );
        uint256 multisigQuorum = vm.envOr("MULTISIG_QUORUM", uint256(0));
        uint256 multisigTimelock = vm.envOr("MULTISIG_TIMELOCK", uint256(48 hours));

        address adminMultisig = vm.envOr("ADMIN_MULTISIG", address(0));
        address operationalAdmin = vm.envOr("OPERATIONAL_ADMIN", deployer);

        if (multisigSigners.length > 0 && multisigQuorum == 0) {
            multisigQuorum = multisigSigners.length;
        }
        if (multisigSigners.length > 0 && multisigTimelock < 48 hours) {
            multisigTimelock = 48 hours;
        }

        address finalDiamondOwner = adminMultisig != address(0)
            ? adminMultisig
            : deployer;
        address defaultAdmin = adminMultisig != address(0)
            ? adminMultisig
            : deployer;

        vm.startBroadcast(deployerPrivateKey);

        console2.log(
            "=== Deploying Guardrail Platform with ComplianceDiamond ==="
        );
        console2.log("Deployer:", deployer);
        if (adminMultisig == address(0)) {
            console2.log(
                "WARNING: ADMIN_MULTISIG not set - using deployer for DEFAULT_ADMIN_ROLE and diamond owner"
            );
        } else {
            console2.log("Admin multisig address:", adminMultisig);
        }
        if (multisigSigners.length > 0) {
            console2.log(
                "MultiSigAdmin will be deployed with signers:",
                multisigSigners.length
            );
            console2.log(
                "  quorum:",
                multisigQuorum,
                "timelock:",
                multisigTimelock
            );
        }
        console2.log("Operational admin:", operationalAdmin);

        if (adminMultisig == address(0) && multisigSigners.length > 0) {
            MultiSigAdmin multisigAdmin = new MultiSigAdmin(
                multisigSigners,
                multisigQuorum,
                multisigTimelock
            );
            adminMultisig = address(multisigAdmin);
            finalDiamondOwner = adminMultisig;
            defaultAdmin = adminMultisig;
            console2.log("MultiSigAdmin deployed:", adminMultisig);
        }

        AccessControl accessControl = new AccessControl(
            defaultAdmin, // defaultAdmin      — holds DEFAULT_ADMIN_ROLE
            operationalAdmin // operationalAdmin  — holds ADMIN_ROLE
        );
        console2.log("AccessControl deployed:", address(accessControl));

        accessControl.grantRole(accessControl.ISSUER_ROLE(), deployer);
        accessControl.grantRole(accessControl.COMPLIANCE_ROLE(), deployer);
        accessControl.grantRole(accessControl.TREASURY_ROLE(), deployer);
        accessControl.grantRole(accessControl.ORACLE_ROLE(), deployer);
        accessControl.grantRole(accessControl.PAUSER_ROLE(), deployer);

        // DiamondCutFacet
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        console2.log("DiamondCutFacet deployed:", address(cutFacet));

        // ─ ComplianceDiamond — the permanent proxy
        ComplianceDiamond diamond = new ComplianceDiamond(
            deployer,
            address(cutFacet)
        );
        console2.log("ComplianceDiamond deployed:", address(diamond));
        if (finalDiamondOwner != deployer) {
            console2.log("Diamond bootstrap owner:", deployer);
            console2.log("Diamond final owner:", finalDiamondOwner);
        }

        // Deploy all compliance facets
        DiamondLoupeFacet loupeFacet = new DiamondLoupeFacet();
        OwnershipFacet ownershipFacet = new OwnershipFacet();
        ComplianceWhitelistFacet whitelistFacet = new ComplianceWhitelistFacet();
        ComplianceRulesFacet rulesFacet = new ComplianceRulesFacet();
        ComplianceCheckFacet checkFacet = new ComplianceCheckFacet();

        console2.log("DiamondLoupeFacet deployed:       ", address(loupeFacet));
        console2.log(
            "OwnershipFacet deployed:          ",
            address(ownershipFacet)
        );
        console2.log(
            "ComplianceWhitelistFacet deployed:",
            address(whitelistFacet)
        );
        console2.log("ComplianceRulesFacet deployed:    ", address(rulesFacet));
        console2.log("ComplianceCheckFacet deployed:    ", address(checkFacet));

        //Deploy ComplianceInit
        ComplianceInit complianceInit = new ComplianceInit();
        console2.log("ComplianceInit deployed:", address(complianceInit));

        //Build the FacetCut array

        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](5);

        // DiamondLoupeFacet — 5 selectors
        bytes4[] memory loupeSelectors = new bytes4[](5);
        loupeSelectors[0] = IDiamondLoupe.facets.selector;
        loupeSelectors[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        loupeSelectors[2] = IDiamondLoupe.facetAddresses.selector;
        loupeSelectors[3] = IDiamondLoupe.facetAddress.selector;
        loupeSelectors[4] = bytes4(keccak256("supportsInterface(bytes4)"));
        // ↑ All 5 values populated — safe to assign
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(loupeFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: loupeSelectors
        });

        // ── OwnershipFacet — 3 selectors ──────────────────────────────────────

        bytes4[] memory ownershipSelectors = new bytes4[](3);
        ownershipSelectors[0] = bytes4(keccak256("transferOwnership(address)"));
        ownershipSelectors[1] = bytes4(keccak256("owner()"));
        ownershipSelectors[2] = bytes4(keccak256("rescueETH(address,uint256)"));
        // ↑ All 3 values populated — safe to assign
        cut[1] = IDiamondCut.FacetCut({
            facetAddress: address(ownershipFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: ownershipSelectors
        });

        bytes4[] memory whitelistSelectors = new bytes4[](9);
        whitelistSelectors[0] = bytes4(keccak256("addToWhitelist(address)"));
        whitelistSelectors[1] = bytes4(
            keccak256("removeFromWhitelist(address)")
        );
        whitelistSelectors[2] = bytes4(
            keccak256("batchAddToWhitelist(address[])")
        );
        whitelistSelectors[3] = bytes4(
            keccak256("setInvestorStatus(address,bool)")
        );
        whitelistSelectors[4] = bytes4(
            keccak256(
                "setInvestorData(address,(bool,bool,bool,uint64,bytes32,bytes32))"
            )
        );
        whitelistSelectors[5] = bytes4(
            keccak256(
                "batchSetInvestorData(address[],(bool,bool,bool,uint64,bytes32,bytes32)[])"
            )
        );
        whitelistSelectors[6] = bytes4(keccak256("getInvestorData(address)"));
        whitelistSelectors[7] = bytes4(keccak256("isWhitelisted(address)"));
        whitelistSelectors[8] = bytes4(keccak256("isAccredited(address)"));
        // ↑ All 9 values populated — NOW safe to assign (Bug 3 fix)
        cut[2] = IDiamondCut.FacetCut({
            facetAddress: address(whitelistFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: whitelistSelectors
        });

        // ── ComplianceRulesFacet — 5 selectors ────────────────────────────────
        bytes4[] memory rulesSelectors = new bytes4[](5);
        rulesSelectors[0] = bytes4(
            keccak256(
                "setAssetRules(address,(bool,bool,bool,bool,uint256,uint256))"
            )
        );
        rulesSelectors[1] = bytes4(
            keccak256("setJurisdictionRestriction(address,bytes32,bool)")
        );
        rulesSelectors[2] = bytes4(keccak256("setAccessControl(address)"));
        rulesSelectors[3] = bytes4(keccak256("getAssetRules(address)"));
        rulesSelectors[4] = bytes4(
            keccak256("isJurisdictionRestricted(address,bytes32)")
        );
        // ↑ All 5 values populated — safe to assign
        cut[3] = IDiamondCut.FacetCut({
            facetAddress: address(rulesFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: rulesSelectors
        });

        bytes4[] memory checkSelectors = new bytes4[](3);
        checkSelectors[0] = bytes4(
            keccak256("canTransfer(address,address,address,uint256,uint256)")
        );
        checkSelectors[1] = bytes4(
            keccak256("canSubscribe(address,address,uint256,uint256)")
        );
        checkSelectors[2] = bytes4(
            keccak256("canRedeem(address,address,uint256)")
        );
        // ↑ All 3 values populated — safe to assign
        cut[4] = IDiamondCut.FacetCut({
            facetAddress: address(checkFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: checkSelectors
        });

        // Step 7: Execute the initial diamondCut
        IDiamondCut(address(diamond)).diamondCut(
            cut,
            address(complianceInit),
            abi.encodeWithSelector(
                ComplianceInit.initialize.selector,
                address(accessControl)
            )
        );
        console2.log(
            "Initial diamondCut executed - all compliance facets registered"
        );

        if (finalDiamondOwner != deployer) {
            OwnershipFacet(address(diamond)).transferOwnership(
                finalDiamondOwner
            );
            console2.log(
                "Diamond ownership transferred:",
                finalDiamondOwner
            );
        }

        //Deploy remaining platform contracts
        MockUSDC usdc = new MockUSDC();
        console2.log("MockUSDC deployed:", address(usdc));

        Treasury treasury = new Treasury(address(usdc), address(accessControl));
        console2.log("Treasury deployed:", address(treasury));

        OracleDataBridge oracle = new OracleDataBridge(address(accessControl));
        console2.log("OracleDataBridge deployed:", address(oracle));
        accessControl.grantRole(accessControl.ORACLE_ROLE(), address(oracle));

        AssetFactory factory = new AssetFactory(
            address(accessControl),
            address(diamond),
            address(treasury)
        );
        console2.log(
            "AssetFactory deployed (compliance = diamond):",
            address(factory)
        );
        accessControl.grantRole(
            accessControl.TREASURY_ROLE(),
            address(factory)
        );
        console2.log("AssetFactory granted TREASURY_ROLE");

        //Create sample asset and configure compliance rules
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
        console2.log("Sample asset token deployed:", tokenAddress);

        ComplianceRulesFacet(address(diamond)).setAssetRules(
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
        console2.log("Compliance rules configured for sample asset");

        vm.stopBroadcast();

        // ── Deployment Summary
        console2.log("\n=== Deployment Summary ===");
        console2.log("AccessControl:             ", address(accessControl));
        console2.log("ComplianceDiamond:         ", address(diamond));
        console2.log("  DiamondCutFacet:         ", address(cutFacet));
        console2.log("  DiamondLoupeFacet:       ", address(loupeFacet));
        console2.log("  OwnershipFacet:          ", address(ownershipFacet));
        console2.log("  ComplianceWhitelistFacet:", address(whitelistFacet));
        console2.log("  ComplianceRulesFacet:    ", address(rulesFacet));
        console2.log("  ComplianceCheckFacet:    ", address(checkFacet));
        console2.log("MockUSDC:                  ", address(usdc));
        console2.log("Treasury:                  ", address(treasury));
        console2.log("OracleDataBridge:          ", address(oracle));
        console2.log("AssetFactory:              ", address(factory));
        console2.log("Sample Asset Token:        ", tokenAddress);
        console2.log("");
        console2.log("IMPORTANT - Testnet notes:");
        console2.log(
            "  deployer holds all roles - use separate wallets on mainnet"
        );
        if (finalDiamondOwner == deployer) {
            console2.log(
                "  diamond owner is deployer - use MultiSigAdmin on mainnet"
            );
        } else {
            console2.log("  diamond owner is MultiSigAdmin");
        }
    }
}
