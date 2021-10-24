// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

/// @title Main Smart Contract of the architecture
/// @author Raisy Funding
/// @notice Main Contract handling the campaigns' creation and donations
/// @dev Inherits of upgradeable versions of OZ libraries
/// interacts with the AddressRegistry / RaisyNFTFactory / RaisyFundsRelease 
contract RaisyCampaigns is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using Counters for Counters.Counter;
    using AddressUpgradeable for address payable;
    using SafeERC20 for IERC20;

    

    /// @notice Events for the contract

    /// @notice Structure for a campaign
    struct Campaign {
      uint256 id;
      bool isOver;
      uint256 duration;
      uint256 amountToRaise;
      uint256 amountRaised;
      UserInfo creator;
      PoolInfo poolInfo;
    }

    /// @notice Maximum and Minimum campaigns' duration
    uint256 public maxDuration;
    uint256 public minDuration;

    /// @notice Latest campaign ID
    Counters.Counter private _campaignIdCounter; 
}