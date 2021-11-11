// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./RaisyFundsRelease.sol";
import "./interfaces/IRaisyTokenRegistry.sol";

interface IRaisyChef {
    function add(uint256, uint256) external;

    function deposit(
        address,
        uint256,
        uint256
    ) external;

    function claimRewards(address, uint256) external;
}

interface IRaisyPriceFeed {
    function wAVAX() external view returns (address);

    function getPrice(address) external view returns (int256, uint8);
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
        uint256 refundAmount,
        address payToken
    );

    event WithdrawFunds(
        uint256 campaignId,
        address indexed user,
        uint256 amount,
        address payToken
    );

    event MoreFundsAsked(uint256 campaignId, address indexed creator);

    /// @notice Structure for a campaign
    struct Campaign {
        uint256 id; // ID of the campaign automatically set by the counter
        address creator; // Creator of the campaign
        uint256 duration;
        uint256 startBlock;
        uint256 amountToRaise; // IN USD w/ 18 decimals e.g 25 USD = 25 * 10 ** 18
        uint256 amountRaised; // IN USD w/ 18 decimals e.g 25 USD = 25 * 10 ** 18
        mapping(address => uint256) amountRaisedPerToken;
        bool isOver;
        bool hasReleaseSchedule;
    }

    /// @notice Structure for a donation
    struct Donation {
        uint256 amountInUSD; // Total amount given in USD
        mapping(address => uint256) amountPerToken;
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

    /// @notice address -> Campaign ID -> Donation
    mapping(address => mapping(uint256 => Donation)) public userDonations;

    /// @notice Campaign ID -> funds already claimed
    mapping(uint256 => uint256) public campaignFundsClaimed;

    /// @notice Modifiers
    modifier isNotOver(uint256 _campaignId) {
        require(
            allCampaigns[_campaignId].startBlock +
                allCampaigns[_campaignId].duration >=
                _getBlock(),
            "Campaign is over."
        );
        _;
    }

    modifier isOver(uint256 _campaignId) {
        require(
            allCampaigns[_campaignId].startBlock +
                allCampaigns[_campaignId].duration <=
                _getBlock(),
            "Campaign is not over."
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
        Campaign storage campaign = allCampaigns[campaignId];

        campaign.id = campaignId;
        campaign.creator = msg.sender;
        campaign.amountToRaise = _amountToRaise;
        campaign.isOver = false;
        campaign.hasReleaseSchedule = false;
        campaign.duration = _duration;
        campaign.amountRaised = 0;
        campaign.startBlock = _getBlock();

        // Add new pool to the RaisyChef
        IRaisyChef raisyChef = IRaisyChef(addressRegistry.raisyChef());
        raisyChef.add(campaignId, _getBlock() + _duration);

        // Inrease the counter
        _campaignIdCounter.increment();

        // Note that it now exists
        campaignExistence[campaignId] = true;

        // Emit creation event
        emit CampaignCreated(
            campaignId,
            msg.sender,
            _duration,
            _getBlock(),
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
        Campaign storage campaign = allCampaigns[campaignId];

        campaign.id = campaignId;
        campaign.creator = msg.sender;
        campaign.amountToRaise = _amountToRaise;
        campaign.isOver = false;
        campaign.hasReleaseSchedule = true;
        campaign.duration = _duration;
        campaign.amountRaised = 0;
        campaign.startBlock = _getBlock();

        // Add new pool to the RaisyChef
        IRaisyChef raisyChef = IRaisyChef(addressRegistry.raisyChef());
        raisyChef.add(campaignId, _getBlock() + _duration);

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
            _getBlock(),
            _amountToRaise,
            true
        );
    }

    function donate(
        uint256 _campaignId,
        uint256 _amount,
        address _payToken
    ) external exists(_campaignId) isNotOver(_campaignId) nonReentrant {
        require(_amount > 0, "Donation must be positive.");

        _validPayToken(_payToken);

        IERC20 payToken = IERC20(_payToken);

        // If the donation is in $RSY then deposit in the pool
        if (_payToken == addressRegistry.raisyToken()) {
            IRaisyChef raisyChef = IRaisyChef(addressRegistry.raisyChef());
            raisyChef.deposit(msg.sender, _campaignId, _amount);
        }

        // Transfer the donation to the contract
        payToken.safeTransferFrom(msg.sender, address(this), _amount);

        // Update the mappings
        (int256 _tokenPrice, uint8 _decimals) = getPrice(_payToken);

        // E.g : _amount = 10 WBTC = 10 * 1e8
        // WBTC Price is 100 USD => amountInUSD = 100 * 1e18 * 10 * 1e8 / 1e18 = 1000 * 1e18
        uint256 amountInUSD = (uint256(_tokenPrice) * _amount) /
            (uint256(10)**_decimals);

        allCampaigns[_campaignId].amountRaised += amountInUSD;

        allCampaigns[_campaignId].amountRaisedPerToken[_payToken] += _amount;

        // If it's the first time the user is donating increment the number of donors
        if (userDonations[msg.sender][_campaignId].amountInUSD == 0)
            nbDonors[_campaignId]++;

        userDonations[msg.sender][_campaignId].amountPerToken[
            _payToken
        ] += _amount;
        userDonations[msg.sender][_campaignId].amountInUSD += amountInUSD;

        // Emit donation event
        emit NewDonation(_campaignId, msg.sender, amountInUSD, _payToken);
    }

    function claimProofOfDonation(uint256 _campaignId)
        external
        exists(_campaignId)
        nonReentrant
    {
        require(allCampaigns[_campaignId].isOver, "Campaign is not over.");
        // require(
        //     userDonations[msg.sender][_campaignId].amountInUSD > 0,
        //     "No PoD to claim."
        // );
        require(!podClaimed[_campaignId][msg.sender], "PoD already claimed.");

        // Mint Raisy NFT
        IRaisyNFT raisyNFT = IRaisyNFT(addressRegistry.raisyNFT());

        IRaisyNFT.DonationInfo memory donationInfo = IRaisyNFT.DonationInfo(
            userDonations[msg.sender][_campaignId].amountInUSD,
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
            !allCampaigns[_campaignId].isOver,
            "Initial funds already claimed."
        );

        IRaisyTokenRegistry tokenRegistry = IRaisyTokenRegistry(
            addressRegistry.tokenRegistry()
        );
        address[] memory enabledTokens = tokenRegistry.getEnabledTokens();

        if (allCampaigns[_campaignId].hasReleaseSchedule) {
            // Trigger state change on RaisyFundsRelease
            uint256 toReleasePct = getNextPctFunds(_campaignId);

            for (uint256 index = 0; index < enabledTokens.length; index++) {
                IERC20 payToken = IERC20(enabledTokens[index]);

                uint256 toReleaseAmount = (allCampaigns[_campaignId]
                    .amountRaisedPerToken[enabledTokens[index]] *
                    toReleasePct) / 10000;

                // Transfer the funds to the campaign's creator
                payToken.safeTransfer(msg.sender, toReleaseAmount);
            }

            uint256 toReleaseAmountUSD = (allCampaigns[_campaignId]
                .amountRaised * toReleasePct) / 10000;
            campaignFundsClaimed[_campaignId] += toReleaseAmountUSD;
        } else {
            campaignFundsClaimed[_campaignId] += allCampaigns[_campaignId]
                .amountRaised;

            for (uint256 index = 0; index < enabledTokens.length; index++) {
                IERC20 payToken = IERC20(enabledTokens[index]);

                // Transfer the funds to the campaign's creator
                payToken.safeTransfer(
                    msg.sender,
                    allCampaigns[_campaignId].amountRaisedPerToken[
                        enabledTokens[index]
                    ]
                );
            }
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

        IRaisyTokenRegistry tokenRegistry = IRaisyTokenRegistry(
            addressRegistry.tokenRegistry()
        );
        address[] memory enabledTokens = tokenRegistry.getEnabledTokens();

        // Trigger state change on RaisyFundsRelease
        uint256 toReleasePct = getNextPctFunds(_campaignId);

        for (uint256 index = 0; index < enabledTokens.length; index++) {
            IERC20 payToken = IERC20(enabledTokens[index]);

            uint256 toReleaseAmount = (allCampaigns[_campaignId]
                .amountRaisedPerToken[enabledTokens[index]] * toReleasePct) /
                10000;

            // Transfer the funds to the campaign's creator
            payToken.safeTransfer(msg.sender, toReleaseAmount);
        }

        campaignFundsClaimed[_campaignId] +=
            (allCampaigns[_campaignId].amountRaised * toReleasePct) /
            10000;

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

    function getFundsBack(uint256 _campaignId, address _payToken)
        external
        exists(_campaignId)
        isOver(_campaignId)
        isSuccess(_campaignId)
        atStage(_campaignId, Stages.Refund)
        hasProofOfDonation(_campaignId)
        nonReentrant
    {
        require(
            userDonations[msg.sender][_campaignId].amountPerToken[_payToken] >
                0,
            "Nothing to withdraw."
        );

        _validPayToken(_payToken);

        IERC20 payToken = IERC20(_payToken);

        uint256 refundAmount = (userDonations[msg.sender][_campaignId]
            .amountPerToken[_payToken] *
            (10000 - campaignSchedule[_campaignId].pctReleased)) / 10000;

        if (refundAmount > 0) {
            userDonations[msg.sender][_campaignId].amountPerToken[
                _payToken
            ] = 0;

            // Transfer the funds back to the user
            payToken.safeTransfer(msg.sender, refundAmount);
        }

        emit Refund(_campaignId, msg.sender, refundAmount, _payToken);
    }

    /// @notice The campaign didn't reach its objective -> the donor can withdraw his funds and claim rewards
    function withdrawFunds(uint256 _campaignId, address _payToken)
        external
        exists(_campaignId)
        isOver(_campaignId)
        nonReentrant
    {
        require(
            allCampaigns[_campaignId].amountRaised <
                allCampaigns[_campaignId].amountToRaise,
            "Campaign has been successful."
        );
        _validPayToken(_payToken);
        require(
            userDonations[msg.sender][_campaignId].amountPerToken[_payToken] >
                0,
            "No more funds to withdraw."
        );

        uint256 refundAmount = userDonations[msg.sender][_campaignId]
            .amountPerToken[_payToken];

        IERC20 payToken = IERC20(_payToken);

        if (refundAmount > 0) {
            userDonations[msg.sender][_campaignId].amountPerToken[
                _payToken
            ] = 0;

            // Transfer the funds back to the user
            payToken.safeTransfer(msg.sender, refundAmount);
        }

        // Claim rewards from the RaisyChef
        IRaisyChef raisyChef = IRaisyChef(addressRegistry.raisyChef());
        raisyChef.claimRewards(msg.sender, _campaignId);

        emit WithdrawFunds(_campaignId, msg.sender, refundAmount, _payToken);
    }

    ///
    /// INTERNAL & VIEW FUNCTIONS
    ///

    // function _sendPayToken(address _to, uint256 _amount, address _payToken) internal {

    // }

    function _validPayToken(address _payToken) internal view {
        require(
            _payToken == address(0) ||
                (addressRegistry.tokenRegistry() != address(0) &&
                    IRaisyTokenRegistry(addressRegistry.tokenRegistry())
                        .enabled(_payToken)),
            "invalid pay token"
        );
    }

    /**
     @notice Method for getting price for pay token
     @param _payToken Paying token
     */
    function getPrice(address _payToken) public view returns (int256, uint8) {
        int256 unitPrice;
        uint8 decimals;
        IRaisyPriceFeed priceFeed = IRaisyPriceFeed(
            addressRegistry.priceFeed()
        );

        if (_payToken == address(0)) {
            (unitPrice, decimals) = priceFeed.getPrice(priceFeed.wAVAX());
        } else {
            (unitPrice, decimals) = priceFeed.getPrice(_payToken);
        }
        if (decimals < 18) {
            unitPrice = unitPrice * (int256(10)**(18 - decimals));
        } else {
            unitPrice = unitPrice / (int256(10)**(decimals - 18));
        }

        return (unitPrice, decimals);
    }

    function getAmountDonated(
        address _donor,
        uint256 _campaignId,
        address _payToken
    ) external view returns (uint256) {
        return userDonations[_donor][_campaignId].amountPerToken[_payToken];
    }
}
