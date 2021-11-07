// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "./interfaces/IRaisyAddressRegistry.sol";

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

/// @title RaisyFundsRelease
/// @author RaisyFunding
/// @notice Smart contract responsible for managing the campaigns' schedule as well as the voting system
/// @dev Parent of RaisyCampaigns, Will be an implementation of a proxy and therefore upgradeable
/// Owner is the ProxyAdmin hence the governance (gnosis-snap-safe)
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

    event NewVote(uint256 campaignId, address indexed voter, int256 voteRatio);

    event VoteRefund(
        uint256 campaignId,
        address indexed voter,
        uint256 wantsRefundTotal
    );

    /// @notice Stages Enum
    enum Stages {
        Nothing,
        Release,
        AllReleased,
        Refund
    }

    /// @notice Schedule Structure
    struct Schedule {
        uint256 campaignId;
        uint256 nbMilestones;
        uint256[] pctReleasePerMilestone;
        uint256 pctReleased;
        uint256 wantsRefund;
        uint8 currentMilestone;
        Stages releaseStage;
    }

    /// @notice Vote Structure
    struct VoteSession {
        uint256 startBlock;
        int256 voteRatio;
        bool inProgress;
        uint8 numUnsuccessfulVotes;
        mapping(address => bool) hasVoted;
    }

    /// @notice Campaign ID -> Schedule
    mapping(uint256 => Schedule) public campaignSchedule;

    /// @notice Campaign ID -> bool
    mapping(uint256 => bool) public scheduleExistence;

    /// @notice Campaign ID -> Vote Session
    mapping(uint256 => VoteSession) public voteSession;

    /// @notice Campaign ID -> user -> wants refund
    mapping(uint256 => mapping(address => bool)) public refundVotes;

    /// @notice Campaign ID -> Number of donors
    mapping(uint256 => uint256) public nbDonors;

    /// @notice Campaign ID -> user address -> Proof of Donation claimed
    mapping(uint256 => mapping(address => bool)) public podClaimed;

    /// @notice Maximum number of milestones
    uint256 public MAX_NB_MILESTONES = 5;

    /// @notice Maximum release percentage at start
    uint256 public MAX_PCT_RELEASE_START = 10000;

    /// @notice Minimum release percentage at start
    uint256 public MIN_PCT_RELEASE_START = 2000;

    /// @notice Vote sessions duration (in blocks)
    uint256 public VOTE_SESSION_DURATION = 84200;

    /// @notice Vote refund treshold (BP)
    uint256 public REFUND_TRESHOLD = 5000;

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

    modifier hasProofOfDonation(uint256 _campaignId) {
        // IRaisyNFT raisyNFT = IRaisyNFT(addressRegistry.raisyNFT());

        // uint256 userBalance = raisyNFT.balanceOf(msg.sender);

        // /// Checks if msg.sender has a proof of donation
        // require(userBalance > 0, "Proof Of Donation needed.");

        // bool _hasProofOfDonation = false;

        // for (uint256 index = 0; index < userBalance; index++) {
        //     uint256 tokenId = raisyNFT.tokenOfOwnerByIndex(msg.sender, index);

        //     // Gets the donation info for the tokenId
        //     IRaisyNFT.DonationInfo memory donationInfo = raisyNFT
        //         .getDonationInfo(tokenId);

        //     if (donationInfo.campaignId == _campaignId)
        //         _hasProofOfDonation = true;
        // }

        // require(_hasProofOfDonation, "No POD for this campaign.");

        require(
            podClaimed[_campaignId][msg.sender],
            "No PoD for this campaign."
        );

        _;
    }

    /// @notice This function allows to register a schedule for a given campaignId
    /// @dev Internal function called in RaisyCampaigns.sol when the capaign is created
    /// @param _campaignId Id of the campaign
    /// @param _nbMilestones The number of milestones the project owner wants to add
    /// @param _pctReleasePerMilestone The percentage of funds released at each milestone
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

        scheduleExistence[_campaignId] = true;

        // Add the schedule to the mapping
        campaignSchedule[_campaignId] = Schedule(
            _campaignId,
            _nbMilestones,
            _pctReleasePerMilestone,
            0,
            0,
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

    /**
     * @notice Gives the next percentage of total funds to be released
     * @dev Internal function called in RaisyCampaigns.sol to release funds
     * @param _campaignId Id of the campaign
     */
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
        campaignSchedule[_campaignId].pctReleased += pctToRelease;

        if (
            campaignSchedule[_campaignId].currentMilestone >=
            campaignSchedule[_campaignId].nbMilestones
        ) {
            campaignSchedule[_campaignId].releaseStage = Stages.AllReleased;
        }

        return pctToRelease;
    }

    /// @notice Starts a vote session to release the next porition of funds
    /// @dev Internal function called by the campaign's owner in RaisyCampaigns.sol to ask for more funds
    /// @param _campaignId Id of the campaign
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
        _voteSession.numUnsuccessfulVotes = 0;

        emit VoteSessionInitialized(_campaignId);
    }

    /**
     * @notice Funders can vote whether they give more funds or not
     * @param _campaignId Id of the campaign
     * @param _vote Vote yes or no
     */
    function vote(uint256 _campaignId, bool _vote)
        external
        atStage(_campaignId, Stages.Release)
        hasProofOfDonation(_campaignId)
        nonReentrant
    {
        require(
            voteSession[_campaignId].inProgress,
            "No vote session in progress."
        );
        require(
            !voteSession[_campaignId].hasVoted[msg.sender],
            "Can only vote once."
        );
        require(
            block.number <
                voteSession[_campaignId].startBlock + VOTE_SESSION_DURATION,
            "Vote session finished."
        );

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
     * @notice Ends the vote session, pays the campaign owner or increase the number of unsuccessful votes.
     * @param _campaignId Id of the campaign
     */
    function endVoteSession(uint256 _campaignId)
        internal
        atStage(_campaignId, Stages.Release)
        returns (bool)
    {
        require(
            voteSession[_campaignId].inProgress,
            "Vote session not in progress."
        );
        require(
            block.number >=
                voteSession[_campaignId].startBlock + VOTE_SESSION_DURATION,
            "Vote session not ended."
        );

        voteSession[_campaignId].inProgress = false;

        if (voteSession[_campaignId].voteRatio >= 0) {
            voteSession[_campaignId].numUnsuccessfulVotes = 0;
            delete voteSession[_campaignId];
            return true;
        } else {
            voteSession[_campaignId].numUnsuccessfulVotes++;
            if (voteSession[_campaignId].numUnsuccessfulVotes == 3) {
                campaignSchedule[_campaignId].releaseStage = Stages.Refund;
                delete voteSession[_campaignId];
            }
            return false;
        }
    }

    function voteRefund(uint256 _campaignId)
        external
        atStage(_campaignId, Stages.Release)
        hasProofOfDonation(_campaignId)
    {
        require(!refundVotes[_campaignId][msg.sender], "Only 1 vote per user.");

        refundVotes[_campaignId][msg.sender] = true;

        campaignSchedule[_campaignId].wantsRefund++;

        // Go to Refund state if more than 50% of donors ask for a refund
        if (
            campaignSchedule[_campaignId].wantsRefund >
            (nbDonors[_campaignId] * REFUND_TRESHOLD) / 10000
        ) {
            campaignSchedule[_campaignId].releaseStage = Stages.Refund;
        }

        emit VoteRefund(
            _campaignId,
            msg.sender,
            campaignSchedule[_campaignId].wantsRefund
        );
    }

    /**
     * @notice Update AgoraAddressRegistry contract
     * @dev Only admin
     */
    function updateAddressRegistry(address _registry) external onlyOwner {
        addressRegistry = IRaisyAddressRegistry(_registry);

        emit AddressRegistryUpdated(_registry);
    }

    /**
     * @notice Update VOTE_SESSION_DURATION (in blocks)
     * @dev Only admin
     */
    function updateVoteSessionDuration(uint256 _duration) external onlyOwner {
        VOTE_SESSION_DURATION = _duration;

        emit VoteSessionDurationUpdated(_duration);
    }
}
