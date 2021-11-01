// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

interface IRaisyAddressRegistry {
    function raisyChef() external view returns (address);

    function tokenRegistry() external view returns (address);

    function priceFeed() external view returns (address);

    function raisyNFT() external view returns (address);

    function raisyToken() external view returns (address);

    function raisyCampaigns() external view returns (address);
}

interface IRaisyNFT {
    struct DonationInfo {
        uint256 amount;
        address tokenUsed;
        uint256 campaignId;
        address recipient;
        uint256 creationTimestamp;
    }

    function balanceOf(address) external view returns (uint256);

    function getDonationInfo(uint256)
        external
        view
        returns (DonationInfo memory);

    function tokenOfOwnerByIndex(address, uint256)
        external
        view
        returns (uint256);

    function mint(DonationInfo calldata) external returns (uint256);
}

contract RaisyFundsRelease is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /// @notice Events of the contract
    event ScheduleRegistered(
        uint256 campaignId,
        uint256 nbMilestones,
        uint256[] pctReleasePerMilestone
    );

    event AddressRegistryUpdated(address indexed newAddressRegistry);

    event VoteSessionDurationUpdated(uint256 newAddressRegistry);

    event VoteSessionInitialized(uint256 campaignId);

    event NewVote(uint256 campaignId, address indexed voter, uint256 voteRatio);

    /// @notice Stages Enum
    enum Stages {
        Release,
        AllReleased,
        Refund
    }

    /// @notice Schedule Structure
    struct Schedule {
        uint256 campaignId;
        uint256 nbMilestones;
        uint256[] pctReleasePerMilestone;
        uint8 currentMilestone;
        Stages releaseStage;
    }

    struct VoteSession {
        uint256 startBlock;
        uint256 voteRatio;
        bool inProgress;
        mapping(address => bool) hasVoted;
    }

    /// @notice Campaign ID -> Schedule
    mapping(uint256 => Schedule) public campaignSchedule;

    /// @notice Campaign ID -> bool
    mapping(uint256 => bool) public scheduleExistence;

    /// @notice Campaign ID -> Vote Session
    mapping(uint256 => VoteSession) public voteSession;

    /// @notice Maximum number of milestones
    uint256 public MAX_NB_MILESTONES = 5;

    /// @notice Maximum release percentage at start
    uint256 public MAX_PCT_RELEASE_START = 10000;

    /// @notice Minimum release percentage at start
    uint256 public MIN_PCT_RELEASE_START = 2000;

    /// @notice Vote sessions duration (in blocks)
    uint256 public VOTE_SESSION_DURATION = 84200;

    /// @notice Address registry
    IRaisyAddressRegistry public addressRegistry;

    /// @notice Modifiers
    modifier atStage(uint256 _campaignId, Stages _stage) {
        require(
            campaignSchedule[_campaignId].releaseStage == _stage,
            "Not at correct stage."
        );
        _;
    }

    /// @notice This function allows to register a schedule for a given campaignId
    /// @dev Only callable by RaisyCampaigns
    function register(
        uint256 _campaignId,
        uint256 _nbMilestones,
        uint256[] calldata _pctReleasePerMilestone
    ) internal {
        require(_nbMilestones > 0, "Needs at least 1 milestone.");
        require(_nbMilestones <= MAX_NB_MILESTONES, "Too many milestones.");
        require(
            _pctReleasePerMilestone.length == _nbMilestones,
            "Only one percent per milestone."
        );
        require(
            _pctReleasePerMilestone[0] >= MIN_PCT_RELEASE_START,
            "Start release pct too low."
        );
        require(
            _pctReleasePerMilestone[0] <= MAX_PCT_RELEASE_START,
            "Start release pct too high."
        );

        uint256 pctSum = 0;
        for (uint256 index = 0; index < _nbMilestones; index++) {
            pctSum += _pctReleasePerMilestone[index];
        }

        require(pctSum == 10000, "Pcts should add up to 100%");

        require(
            !scheduleExistence[_campaignId],
            "Campaign already has a schedule."
        );

        // Add the schedule to the mapping
        campaignSchedule[_campaignId] = Schedule(
            _campaignId,
            _nbMilestones,
            _pctReleasePerMilestone,
            0,
            Stages.Release
        );

        // Emit the register event
        emit ScheduleRegistered(
            _campaignId,
            _nbMilestones,
            _pctReleasePerMilestone
        );
    }

    function getNextPctFunds(uint256 _campaignId)
        internal
        atStage(_campaignId, Stages.Release)
        returns (uint256)
    {
        require(scheduleExistence[_campaignId], "No schedule registered.");

        uint8 current = campaignSchedule[_campaignId].currentMilestone;

        uint256 pctToRelease = campaignSchedule[_campaignId]
            .pctReleasePerMilestone[current];

        campaignSchedule[_campaignId].currentMilestone++;

        if (
            campaignSchedule[_campaignId].currentMilestone >=
            campaignSchedule[_campaignId].nbMilestones
        ) {
            campaignSchedule[_campaignId].releaseStage = Stages.AllReleased;
        }

        return pctToRelease;
    }

    /// @notice Starts a vote session to release the next porition of funds
    function initializeVoteSession(uint256 _campaignId)
        internal
        atStage(_campaignId, Stages.Release)
    {
        require(
            !voteSession[_campaignId].inProgress,
            "Vote session already in progress."
        );

        // Adds the vote session to the mapping

        VoteSession storage _voteSession = voteSession[_campaignId];

        _voteSession.inProgress = true;
        _voteSession.startBlock = block.number;
        _voteSession.voteRatio = 0;

        emit VoteSessionInitialized(_campaignId);
    }

    function vote(uint256 _campaignId, bool _vote) external nonReentrant {
        require(
            voteSession[_campaignId].inProgress,
            "No vote session in progress."
        );
        require(
            !voteSession[_campaignId].hasVoted[msg.sender],
            "Can only vote once."
        );

        IRaisyNFT raisyNFT = IRaisyNFT(addressRegistry.raisyNFT());

        uint256 userBalance = raisyNFT.balanceOf(msg.sender);

        /// Checks if msg.sender has a proof of donation
        require(userBalance > 0, "Proof Of Donation needed.");

        bool hasProofOfDonation = false;

        for (uint256 index = 0; index < userBalance; index++) {
            uint256 tokenId = raisyNFT.tokenOfOwnerByIndex(msg.sender, index);
            
            // Gets the donation info for the tokenId
            IRaisyNFT.DonationInfo memory donationInfo = raisyNFT
                .getDonationInfo(tokenId);

            if (donationInfo.campaignId == _campaignId)
                hasProofOfDonation = true;
        }

        require(hasProofOfDonation, "No Proof Of Donation for this campaign.");

        if (_vote) voteSession[_campaignId].voteRatio++;
        else voteSession[_campaignId].voteRatio--;

        voteSession[_campaignId].hasVoted[msg.sender] = true;

        emit NewVote(
            _campaignId,
            msg.sender,
            voteSession[_campaignId].voteRatio
        );
    }

    /**
     @notice Update AgoraAddressRegistry contract
     @dev Only admin
     */
    function updateAddressRegistry(address _registry) external onlyOwner {
        addressRegistry = IRaisyAddressRegistry(_registry);

        emit AddressRegistryUpdated(_registry);
    }

    /**
     @notice Update VOTE_SESSION_DURATION (in blocks)
     @dev Only admin
     */
    function updateVoteSessionDuration(uint256 _duration) external onlyOwner {
        VOTE_SESSION_DURATION = _duration;

        emit VoteSessionDurationUpdated(_duration);
    }
}
