// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

contract RaisyAddressRegistry is Ownable {
    /// @notice RaisyTokenRegistry contract
    address public tokenRegistry;

    /// @notice RaisyPriceFeed contract
    address public priceFeed;

    /// @notice RaisyChef contract
    address public raisyChef;

    /// @notice RaisyToken contract
    address public raisyToken;

    /**
     @notice Update token registry contract
     @dev Only admin
     */
    function updateTokenRegistry(address _tokenRegistry) external onlyOwner {
        tokenRegistry = _tokenRegistry;
    }

    /**
     @notice Update price feed contract
     @dev Only admin
     */
    function updatePriceFeed(address _priceFeed) external onlyOwner {
        priceFeed = _priceFeed;
    }

    /**
     @notice Update raisy chef contract
     @dev Only admin
     */
    function updateRaisyChef(address _raisyChef) external onlyOwner {
        raisyChef = _raisyChef;
    }

    /**
     @notice Update raisy chef contract
     @dev Only admin
     */
    function updateRaisyToken(address _raisyToken) external onlyOwner {
        raisyToken = _raisyToken;
    }
}