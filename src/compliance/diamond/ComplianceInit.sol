// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LibComplianceStorage} from "../libraries/LibComplianceStorage.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IDiamondLoupe} from "../interfaces/IDiamondLoupe.sol";
import {IDiamondCut} from "../interfaces/IDiamondCut.sol";
import {IERC165} from "../interfaces/IERC165.sol";


/// @notice One-time initializer contract called via delegatecall during the
///         initial diamondCut that adds all three compliance facets.
///

contract ComplianceInit {
    error AlreadyInitialized();
    error InvalidAccessControl();

    function initialize(address accessControl) external {
        LibComplianceStorage.Layout storage l = LibComplianceStorage.layout();

        if (l.initialized) revert AlreadyInitialized();
        if (accessControl == address(0)) revert InvalidAccessControl();

        l.accessControl = accessControl;
        l.initialized = true;

        // Register ERC-165 interface support in LibDiamond storage
        // so that external tools can query what interfaces this diamond supports.
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IERC165).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
    }
}
