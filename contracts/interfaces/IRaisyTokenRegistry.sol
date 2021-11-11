// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IRaisyTokenRegistry {
    function enabled(address) external view returns (bool);

    function getEnabledTokens() external view returns (address[] memory);
}
