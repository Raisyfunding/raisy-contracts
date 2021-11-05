// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IRaisyAddressRegistry {
    function raisyChef() external view returns (address);

    function tokenRegistry() external view returns (address);

    function priceFeed() external view returns (address);

    function raisyNFT() external view returns (address);

    function raisyToken() external view returns (address);

    function raisyCampaigns() external view returns (address);
}
