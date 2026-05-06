// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IERC173} from "../interfaces/IERC173.sol";

contract OwnershipFacet is IERC173 {
    error InvalidAddress();
    error ETHRescueFailed();

    function transferOwnership(address _newOwner) external override {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.setContractOwner(_newOwner);
    }

    function owner() external view override returns (address owner_) {
        owner_ = LibDiamond.contractOwner();
    }

    function rescueETH(address payable to, uint256 amount) external {
        LibDiamond.enforceIsContractOwner();
        if (to == address(0)) revert InvalidAddress();
        (bool success,) = to.call{value: amount}("");
        if (!success) revert ETHRescueFailed();
    }
}
