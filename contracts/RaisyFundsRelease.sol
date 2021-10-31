// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

interface IRaisyAddressRegistry {
    function raisyChef() external view returns (address);

    function tokenRegistry() external view returns (address);

    function priceFeed() external view returns (address);

    function raisyNFT() external view returns (address);

    function raisyToken() external view returns (address);

    function raisyCampaigns() external view returns (address);
}

contract RaisyFundsRelease is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /// @notice Events of the contract
    event ScheduleRegistered(
        uint256 campaignId,
        uint256 nbMilestones,
        uint256 pctReleaseAtStart,
        uint256[] pctReleasePerMilestone
    );

    event AddressRegistryUpdated(address indexed newAddressRegistry);

    /// @notice Stages Enum
    enum Stages {
        Initial,
        Release,
        AllReleased,
        Refund
    }

    /// @notice Schedule Structure
    struct Schedule {
        uint256 campaignId;
        uint256 nbMilestones;
        uint256 pctReleaseAtStart;
        uint256[] pctReleasePerMilestone;
        Stages releaseStage;
    }

    /// @notice Campaign ID -> Schedule
    mapping(uint256 => Schedule) public campaignSchedule;

    /// @notice Campaign ID -> bool
    mapping(uint256 => bool) public scheduleExistence;

    /// @notice Maximum number of milestones
    uint256 public MAX_NB_MILESTONES;

    /// @notice Maximum release percentage at start
    uint256 public MAX_PCT_RELEASE_START = 10000;

    /// @notice Minimum release percentage at start
    uint256 public MIN_PCT_RELEASE_START = 2000;

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

    modifier onlyRaisyChef() {
        require(
            msg.sender == addressRegistry.raisyCampaigns(),
            "msg.sender has to be RaisyCampaigns."
        );
        _;
    }

    constructor(uint256 _maxNbMilestones) {
        MAX_NB_MILESTONES = _maxNbMilestones;
    }

    /// @notice This function allows to register a schedule for a given campaignId
    /// @dev Only
    function register(
        uint256 _campaignId,
        uint256 _nbMilestones,
        uint256[] calldata _pctReleasePerMilestone,
        uint256 _pctReleaseAtStart
    ) external onlyRaisyChef {
        require(_nbMilestones > 0, "Needs at least 1 milestone.");
        require(
            _pctReleasePerMilestone.length == _nbMilestones,
            "Only one percent per milestone."
        );
        require(
            _pctReleaseAtStart >= MIN_PCT_RELEASE_START,
            "Start release pct too low."
        );
        require(
            _pctReleaseAtStart <= MAX_PCT_RELEASE_START,
            "Start release pct too high."
        );

        uint256 pctSum = 0;
        for (uint256 index = 0; index < _nbMilestones; index++) {
            pctSum += _pctReleasePerMilestone[index];
        }

        require(
            pctSum + _pctReleaseAtStart == 10000,
            "Pcts should add up to 100%"
        );

        require(
            !scheduleExistence[_campaignId],
            "Campaign already has a schedule."
        );

        // Add the schedule to the mapping
        campaignSchedule[_campaignId] = Schedule(
            _campaignId,
            _nbMilestones,
            _pctReleaseAtStart,
            _pctReleasePerMilestone,
            Stages.Initial
        );

        // Emit the register event
        emit ScheduleRegistered(
            _campaignId,
            _nbMilestones,
            _pctReleaseAtStart,
            _pctReleasePerMilestone
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
}
