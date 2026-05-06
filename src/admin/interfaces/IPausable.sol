// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IPausable {
    event Paused(address account);
    event Unpaused(address account);

    function pause() external;
    function unpause() external;
    function paused() external view returns (bool);
}
