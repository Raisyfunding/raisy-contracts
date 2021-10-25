// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

interface IRaisyAddressRegistry {
    function raisyChef() external view returns (address);

    function tokenRegistry() external view returns (address);

    function priceFeed() external view returns (address);

    function raisyNFT() external view returns (address);

    function raisyToken() external view returns (address);
}

interface IRaisyChef {
    function add(uint256, uint256) external;
}

interface IRaisyNFT {
    struct donationInfo {
        uint256 amount;
        address tokenUsed;
        uint256 campaignId;
        address recipient;
        uint256 creationTimestamp;
    }

    function mint(donationInfo calldata) external;
}

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
        uint256 id; // ID of the campaign automatically set by the counter
        address creator; // Creator of the campaign
        bool isOver;
        uint256 duration;
        uint256 startBlock;
        uint256 amountToRaise;
        uint256 amountRaised;
        bool hasReleaseSchedule;
    }

    /// @notice Maximum and Minimum campaigns' duration
    uint256 public maxDuration;
    uint256 public minDuration;

    /// @notice Latest campaign ID
    Counters.Counter private _campaignIdCounter;

    /// @notice Campaign ID -> Campaign
    mapping(uint256 => Campaign) public allCampaigns;

    /// @notice Campaign ID -> bool
    mapping(uint256 => bool) public campaignExistence;

    /// @notice address -> Campaign ID -> amount donated
    mapping(address => mapping(uint256 => uint256)) public userDonations;

    /// @notice Address registry
    IRaisyAddressRegistry public addressRegistry;

    modifier isNotOver(uint256 _campaignId) {
        require(
            allCampaigns[_campaignId].startBlock +
                allCampaigns[_campaignId].duration >=
                block.number,
            "Campaign is over."
        );
        _;
    }

    modifier isOver(uint256 _campaignId) {
        require(
            allCampaigns[_campaignId].startBlock +
                allCampaigns[_campaignId].duration <=
                block.number,
            "Campaign is over."
        );
        _;
    }

    modifier exists(uint256 _campaignId) {
        require(campaignExistence[_campaignId], "Campaign does not exist.");
        _;
    }

    function addCampaign(
        uint256 _duration,
        uint256 _amountToRaise,
        bool _hasReleaseSchedule
    ) external {
        require(_duration <= maxDuration, "duration too long");
        require(_duration >= minDuration, "duration too short");
        require(_amountToRaise > 0, "amount to raise null");

        uint256 campaignId = _campaignIdCounter.current();

        // Add a new campaign to the mapping
        allCampaigns[campaignId] = Campaign(
            campaignId,
            msg.sender,
            false,
            _duration,
            block.number,
            _amountToRaise,
            0,
            _hasReleaseSchedule
        );

        // Add new pool to the RaisyChef
        IRaisyChef raisyChef = IRaisyChef(addressRegistry.raisyChef());
        raisyChef.add(campaignId, block.number + _duration);

        // Inrease the counter
        _campaignIdCounter.increment();

        // Note that it now exists
        campaignExistence[campaignId] = true;

        // Emit creation event
    }

    function donate(
        uint256 _campaignId,
        uint256 _amount,
        address _payToken
    ) external isNotOver(_campaignId) exists(_campaignId) nonReentrant {
        require(_amount > 0, "Donation must be positive.");

        // Transfer the donation to the contract
        IERC20 payToken = IERC20(_payToken);
        payToken.safeTransferFrom(msg.sender, address(this), _amount);

        // Update the mappings
        allCampaigns[_campaignId].amountRaised += _amount;

        userDonations[msg.sender][_campaignId] += _amount;

        // Emit donation event
    }

    function claimProofOfDonation(uint256 _campaignId)
        external
        exists(_campaignId)
        nonReentrant
    {
        require(allCampaigns[_campaignId].isOver, "Campaign is not over.");
        require(userDonations[msg.sender][_campaignId] > 0, "No PoD to claim.");

        // Mint Raisy NFT
        IRaisyNFT raisyNFT = IRaisyNFT(addressRegistry.raisyNFT());

        IRaisyNFT.donationInfo memory donationInfo = IRaisyNFT.donationInfo(
            userDonations[msg.sender][_campaignId],
            addressRegistry.raisyToken(),
            _campaignId,
            msg.sender,
            block.timestamp
        );

        raisyNFT.mint(donationInfo);

        // Reset his donation amount
        userDonations[msg.sender][_campaignId] = 0;

        // Emit the claim event
    }

    function claimFunds(uint256 _campaignId)
        external
        exists(_campaignId)
        isOver(_campaignId)
        nonReentrant
    {
        require(
            allCampaigns[_campaignId].creator == msg.sender,
            "You're not the creator ."
        );

        if (allCampaigns[_campaignId].hasReleaseSchedule) {
            
        } else {
            // Transfer the funds to the campaign's creator
            IERC20 payToken = IERC20(_payToken);
            payToken.safeTransferFrom(
                address(this),
                msg.sender,
                allCampaigns[_campaignId].amountRaised
            );
        }

        // Enable Proof of Donation
        allCampaigns[_campaignId].isOver = true;

        // Emit the claim event
    }

    /**
     @notice Update AgoraAddressRegistry contract
     @dev Only admin
     */
    function updateAddressRegistry(address _registry) external onlyOwner {
        addressRegistry = IRaisyAddressRegistry(_registry);
    }
}
