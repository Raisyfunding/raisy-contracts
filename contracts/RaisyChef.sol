// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./RaisyToken.sol";

/// @title RaisyChef 
/// @author RaisyFunding
/// @notice Manages the staking process of $RSY into each pool which refers to a campaign
/// @dev Inspired by the masterchef used in yield farming
contract RaisyChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many tokens the user has provided.
        uint256 rewardDebt;
        //
        // We do some fancy math here. Basically, at any point in time, the
        // amount of RAISY
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accRaisyPerShare) - user.rewardDebt

        // In our case there is no user.rewardDebt because all the rewards at generated at once
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

    // Info of each pool.
    struct PoolInfo {
        uint256 campaignId; // ID of the associated campaign
        uint256 endBlock; // Last block number where RAISY distribution ends.
        uint256 lastRewardBlock; // Last block number that RAISY distribution occurs.
        uint256 accRaisyPerShare; // Accumulated RAISY per share, times 1e12. See below.
        uint256 daoBonusMultiplier; // Bonus Multiplier which can be set by the Raisy DAO
    }

    // The RAISY token
    RaisyToken public Raisy;
    // Dev address.
    address public devaddr;
    // DAO Treasury Address
    address public daotreasuryaddr;
    // RAISY created per block.
    uint256 public REWARD_PER_BLOCK;

    // @notice The block number when RAISY mining starts.
    uint256 public START_BLOCK;

    uint256 public PERCENT_FOR_DEV; // dev bounties
    uint256 public PERCENT_FOR_DAO; // DAO Treasury

    // @notice Linear vesting duration on staking rewards
    uint256 public LOCK_DURATION;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // @notice campaignId -> pid
    mapping(uint256 => uint256) public poolId1; // poolId1 starting from 1, subtract 1 before using with poolInfo
    // @notice Info of each user that stakes LP tokens. pid => user address => info
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    mapping(address => UserGlobalInfo) public userGlobalInfo;
    mapping(uint256 => bool) public poolExistence;

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

    modifier nonDuplicated(uint256 _campaignId) {
        require(
            poolExistence[_campaignId] == false,
            "RaisyChef::nonDuplicated: duplicated"
        );
        _;
    }

    constructor(
        RaisyToken _Raisy,
        address _devaddr,
        address _daotreasuryaddr,
        uint256 _rewardPerBlock,
        uint256 _lockDuration,
        uint256 _startBlock
    ) {
        Raisy = _Raisy;
        devaddr = _devaddr;
        daotreasuryaddr = _daotreasuryaddr;
        REWARD_PER_BLOCK = _rewardPerBlock;
        START_BLOCK = _startBlock;
        LOCK_DURATION = _lockDuration;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new campaign pool. Can only be called by the owner.
    function add(uint256 _campaignId, uint256 _endBlock)
        external
        onlyOwner
        nonDuplicated(_campaignId)
    {
        require(poolId1[_campaignId] == 0, "RaisyChef::add: id already exists");

        uint256 lastRewardBlock = block.number > START_BLOCK
            ? block.number
            : START_BLOCK;

        poolId1[_campaignId] = poolInfo.length + 1;

        poolExistence[_campaignId] = true;

        poolInfo.push(
            PoolInfo({
                campaignId: _campaignId,
                endBlock: _endBlock,
                lastRewardBlock: lastRewardBlock,
                accRaisyPerShare: 0,
                daoBonusMultiplier: 1
            })
        );
    }

    // Update the given pool's parameters. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _endBlock,
        uint256 _daoBonusMultiplier
    ) external onlyOwner {
        poolInfo[_pid].endBlock = _endBlock;
        poolInfo[_pid].daoBonusMultiplier = _daoBonusMultiplier;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = Raisy.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 RaisyForFarmer;
        uint256 RaisyForDao;
        (RaisyForFarmer, RaisyForDao) = getPoolReward(
            pool.lastRewardBlock,
            block.number,
            pool.daoBonusMultiplier
        );

        // Mint some new RAISY tokens for the farmer and store them in RaisyChef.
        Raisy.mint(address(this), RaisyForFarmer);

        pool.accRaisyPerShare = pool.accRaisyPerShare.add(
            RaisyForFarmer.mul(1e12).div(lpSupply)
        );

        pool.lastRewardBlock = block.number;

        if (RaisyForDao > 0) {
            Raisy.mint(daotreasuryaddr, RaisyForDao);
        }
    }

    function getPoolReward(
        uint256 _from,
        uint256 _to,
        uint256 _daoBonusMultiplier
    ) public view returns (uint256 forFarmer, uint256 forDao) {
        uint256 amount = _to.sub(_from).mul(REWARD_PER_BLOCK).mul(
            _daoBonusMultiplier
        );
        uint256 GovernanceTokenCanMint = Raisy.maxsupplycap().sub(
            Raisy.totalSupply()
        );

        if (GovernanceTokenCanMint < amount) {
            // If there aren't enough governance tokens left to mint before the cap,
            // just give all of the possible tokens left to the farmer.
            forFarmer = GovernanceTokenCanMint;
            forDao = 0;
        } else {
            // Otherwise, give the farmer their full amount and also give some
            // extra to the dev, LP, com, and founders wallets.
            forDao = amount.mul(PERCENT_FOR_DAO).div(100);
            forFarmer = amount;
        }
    }

    // View function to see pending RAISY on frontend.
    function pendingReward(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRaisyPerShare = pool.accRaisyPerShare;
        uint256 lpSupply = Raisy.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply > 0) {
            uint256 RaisyForFarmer;
            (RaisyForFarmer, ) = getPoolReward(
                pool.lastRewardBlock,
                block.number,
                pool.daoBonusMultiplier
            );
            accRaisyPerShare = accRaisyPerShare.add(
                RaisyForFarmer.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accRaisyPerShare).div(1e12).sub(user.rewardDebt);
    }

    function claimRewards(uint256[] memory _pids) public {
        for (uint256 i = 0; i < _pids.length; i++) {
            claimReward(_pids[i]);
        }
    }

    function claimReward(uint256 _pid) public {
        updatePool(_pid);
        _harvest(_pid);
    }

    // lock a % of reward if it comes from bonus time.
    function _harvest(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(block.number >= pool.endBlock, "Campaign is not over yet.");

        // Only harvest if the user amount is greater than 0.
        if (user.amount > 0) {
            // Calculate the pending reward. This is the user's amount of LP
            // tokens multiplied by the accRaisyPerShare of the pool, minus
            // the user's rewardDebt.
            uint256 pending = user
                .amount
                .mul(pool.accRaisyPerShare)
                .div(1e12)
                .sub(user.rewardDebt);

            // Make sure we aren't giving more tokens than we have in the
            // RaisyChef contract.
            uint256 masterBal = Raisy.balanceOf(address(this));

            if (pending > masterBal) {
                pending = masterBal;
            }

            if (pending > 0) {
                // If the user has a positive pending balance of tokens, transfer
                // those tokens from RaisyChef to their wallet.
                uint256 rewards;

                if (block.number >= pool.endBlock + LOCK_DURATION) {
                    // Transfer all the rewards if the linear vesting is finished
                    rewards = pending;
                } else {
                    // Transfer rewards determined by the linear vesting ratio
                    uint256 unlock_pct = block.number.sub(pool.endBlock).div(
                        LOCK_DURATION
                    );
                    rewards = pending.mul(unlock_pct);
                }

                Raisy.transfer(msg.sender, rewards);

                emit SendGovernanceTokenReward(msg.sender, _pid, rewards);
            }

            // Recalculate the rewardDebt for the user.
            user.rewardDebt = user.amount.mul(pool.accRaisyPerShare).div(1e12);
        }
    }

    function getGlobalAmount(address _user) public view returns (uint256) {
        UserGlobalInfo memory current = userGlobalInfo[_user];
        return current.globalAmount;
    }

    // Deposit Raisy in a pool to RaisyChef for RAISY allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        require(
            _amount > 0,
            "RaisyChef::deposit: amount must be greater than 0"
        );

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        // UserGlobalInfo storage current = userGlobalInfo[msg.sender];

        // When a user deposits, we need to update the pool and harvest beforehand,
        // since the rates will change.
        updatePool(_pid);
        _harvest(_pid);

        IERC20(Raisy).safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );

        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accRaisyPerShare).div(1e12);

        emit Deposit(msg.sender, _pid, _amount);
    }

    // // Withdraw LP tokens from MasterGardener.
    // function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
    //     PoolInfo storage pool = poolInfo[_pid];
    //     UserInfo storage user = userInfo[_pid][msg.sender];
    //     UserGlobalInfo storage current = userGlobalInfo[msg.sender];
    //     require(user.amount >= _amount, "RaisyChef::withdraw: not good");

    //     current.globalAmount = current.globalAmount - _amount;

    //     updatePool(_pid);
    //     _harvest(_pid);

    //     if (_amount > 0) {
    //         user.amount = user.amount.sub(_amount);
    //         if (user.lastWithdrawBlock > 0) {
    //             user.blockdelta = block.number - user.lastWithdrawBlock;
    //         } else {
    //             user.blockdelta = block.number - user.firstDepositBlock;
    //         }
    //         if (
    //             user.blockdelta == blockDeltaStartStage[0] ||
    //             block.number == user.lastDepositBlock
    //         ) {
    //             //25% fee for withdrawals of LP tokens in the same block this is to prevent abuse from flashloans
    //             pool.lpToken.safeTransfer(
    //                 address(msg.sender),
    //                 _amount.mul(userFeeStage[0]).div(100)
    //             );
    //             pool.lpToken.safeTransfer(
    //                 address(devaddr),
    //                 _amount.mul(devFeeStage[0]).div(100)
    //             );
    //         } else if (
    //             user.blockdelta >= blockDeltaStartStage[1] &&
    //             user.blockdelta <= blockDeltaEndStage[0]
    //         ) {
    //             //8% fee if a user deposits and withdraws in between same block and 59 minutes.
    //             pool.lpToken.safeTransfer(
    //                 address(msg.sender),
    //                 _amount.mul(userFeeStage[1]).div(100)
    //             );
    //             pool.lpToken.safeTransfer(
    //                 address(devaddr),
    //                 _amount.mul(devFeeStage[1]).div(100)
    //             );
    //         } else if (
    //             user.blockdelta >= blockDeltaStartStage[2] &&
    //             user.blockdelta <= blockDeltaEndStage[1]
    //         ) {
    //             //4% fee if a user deposits and withdraws after 1 hour but before 1 day.
    //             pool.lpToken.safeTransfer(
    //                 address(msg.sender),
    //                 _amount.mul(userFeeStage[2]).div(100)
    //             );
    //             pool.lpToken.safeTransfer(
    //                 address(devaddr),
    //                 _amount.mul(devFeeStage[2]).div(100)
    //             );
    //         } else if (
    //             user.blockdelta >= blockDeltaStartStage[3] &&
    //             user.blockdelta <= blockDeltaEndStage[2]
    //         ) {
    //             //2% fee if a user deposits and withdraws between after 1 day but before 3 days.
    //             pool.lpToken.safeTransfer(
    //                 address(msg.sender),
    //                 _amount.mul(userFeeStage[3]).div(100)
    //             );
    //             pool.lpToken.safeTransfer(
    //                 address(devaddr),
    //                 _amount.mul(devFeeStage[3]).div(100)
    //             );
    //         } else if (
    //             user.blockdelta >= blockDeltaStartStage[4] &&
    //             user.blockdelta <= blockDeltaEndStage[3]
    //         ) {
    //             //1% fee if a user deposits and withdraws after 3 days but before 5 days.
    //             pool.lpToken.safeTransfer(
    //                 address(msg.sender),
    //                 _amount.mul(userFeeStage[4]).div(100)
    //             );
    //             pool.lpToken.safeTransfer(
    //                 address(devaddr),
    //                 _amount.mul(devFeeStage[4]).div(100)
    //             );
    //         } else if (
    //             user.blockdelta >= blockDeltaStartStage[5] &&
    //             user.blockdelta <= blockDeltaEndStage[4]
    //         ) {
    //             //0.5% fee if a user deposits and withdraws if the user withdraws after 5 days but before 2 weeks.
    //             pool.lpToken.safeTransfer(
    //                 address(msg.sender),
    //                 _amount.mul(userFeeStage[5]).div(1000)
    //             );
    //             pool.lpToken.safeTransfer(
    //                 address(devaddr),
    //                 _amount.mul(devFeeStage[5]).div(1000)
    //             );
    //         } else if (
    //             user.blockdelta >= blockDeltaStartStage[6] &&
    //             user.blockdelta <= blockDeltaEndStage[5]
    //         ) {
    //             //0.25% fee if a user deposits and withdraws after 2 weeks.
    //             pool.lpToken.safeTransfer(
    //                 address(msg.sender),
    //                 _amount.mul(userFeeStage[6]).div(10000)
    //             );
    //             pool.lpToken.safeTransfer(
    //                 address(devaddr),
    //                 _amount.mul(devFeeStage[6]).div(10000)
    //             );
    //         } else if (user.blockdelta > blockDeltaStartStage[7]) {
    //             //0.1% fee if a user deposits and withdraws after 4 weeks.
    //             pool.lpToken.safeTransfer(
    //                 address(msg.sender),
    //                 _amount.mul(userFeeStage[7]).div(10000)
    //             );
    //             pool.lpToken.safeTransfer(
    //                 address(devaddr),
    //                 _amount.mul(devFeeStage[7]).div(10000)
    //             );
    //         }
    //         user.rewardDebt = user.amount.mul(pool.accRaisyPerShare).div(1e12);
    //         emit Withdraw(msg.sender, _pid, _amount);
    //         user.lastWithdrawBlock = block.number;
    //     }
    // }

    // Safe Raisy transfer function, just in case if rounding error causes pool to not have enough Raisys.
    function safeRaisyTransfer(address _to, uint256 _amount) internal {
        uint256 RaisyBal = Raisy.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > RaisyBal) {
            transferSuccess = Raisy.transfer(_to, RaisyBal);
        } else {
            transferSuccess = Raisy.transfer(_to, _amount);
        }
        require(
            transferSuccess,
            "MasterGardener::safeRaisyTransfer: transfer failed"
        );
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public onlyOwner {
        devaddr = _devaddr;
    }

    // Update founderaddr
    function daoTreasuryUpdate(address _newDaoTreasury) public onlyOwner {
        daotreasuryaddr = _newDaoTreasury;
    }

    // Update Reward Per Block
    function rewardUpdate(uint256 _newReward) public onlyOwner {
        REWARD_PER_BLOCK = _newReward;
    }

    // Update START_BLOCK
    function starblockUpdate(uint256 _newstarblock) public onlyOwner {
        START_BLOCK = _newstarblock;
    }
}
