## `RaisyFundsRelease`

Smart contract responsible for managing the campaigns' schedule as well as the voting system


Parent of RaisyCampaigns, Will be an implementation of a proxy and therefore upgradeable
Owner is the ProxyAdmin hence the governance (gnosis-snap-safe)

### `atStage(uint256 _campaignId, enum RaisyFundsRelease.Stages _stage)`

Modifiers



### `hasProofOfDonation(uint256 _campaignId)`






### `register(uint256 _campaignId, uint256 _nbMilestones, uint256[] _pctReleasePerMilestone)` (internal)

This function allows to register a schedule for a given campaignId


Internal function called in RaisyCampaigns.sol when the capaign is created


### `getNextPctFunds(uint256 _campaignId) → uint256` (internal)

Gives the next percentage of total funds to be released


Internal function called in RaisyCampaigns.sol to release funds


### `initializeVoteSession(uint256 _campaignId)` (internal)

Starts a vote session to release the next porition of funds


Internal function called by the campaign's owner in RaisyCampaigns.sol to ask for more funds


### `vote(uint256 _campaignId, bool _vote)` (external)

Funders can vote whether they give more funds or not




### `voteRefund(uint256 _campaignId)` (external)





### `updateAddressRegistry(address _registry)` (external)

Update AgoraAddressRegistry contract


Only admin

### `updateVoteSessionDuration(uint256 _duration)` (external)

Update VOTE_SESSION_DURATION (in blocks)


Only admin

### `_getBlock() → uint256` (internal)

View, gives the current block


Function to override for the tests (mockRaisyChef)



### `ScheduleRegistered(uint256 campaignId, uint256 nbMilestones, uint256[] pctReleasePerMilestone)`

Events of the contract



### `AddressRegistryUpdated(address newAddressRegistry)`





### `VoteSessionDurationUpdated(uint256 newAddressRegistry)`





### `VoteSessionInitialized(uint256 campaignId, uint256 id)`





### `NewVote(uint256 campaignId, uint256 id, address voter, int256 voteRatio)`





### `VoteRefund(uint256 campaignId, address voter, uint256 wantsRefundTotal)`






### `Schedule`


uint256 campaignId


uint256 nbMilestones


uint256[] pctReleasePerMilestone


uint256 pctReleased


uint256 wantsRefund


uint8 currentMilestone


enum RaisyFundsRelease.Stages releaseStage


### `VoteSession`


uint256 id


uint256 startBlock


int256 voteRatio


bool inProgress


uint8 numUnsuccessfulVotes



### `Stages`














