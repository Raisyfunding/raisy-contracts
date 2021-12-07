## `RaisyCampaigns`

Main Contract handling the campaigns' creation and donations


Inherits of upgradeable versions of OZ libraries
interacts with the AddressRegistry / RaisyNFTFactory / RaisyFundsRelease

### `isNotOver(uint256 _campaignId)`

Modifiers



### `isOver(uint256 _campaignId)`





### `exists(uint256 _campaignId)`





### `isSuccess(uint256 _campaignId)`





### `onlyCreator(uint256 _campaignId)`






### `initialize()` (public)

Contract initializer



### `addCampaign(uint256 _duration, uint256 _amountToRaise)` (external)

Add a campaign without any release schedule




### `addCampaign(uint256 _duration, uint256 _amountToRaise, uint256 _nbMilestones, uint256[] _pctReleasePerMilestone)` (external)

Add campaign with a release schedule




### `donate(uint256 _campaignId, uint256 _amount, address _payToken)` (external)

Enable the users to make a donation




### `claimProofOfDonation(uint256 _campaignId)` (external)

enable the user to claim his proof of donation




### `claimInitialFunds(uint256 _campaignId)` (external)

Claim initial funds, changes the stage of the campaign and enable proof of donation.




### `endVoteSession(uint256 _campaignId)` (external)

Ends the vote session, pays the campaign owner or increase the number of unsuccessful votes.




### `askMoreFunds(uint256 _campaignId)` (external)

The creator can come up at anytime during his campaign to ask for more funds


This initializes a vote session in the RaisyFundsRelease contract


### `getFundsBack(uint256 _campaignId, address _payToken)` (external)

Enables an user to get their funds back if the majority voted so.




### `withdrawFunds(uint256 _campaignId, address _payToken)` (external)

The campaign didn't reach its objective -> the donor can withdraw his funds and claim rewards




### `updatePlatformFee(uint256 _platformFee)` (external)

Update platformFee


Only admin

### `_validPayToken(address _payToken)` (internal)

Sees if the Token address is valid




### `getPrice(address _payToken) → int256, uint8` (public)

Method for getting price for pay token
     @param _payToken Address of the token



### `getAmountDonated(address _donor, uint256 _campaignId, address _payToken) → uint256` (external)

Returns the amount Donated by an address for a given token and campaign.





### `CampaignCreated(uint256 id, address creator, uint256 duration, uint256 startBlock, uint256 amountToRaise, bool hasReleaseSchedule)`

Events for the contract



### `NewDonation(uint256 campaignId, address donor, uint256 amount, address payToken)`





### `ProofOfDonationClaimed(uint256 campaignId, address donor, uint256 tokenId)`





### `FundsClaimed(uint256 campaignId, address creator)`





### `PlatformFeeUpdated(uint256 platformFee)`





### `Refund(uint256 campaignId, address user, uint256 refundAmount, address payToken)`





### `WithdrawFunds(uint256 campaignId, address user, uint256 amount, address payToken)`





### `MoreFundsAsked(uint256 campaignId, address creator)`





### `EndVoteSession(uint256 campaignId, uint256 id, uint256 numUnsuccessfulVotes)`






### `Campaign`


uint256 id


address creator


uint256 duration


uint256 startBlock


uint256 amountToRaise


uint256 amountRaised


mapping(address => uint256) amountRaisedPerToken


bool isOver


bool hasReleaseSchedule


### `Donation`


uint256 amountInUSD


mapping(address => uint256) amountPerToken



