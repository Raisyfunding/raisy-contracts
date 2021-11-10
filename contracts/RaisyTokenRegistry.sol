// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract RaisyTokenRegistry is Ownable {
    /// @dev Events of the contract
    event TokenAdded(address token);
    event TokenRemoved(address token);

    /// @notice ERC20 Address -> Bool
    mapping(address => bool) public enabled;

    // Declare a set state variable
    EnumerableSet.AddressSet private _enabledTokens;

    /**
  @notice Method for adding payment token
  @dev Only admin
  @param token ERC20 token address
  */
    function add(address token) external onlyOwner {
        require(!enabled[token], "token already added");
        enabled[token] = true;
        EnumerableSet.add(_enabledTokens, token);
        emit TokenAdded(token);
    }

    /**
  @notice Method for removing payment token
  @dev Only admin
  @param token ERC20 token address
  */
    function remove(address token) external onlyOwner {
        require(enabled[token], "token not exist");
        enabled[token] = false;
        EnumerableSet.remove(_enabledTokens, token);
        emit TokenRemoved(token);
    }

    function getEnabledTokens() external view returns (address[] memory) {
        return EnumerableSet.values(_enabledTokens);
    }
}
