// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./RaisyFundsRelease.sol";

interface IRaisyChef {
    function add(uint256, uint256) external;

    function deposit(address,uint256, uint256) external;
}

/// @title Main Smart Contract of the architecture
/// @author Raisy Funding
/// @notice Main Contract handling the campaigns' creation and donations
/// @dev Inherits of upgradeable versions of OZ libraries
/// interacts with the AddressRegistry / RaisyNFTFactory / RaisyFundsRelease
contract RaisyCampaigns is RaisyFundsRelease {
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using AddressUpgradeable for address payable;
    using SafeERC20 for IERC20;

    /// @notice Events for the contract
    event CampaignCreated(
        uint256 id,
        address indexed creator,
        uint256 duration,
        uint256 startBlock,
        uint256 amountToRaise,
        bool hasReleaseSchedule
    );

    event NewDonation(
        uint256 campaignId,
        address indexed donor,
        uint256 amount,
        address indexed payToken
    );

    event ProofOfDonationClaimed(
        uint256 campaignId,
        address indexed donor,
        uint256 tokenId
    );

    event FundsClaimed(uint256 campaignId, address indexed creator);

    event Refund(
        uint256 campaignId,
        address indexed user,
        uint256 refundAmount
    );

    event MoreFundsAsked(uint256 campaignId, address indexed creator);

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
    uint256 public maxDuration = 200;
    uint256 public minDuration = 20;

    /// @notice Latest campaign ID
    CountersUpgradeable.Counter private _campaignIdCounter;

    /// @notice Campaign ID -> Campaign
    mapping(uint256 => Campaign) public allCampaigns;

    /// @notice Campaign ID -> bool
    mapping(uint256 => bool) public campaignExistence;

    /// @notice address -> Campaign ID -> amount donated
    mapping(address => mapping(uint256 => uint256)) public userDonations;

    /// @notice Campaign ID -> funds already claimed
    mapping(uint256 => uint256) public campaignFundsClaimed;

    /// @notice Modifiers
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

    modifier isSuccess(uint256 _campaignId) {
        require(
            allCampaigns[_campaignId].amountRaised >=
                allCampaigns[_campaignId].amountToRaise,
            "Campaign hasn't been successful."
        );
        _;
    }

    modifier onlyCreator(uint256 _campaignId) {
        require(
            allCampaigns[_campaignId].creator == msg.sender,
            "You're not the creator ."
        );
        _;
    }

    /// @notice Contract initializer
    function initialize() public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
    }

    /// @notice Add a campaign without any release schedule
    function addCampaign(uint256 _duration, uint256 _amountToRaise) external {
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
            false
        );

        // Add new pool to the RaisyChef
        IRaisyChef raisyChef = IRaisyChef(addressRegistry.raisyChef());
        raisyChef.add(campaignId, block.number + _duration);

        // Inrease the counter
        _campaignIdCounter.increment();

        // Note that it now exists
        campaignExistence[campaignId] = true;

        // Emit creation event
        emit CampaignCreated(
            campaignId,
            msg.sender,
            _duration,
            block.number,
            _amountToRaise,
            false
        );
    }

    /// @notice Add campaign with a release schedule
    function addCampaign(
        uint256 _duration,
        uint256 _amountToRaise,
        uint256 _nbMilestones,
        uint256[] calldata _pctReleasePerMilestone
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
            true
        );

        // Add new pool to the RaisyChef
        IRaisyChef raisyChef = IRaisyChef(addressRegistry.raisyChef());
        raisyChef.add(campaignId, block.number + _duration);

        // Register the schedule
        register(campaignId, _nbMilestones, _pctReleasePerMilestone);

        // Inrease the counter
        _campaignIdCounter.increment();

        // Note that it now exists
        campaignExistence[campaignId] = true;

        // Emit creation event
        emit CampaignCreated(
            campaignId,
            msg.sender,
            _duration,
            block.number,
            _amountToRaise,
            true
        );
    }

    function donate(
        uint256 _campaignId,
        uint256 _amount,
        address _payToken
    ) external isNotOver(_campaignId) exists(_campaignId) nonReentrant {
        require(_amount > 0, "Donation must be positive.");

        IERC20 payToken = IERC20(_payToken);

        // If the donation is in $RSY then deposit in the pool
        if (_payToken == addressRegistry.raisyToken()) {
            IRaisyChef raisyChef = IRaisyChef(addressRegistry.raisyChef());
            raisyChef.deposit(msg.sender, _campaignId, _amount);
        } else {
            // Transfer the donation to the contract
            payToken.safeTransferFrom(msg.sender, address(this), _amount);
        }

        // Update the mappings
        allCampaigns[_campaignId].amountRaised += _amount;

        if (userDonations[msg.sender][_campaignId] == 0)
            nbDonors[_campaignId]++;

        userDonations[msg.sender][_campaignId] += _amount;

        // Emit donation event
        emit NewDonation(_campaignId, msg.sender, _amount, _payToken);
    }

    function claimProofOfDonation(uint256 _campaignId)
        external
        exists(_campaignId)
        nonReentrant
    {
        require(allCampaigns[_campaignId].isOver, "Campaign is not over.");
        require(userDonations[msg.sender][_campaignId] > 0, "No PoD to claim.");
        require(!podClaimed[_campaignId][msg.sender], "PoD already claimed.");

        // Mint Raisy NFT
        IRaisyNFT raisyNFT = IRaisyNFT(addressRegistry.raisyNFT());

        IRaisyNFT.DonationInfo memory donationInfo = IRaisyNFT.DonationInfo(
            userDonations[msg.sender][_campaignId],
            addressRegistry.raisyToken(),
            _campaignId,
            msg.sender,
            block.timestamp
        );

        uint256 tokenId = raisyNFT.mint(donationInfo);

        podClaimed[_campaignId][msg.sender] = true;

        // Emit the claim event
        emit ProofOfDonationClaimed(_campaignId, msg.sender, tokenId);
    }

    function claimInitialFunds(uint256 _campaignId)
        external
        exists(_campaignId)
        isOver(_campaignId)
        isSuccess(_campaignId)
        onlyCreator(_campaignId)
        nonReentrant
    {
        require(
            campaignFundsClaimed[_campaignId] <
                allCampaigns[_campaignId].amountRaised,
            "No more funds to claim."
        );

        require(
            !allCampaigns[_campaignId].isOver,
            "Initial Funds Release already triggered."
        );

        IERC20 payToken = IERC20(addressRegistry.raisyToken());

        if (allCampaigns[_campaignId].hasReleaseSchedule) {
            // Trigger state change on RaisyFundsRelease
            uint256 toReleasePct = getNextPctFunds(_campaignId);
            uint256 toReleaseAmount = (allCampaigns[_campaignId].amountRaised *
                toReleasePct) / 10000;

            // Transfer the funds to the campaign's creator
            payToken.safeTransferFrom(
                address(this),
                msg.sender,
                toReleaseAmount
            );

            campaignFundsClaimed[_campaignId] += toReleaseAmount;
        } else {
            // Transfer the funds to the campaign's creator

            payToken.safeTransferFrom(
                address(this),
                msg.sender,
                allCampaigns[_campaignId].amountRaised
            );

            campaignFundsClaimed[_campaignId] += allCampaigns[_campaignId]
                .amountRaised;
        }

        // Enable Proof of Donation
        allCampaigns[_campaignId].isOver = true;

        // Emit the claim event
        emit FundsClaimed(_campaignId, msg.sender);
    }

    /// @notice If donors voted YES to transfer the next portion of funds
    /// then the creator can come up and call this function to claim the funds
    function claimNextFunds(uint256 _campaignId)
        external
        exists(_campaignId)
        isOver(_campaignId)
        isSuccess(_campaignId)
        onlyCreator(_campaignId)
        nonReentrant
    {
        require(
            campaignFundsClaimed[_campaignId] <
                allCampaigns[_campaignId].amountRaised,
            "No more funds to claim."
        );
        require(allCampaigns[_campaignId].isOver, "Initial funds not claimed.");
        require(endVoteSession(_campaignId), "Vote didn't pass.");

        IERC20 payToken = IERC20(addressRegistry.raisyToken());

        // Trigger state change on RaisyFundsRelease
        uint256 toReleasePct = getNextPctFunds(_campaignId);
        uint256 toReleaseAmount = (allCampaigns[_campaignId].amountRaised *
            toReleasePct) / 10000;

        // Transfer the funds to the campaign's creator
        payToken.safeTransferFrom(address(this), msg.sender, toReleaseAmount);

        campaignFundsClaimed[_campaignId] += toReleaseAmount;

        // Emit the claim event
        emit FundsClaimed(_campaignId, msg.sender);
    }

    /// @notice The creator can come up at anytime during his campaign to ask for more funds
    /// This initializes a vote session in the RaisyFundsRelease contract
    function askMoreFunds(uint256 _campaignId)
        external
        exists(_campaignId)
        isOver(_campaignId)
        isSuccess(_campaignId)
        onlyCreator(_campaignId)
        nonReentrant
    {
        require(
            campaignFundsClaimed[_campaignId] <
                allCampaigns[_campaignId].amountRaised,
            "No more funds to claim."
        );
        require(allCampaigns[_campaignId].isOver, "Initial funds not claimed.");

        initializeVoteSession(_campaignId);

        emit MoreFundsAsked(_campaignId, msg.sender);
    }

    function getFundsBack(uint256 _campaignId)
        external
        exists(_campaignId)
        isOver(_campaignId)
        isSuccess(_campaignId)
        atStage(_campaignId, Stages.Refund)
        hasProofOfDonation(_campaignId)
        nonReentrant
    {
        require(
            userDonations[msg.sender][_campaignId] > 0,
            "No more funds to withdraw."
        );

        IERC20 payToken = IERC20(addressRegistry.raisyToken());

        uint256 refundAmount = (userDonations[msg.sender][_campaignId] *
            (10000 - campaignSchedule[_campaignId].pctReleased)) / 10000;

        if (refundAmount > 0) {
            // Transfer the funds back to the user
            payToken.safeTransferFrom(address(this), msg.sender, refundAmount);

            userDonations[msg.sender][_campaignId] = 0;
        }

        emit Refund(_campaignId, msg.sender, refundAmount);
    }

    //TODO: Write functions which calls harvest and withdraw functions in RaisyChef
    // 1. All the funds have been released -> the donor can now safely claim his rewards
    // 2. The campaign didn't reach its objective -> the donor can withdraw his funds and harvest without any lock period
}
