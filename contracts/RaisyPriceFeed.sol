// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IRaisyAddressRegistry.sol";

interface IRaisyTokenRegistry {
    function enabled(address) external returns (bool);
}

interface IOracle {
    function decimals() external view returns (uint8);

    function latestAnswer() external view returns (int256);
}

contract RaisyPriceFeed is Ownable {
    /// @notice keeps track of oracles for each tokens
    mapping(address => address) public oracles;

    /// @notice Raisy address registry contract
    address public addressRegistry;

    /// @notice wrapped AVAX contract
    address public wAVAX;

    constructor(address _addressRegistry, address _wAVAX) {
        addressRegistry = _addressRegistry;
        wAVAX = _wAVAX;
    }

    /**
     @notice Register oracle contract to token
     @dev Only owner can register oracle
     @param _token ERC20 token address
     @param _oracle Oracle address
     */
    function registerOracle(address _token, address _oracle)
        external
        onlyOwner
    {
        IRaisyTokenRegistry tokenRegistry = IRaisyTokenRegistry(
            IRaisyAddressRegistry(addressRegistry).tokenRegistry()
        );
        require(tokenRegistry.enabled(_token), "invalid token");
        require(oracles[_token] == address(0), "oracle already set");

        oracles[_token] = _oracle;
    }

    /**
     @notice Update oracle address for token
     @dev Only owner can update oracle
     @param _token ERC20 token address
     @param _oracle Oracle address
     */
    function updateOracle(address _token, address _oracle) external onlyOwner {
        require(oracles[_token] != address(0), "oracle not set");

        oracles[_token] = _oracle;
    }

    /**
     @notice Get current price for token
     @dev return current price or if oracle is not registered returns 0
     @param _token ERC20 token address
     */
    function getPrice(address _token) external view returns (int256, uint8) {
        if (oracles[_token] == address(0)) {
            return (0, 0);
        }

        if (_token == IRaisyAddressRegistry(addressRegistry).raisyToken()) {
            // TODO: Get the price through the liquidity pool
        }

        IOracle oracle = IOracle(oracles[_token]);
        return (oracle.latestAnswer(), oracle.decimals());
    }

    /**
     @notice Update address registry contract
     @dev Only admin
     */
    function updateAddressRegistry(address _addressRegistry)
        external
        onlyOwner
    {
        addressRegistry = _addressRegistry;
    }
}
