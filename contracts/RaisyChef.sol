// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./RaisyToken.sol";
import "./Authorizable.sol";

/// @title RaisyChef
/// @author RaisyFunding
/// @notice Manages the staking process of $RSY into each pool which refers to a campaign
/// @dev Inspired by the masterchef used in yield farming
contract RaisyChef is Ownable, ReentrancyGuard, Authorizable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /// @notice Info of each user.
    struct UserInfo {
        uint256 amount; // How many tokens the user has provided.
        uint256 rewardDebt;
        //
        // We do some fancy math here. Basically, at any point in time, the
        // amount of RAISY
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accRaisyPerShare) - user.rewardDebt

        // In our case there is no user.rewardDebt because all the rewards are generated at once
        // The user cannot harvest nor withdraw until the rewards have all been generated and
        // the associated campaign is over
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accRaisyPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    struct UserGlobalInfo {
        uint256 globalAmount;
    }

    /// @notice Info of each pool.
    struct PoolInfo {
        uint256 campaignId; // ID of the associated campaign
        uint256 endBlock; // Last block number where RAISY distribution ends.
        uint256 lastRewardBlock; // Last block number that RAISY distribution occurs.
        uint256 accRaisyPerShare; // Accumulated RAISY per share, times 1e18. See below.
        uint256 amountStaked; // Amount of RAISY staked in the pool
        uint256 daoBonusMultiplier; // Bonus Multiplier which can be set by the Raisy DAO
    }

    // The RAISY token
    RaisyToken public Raisy;
    // DAO Treasury Address
    address public daotreasuryaddr;
    // Total Raisy Staked
    uint256 public totalRaisyStaked;
    // RAISY created per block.
    uint256 public rewardPerBlock;

    // @notice The block number when RAISY mining starts.
    uint256 public startBlock;

    uint256 public percentForDao = 1; // Rewards for DAO Treasury

    // @notice Linear vesting duration on staking rewards
    uint256 public lockDuration;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // @notice campaignId -> pid
    mapping(uint256 => uint256) public poolId1; // poolId1 starting from 1, subtract 1 before using with poolInfo
    // @notice Info of each user that stakes LP tokens. pid => user address => info
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    mapping(address => UserGlobalInfo) public userGlobalInfo;
    mapping(uint256 => bool) public poolExistence;

    /// @notice Events
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event SendGovernanceTokenReward(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    /// @notice Modifiers
    modifier nonDuplicated(uint256 _campaignId) {
        require(poolExistence[_campaignId] == false, "RaisyChef::duplicated");
        _;
    }

    /// @notice Constructor
    /// @param _Raisy RaisyToken
    /// @param _daotreasuryaddr Address of the DAO treasury
    /// @param _rewardPerBlock Raisy distributed per block, corresponding to the linear vesting (tokenomics whitepaper)
    /// @param _lockDuration Duration of the locking after the campaign ends
    /// @param _startBlock Start block of farming
    constructor(
        RaisyToken _Raisy,
        address _daotreasuryaddr,
        uint256 _rewardPerBlock,
        uint256 _lockDuration,
        uint256 _startBlock
    ) {
        Raisy = _Raisy;
        daotreasuryaddr = _daotreasuryaddr;
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        lockDuration = _lockDuration;
    }

    /// @notice View returns the number of pools
    /// @return Length of the pool
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /// @notice Add a new campaign pool.
    /// @dev Can only be called by the owner.
    /// @param _campaignId Id of the campaign
    /// @param _endBlock End of the rewards (end of the campaign)
    function add(uint256 _campaignId, uint256 _endBlock)
        external
        onlyOwner
        nonDuplicated(_campaignId)
    {
        uint256 lastRewardBlock = _getBlock() > startBlock
            ? _getBlock()
            : startBlock;

        poolId1[_campaignId] = poolInfo.length + 1;

        poolExistence[_campaignId] = true;

        poolInfo.push(
            PoolInfo({
                campaignId: _campaignId,
                endBlock: _endBlock,
                lastRewardBlock: lastRewardBlock,
                accRaisyPerShare: 0,
                amountStaked: 0,
                daoBonusMultiplier: 1
            })
        );
    }

    /// @notice Update the given pool's parameters.
    /// @dev Can only be called by the owner.
    /// @param _pid Id of the pool in the RaisyChef contract (!=campaignId)
    /// @param _endBlock End of the rewards (end of the campaign)
    /// @param _daoBonusMultiplier Multiplier voted by the DAO, highest APR for this pool
    function set(
        uint256 _pid,
        uint256 _endBlock,
        uint256 _daoBonusMultiplier
    ) external onlyOwner {
        require(_endBlock > _getBlock(), "End block in the past");
        poolInfo[_pid].endBlock = _endBlock;
        poolInfo[_pid].daoBonusMultiplier = _daoBonusMultiplier;
    }

    /// @notice Update reward variables of the given pool to be up-to-date.
    /// @dev Anyone can call this function
    /// @param _pid Id of the pool in the RaisyChef contract (!=campaignId)
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];

        if (_getBlock() <= pool.lastRewardBlock) {
            return;
        }

        // Amount of $RSY staked in the pool
        uint256 lpSupply = pool.amountStaked;

        if (lpSupply == 0) {
            pool.lastRewardBlock = _getBlock();
            return;
        }

        uint256 raisyForFarmer;
        uint256 raisyForDao;

        (raisyForFarmer, raisyForDao) = getPoolReward(
            pool.lastRewardBlock,
            _getBlock(),
            pool.daoBonusMultiplier
        );

        // Mint some new RAISY tokens for the farmer and store them in RaisyChef.
        Raisy.mint(address(this), raisyForFarmer); //Trusted external call

        pool.accRaisyPerShare = pool.accRaisyPerShare.add(
            raisyForFarmer.mul(1e18).div(totalRaisyStaked)
        );

        pool.lastRewardBlock = _getBlock();

        if (raisyForDao > 0) {
            Raisy.mint(daotreasuryaddr, raisyForDao); //Trusted external call
        }
    }

    /// @notice View, gives the rewards of the pool
    /// @param _from StartBlock of the calculation window
    /// @param _to EndBlock of the calculation window
    /// @param _daoBonusMultiplier Multiplier voted by the DAO, highest APR for this pool
    /// @return forFarmer The amount of Raisy for the farmer
    /// @return forDao The amount of Raisy for the DAO treasury
    function getPoolReward(
        uint256 _from,
        uint256 _to,
        uint256 _daoBonusMultiplier
    ) public view returns (uint256 forFarmer, uint256 forDao) {
        uint256 amount = _to.sub(_from).mul(rewardPerBlock).mul(
            _daoBonusMultiplier
        );
        uint256 governanceTokenCanMint = Raisy.maxsupplycap().sub( //Trusted external call
            Raisy.totalSupply() //Trusted external call
        );

        if (governanceTokenCanMint < amount) {
            // If there aren't enough governance tokens left to mint before the cap,
            // just give all of the possible tokens left to the farmer.
            forFarmer = governanceTokenCanMint;
            forDao = 0;
        } else {
            // Otherwise, give the farmer their full amount and also give some
            // extra to the dao.
            forDao = amount.mul(percentForDao).div(100);
            forFarmer = amount;
        }
    }

    /// @notice View function to see pending RAISY on frontend.
    /// @param _pid Id of the pool in the RaisyChef contract (!=campaignId)
    /// @param _user Address of the farmer
    /// @return Pending rewards for a farmer
    function pendingReward(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRaisyPerShare = pool.accRaisyPerShare;
        uint256 lpSupply = pool.amountStaked;

        if (_getBlock() > pool.lastRewardBlock && lpSupply > 0) {
            uint256 raisyForFarmer;
            (raisyForFarmer, ) = getPoolReward(
                pool.lastRewardBlock,
                _getBlock(),
                pool.daoBonusMultiplier
            );
            accRaisyPerShare = accRaisyPerShare.add(
                raisyForFarmer.mul(1e18).div(totalRaisyStaked)
            );
        }

        return user.amount.mul(accRaisyPerShare).div(1e18).sub(user.rewardDebt);
    }

    /// @notice claims rewards of the farmer
    /// @param _to Address of the farmer who wants to claim their rewards
    /// @param _pid Id of the pool in the RaisyChef contract (!=campaignId)
    function claimRewards(address _to, uint256 _pid) external {
        updatePool(_pid);
        _harvest(_to, _pid);
    }

    /// @notice harvest function, called only after the end of the campaigns, implements the linear vesting
    /// @dev Not a classic harvest function, it is enabled only at the end of the pool farm. Locks a % of reward if it comes from bonus time.
    /// @param _to Address of the farmer who harvests
    /// @param _pid Id of the pool in the RaisyChef contract (!=campaignId)
    function _harvest(address _to, uint256 _pid) internal nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(_getBlock() >= pool.endBlock, "Campaign is not over yet.");

        // Only harvest if the user amount is greater than 0.
        if (user.amount > 0) {
            // Calculate the pending reward. This is the user's amount of LP
            // tokens multiplied by the accRaisyPerShare of the pool, minus
            // the user's rewardDebt.
            uint256 pending = user
                .amount
                .mul(pool.accRaisyPerShare)
                .div(1e18)
                .sub(user.rewardDebt);

            // Make sure we aren't giving more tokens than we have in the
            // RaisyChef contract.
            uint256 masterBal = Raisy.balanceOf(address(this)); //Trusted external call

            if (pending > masterBal) {
                pending = masterBal;
            }

            if (pending > 0) {
                // If the user has a positive pending balance of tokens, transfer
                // those tokens from RaisyChef to their wallet.
                uint256 rewards;

                if (_getBlock() >= pool.endBlock + lockDuration) {
                    // Transfer all the rewards if the linear vesting is finished
                    rewards = pending;
                } else {
                    // Transfer rewards determined by the linear vesting ratio
                    uint256 blocksPassed = _getBlock().sub(pool.endBlock);
                    rewards = pending.mul(blocksPassed).div(lockDuration);
                }

                safeRaisyTransfer(_to, rewards);

                emit SendGovernanceTokenReward(_to, _pid, rewards);
            }

            // Recalculate the rewardDebt for the user.
            user.rewardDebt = user.amount.mul(pool.accRaisyPerShare).div(1e18);
        }
    }

    /// @notice View, gets user's global amount
    /// @param _user Address of the farmer
    /// @return the global amount of the user
    function getGlobalAmount(address _user) public view returns (uint256) {
        UserGlobalInfo memory current = userGlobalInfo[_user];
        return current.globalAmount;
    }

    /// @notice Deposit Raisy in a pool to RaisyChef for RAISY allocation.
    /// @dev Only RaisyCampaigns can call this function (owner).
    /// @dev There's no Raisy transfer from RaisyCampaign to this contract, only a structure update.
    /// @param _from address who made the deposit
    /// @param _pid Id of the pool in the RaisyChef contract (!=campaignId)
    /// @param _amount Amount of the deposit
    function deposit(
        address _from,
        uint256 _pid,
        uint256 _amount
    ) external nonReentrant onlyOwner {
        require(_amount > 0, "Amount must be greater than 0");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_from];
        UserGlobalInfo storage current = userGlobalInfo[_from];

        // When a user deposits, we need to update the pool and harvest beforehand,
        // since the rates will change.
        // _harvest(_pid);

        // IERC20(Raisy).safeTransferFrom(
        //     _from,
        //     address(this),
        //     _amount
        // );

        updatePool(_pid);

        // Update staking amounts
        totalRaisyStaked += _amount;
        pool.amountStaked += _amount;

        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accRaisyPerShare).div(1e18);
        current.globalAmount = current.globalAmount.add(_amount);

        emit Deposit(_from, _pid, _amount);
    }

    /// @notice Safe Raisy transfer function
    /// @dev Just in case if rounding error causes pool to not have enough Raisys.
    /// @param _to Address of the reciever
    /// @param _amount Amount of the transfer
    function safeRaisyTransfer(address _to, uint256 _amount) internal {
        uint256 raisyBal = Raisy.balanceOf(address(this)); //Trusted external call
        bool transferSuccess = false;
        if (_amount > raisyBal) {
            transferSuccess = Raisy.transfer(_to, raisyBal); //Trusted external call
        } else {
            transferSuccess = Raisy.transfer(_to, _amount); //Trusted external call
        }
        require(transferSuccess, "RaisyChef::Transfer failed");
    }

    /// @notice Update Address of the DAO treasury
    /// @dev Only Authorized
    /// @param _newDaoTreasury New address of the DAO treasury
    function daoTreasuryUpdate(address _newDaoTreasury) public onlyAuthorized {
        daotreasuryaddr = _newDaoTreasury;
    }

    /// @notice Update Reward Per Block
    /// @dev Only Authorized
    /// @param _newReward New emission rate of Raisy
    function rewardUpdate(uint256 _newReward) public onlyAuthorized {
        rewardPerBlock = _newReward;
    }

    /// @notice Update startBlock
    /// @dev Only owner
    /// @param _newstarblock New number for the start block
    function starblockUpdate(uint256 _newstarblock) public onlyOwner {
        startBlock = _newstarblock;
    }

    /// @notice Update percentForDao
    /// @dev Only Authorized
    /// @param _newDaoRewardsPercent New percentage for DAO treasury
    function daoRewardsUpdate(uint256 _newDaoRewardsPercent)
        public
        onlyAuthorized
    {
        percentForDao = _newDaoRewardsPercent;
    }

    /// @notice View, gives the current block
    /// @dev Function to override for the tests (mockRaisyChef)
    /// @return Current block
    function _getBlock() internal view virtual returns (uint256) {
        return block.number;
    }
}
