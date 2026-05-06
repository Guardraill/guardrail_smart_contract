// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../interfaces/IPausable.sol";
import {Errors} from "../libraries/Errors.sol";

contract Pausable is IPausable {
    bool private _paused;
    address public admin;

    modifier onlyAdmin() {
        require(msg.sender == admin, Errors.NotAdmin());
        _;
    }

    modifier whenNotPaused() {
        require(!_paused, Errors.ContractPaused());
        _;
    }

    modifier whenPaused() {
        require(_paused, Errors.ContractNotPaused());
        _;
    }

    constructor() {
        admin = msg.sender;
        _paused = false;
    }

    function pause() external onlyAdmin whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyAdmin whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }

    function paused() external view returns (bool) {
        return _paused;
    }
}
