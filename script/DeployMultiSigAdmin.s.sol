// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {MultiSigAdmin} from "../src/admin/contracts/MultiSigAdmin.sol";

/// @title DeployMultiSigAdmin
/// @notice Standalone script to deploy MultiSigAdmin before the main platform.
///         Deploy this first, copy the address to ADMIN_MULTISIG in .env,
///         then run DeployComplianceDiamond.s.sol.
contract DeployMultiSigAdmin is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address[] memory signers = vm.envOr(
            "MULTISIG_SIGNERS",
            ",",
            new address[](0)
        );
        uint256 quorum = vm.envOrUint("MULTISIG_QUORUM", 0);
        uint256 timelock = vm.envOrUint("MULTISIG_TIMELOCK", 48 hours);

        require(signers.length > 0, "MULTISIG_SIGNERS not set");
        require(quorum > 0, "MULTISIG_QUORUM not set");
        require(
            timelock >= 48 hours,
            "MULTISIG_TIMELOCK must be at least 48 hours"
        );

        vm.startBroadcast(deployerPrivateKey);

        console2.log("=== Deploying MultiSigAdmin ===");
        console2.log("Deployer:", deployer);
        console2.log("Signers count:", signers.length);
        console2.log("Quorum:", quorum);
        console2.log("Timelock (seconds):", timelock);

        MultiSigAdmin multisig = new MultiSigAdmin(signers, quorum, timelock);

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== Deployment Complete ===");
        console2.log("MultiSigAdmin deployed at:", address(multisig));
        console2.log("");
        console2.log("Next steps:");
        console2.log("1. Copy the address above");
        console2.log("2. Add to your .env:");
        console2.log("   ADMIN_MULTISIG=", address(multisig));
        console2.log("3. Run DeployComplianceDiamond.s.sol");
    }
}
