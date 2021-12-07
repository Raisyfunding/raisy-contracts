## `RaisyChef`

Manages the staking process of $RSY into each pool which refers to a campaign


Inspired by the masterchef used in yield farming

### `nonDuplicated(uint256 _campaignId)`

Modifiers




### `constructor(contract RaisyToken _Raisy, address _daotreasuryaddr, uint256 _rewardPerBlock, uint256 _lockDuration, uint256 _startBlock)` (public)

Constructor




### `poolLength() → uint256` (external)

View returns the number of pools




### `add(uint256 _campaignId, uint256 _endBlock)` (external)

Add a new campaign pool.


Can only be called by the owner.


### `set(uint256 _pid, uint256 _endBlock, uint256 _daoBonusMultiplier)` (external)

Update the given pool's parameters.


Can only be called by the owner.


### `updatePool(uint256 _pid)` (public)

Update reward variables of the given pool to be up-to-date.


Anyone can call this function


### `getPoolReward(uint256 _from, uint256 _to, uint256 _daoBonusMultiplier) → uint256 forFarmer, uint256 forDao` (public)

View, gives the rewards of the pool




### `pendingReward(uint256 _pid, address _user) → uint256` (external)

View function to see pending RAISY on frontend.




### `claimRewards(address _to, uint256 _pid)` (external)

claims rewards of the farmer




### `_harvest(address _to, uint256 _pid)` (internal)

harvest function, called only after the end of the campaigns, implements the linear vesting


Not a classic harvest function, it is enabled only at the end of the pool farm. Locks a % of reward if it comes from bonus time.


### `getGlobalAmount(address _user) → uint256` (public)

View, gets user's global amount




### `deposit(address _from, uint256 _pid, uint256 _amount)` (external)

Deposit Raisy in a pool to RaisyChef for RAISY allocation.


Only RaisyCampaigns can call this function (owner).
There's no Raisy transfer from RaisyCampaign to this contract, only a structure update.


### `safeRaisyTransfer(address _to, uint256 _amount)` (internal)

Safe Raisy transfer function


Just in case if rounding error causes pool to not have enough Raisys.


### `daoTreasuryUpdate(address _newDaoTreasury)` (public)

Update Address of the DAO treasury


Only Authorized


### `rewardUpdate(uint256 _newReward)` (public)

Update Reward Per Block


Only Authorized


### `starblockUpdate(uint256 _newstarblock)` (public)

Update startBlock


Only owner


### `daoRewardsUpdate(uint256 _newDaoRewardsPercent)` (public)

Update percentForDao


Only Authorized


### `_getBlock() → uint256` (internal)

View, gives the current block


Function to override for the tests (mockRaisyChef)



### `Deposit(address user, uint256 pid, uint256 amount)`

Events



### `Withdraw(address user, uint256 pid, uint256 amount)`





### `EmergencyWithdraw(address user, uint256 pid, uint256 amount)`





### `SendGovernanceTokenReward(address user, uint256 pid, uint256 amount)`






### `UserInfo`


uint256 amount


uint256 rewardDebt


### `UserGlobalInfo`


uint256 globalAmount


### `PoolInfo`


uint256 campaignId


uint256 endBlock


uint256 lastRewardBlock


uint256 accRaisyPerShare


uint256 amountStaked


uint256 daoBonusMultiplier



