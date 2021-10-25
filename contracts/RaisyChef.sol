// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./RaisyToken.sol";

// RaisyChef is the master of the raisy campaigns.
//
// Note that it's ownable and the owner is the RaisyCampaigns contract
//
contract RaisyChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
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
    //An ETH/USDC Oracle (Chainlink)
    address public usdOracle;
    // Dev address.
    address public devaddr;
    // DAO Treasury Address
    address public daotreasuryaddr;
    // RAISY created per block.
    uint256 public REWARD_PER_BLOCK;
    // Bonus multiplier for early JEWEL makers.
    uint256[] public REWARD_MULTIPLIER; // init in constructor function
    uint256[] public HALVING_AT_BLOCK; // init in constructor function
    uint256[] public blockDeltaStartStage;
    uint256[] public blockDeltaEndStage;
    uint256[] public userFeeStage;
    uint256[] public devFeeStage;
    uint256 public FINISH_BONUS_AT_BLOCK;
    uint256 public userDepFee;
    uint256 public devDepFee;

    // @notice The block number when RAISY mining starts.
    uint256 public START_BLOCK;

    // @notice Total raisy staked in all pools
    uint256 public totalRaisyStaked;

    uint256[] public PERCENT_LOCK_BONUS_REWARD; // lock xx% of bounus reward
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
    mapping(IERC20 => bool) public poolExistence;
    // @notice Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

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
        uint256 amount,
        uint256 lockAmount
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
        uint256 _startBlock,
        uint256 _halvingAfterBlock,
        uint256 _userDepFee,
        uint256 _devDepFee,
        uint256[] memory _rewardMultiplier,
        uint256[] memory _blockDeltaStartStage,
        uint256[] memory _blockDeltaEndStage,
        uint256[] memory _userFeeStage,
        uint256[] memory _devFeeStage
    ) public {
        Raisy = _Raisy;
        devaddr = _devaddr;
        daotreasuryaddr = _daotreasuryaddr;
        REWARD_PER_BLOCK = _rewardPerBlock;
        START_BLOCK = _startBlock;
        LOCK_DURATION = _lockDuration;
        userDepFee = _userDepFee;
        devDepFee = _devDepFee;
        REWARD_MULTIPLIER = _rewardMultiplier;
        blockDeltaStartStage = _blockDeltaStartStage;
        blockDeltaEndStage = _blockDeltaEndStage;
        userFeeStage = _userFeeStage;
        devFeeStage = _devFeeStage;
        for (uint256 i = 0; i < REWARD_MULTIPLIER.length - 1; i++) {
            uint256 halvingAtBlock = _halvingAfterBlock
                .mul(i + 1)
                .add(_startBlock)
                .add(1);
            HALVING_AT_BLOCK.push(halvingAtBlock);
        }
        FINISH_BONUS_AT_BLOCK = _halvingAfterBlock
            .mul(REWARD_MULTIPLIER.length - 1)
            .add(_startBlock);
        HALVING_AT_BLOCK.push(uint256(-1));
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new campaign pool. Can only be called by the owner.
    function add(
        uint256 _campaignId,
        uint256 _endBlock
    ) external onlyOwner nonDuplicated(_campaignId) {
        require(
            poolId1[_campaignId] == 0,
            "RaisyChef::add: id already exists"
        );
       
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
        (
            RaisyForFarmer,
            RaisyForDao
        ) = getPoolReward(pool.lastRewardBlock, block.number, pool.daoBonusMultiplier);

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

    // |--------------------------------------|
    // [20, 30, 40, 50, 60, 70, 80, 99999999]
    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        uint256 result = 0;
        if (_from < START_BLOCK) return 0;

        for (uint256 i = 0; i < HALVING_AT_BLOCK.length; i++) {
            uint256 endBlock = HALVING_AT_BLOCK[i];
            if (i > REWARD_MULTIPLIER.length - 1) return 0;

            if (_to <= endBlock) {
                uint256 m = _to.sub(_from).mul(REWARD_MULTIPLIER[i]);
                return result.add(m);
            }

            if (_from < endBlock) {
                uint256 m = endBlock.sub(_from).mul(REWARD_MULTIPLIER[i]);
                _from = endBlock;
                result = result.add(m);
            }
        }

        return result;
    }

    function getLockPercentage(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        uint256 result = 0;
        if (_from < START_BLOCK) return 100;

        for (uint256 i = 0; i < HALVING_AT_BLOCK.length; i++) {
            uint256 endBlock = HALVING_AT_BLOCK[i];
            if (i > PERCENT_LOCK_BONUS_REWARD.length - 1) return 0;

            if (_to <= endBlock) {
                return PERCENT_LOCK_BONUS_REWARD[i];
            }
        }

        return result;
    }

    function getPoolReward(
        uint256 _from,
        uint256 _to,
        uint256 _daoBonusMultiplier
    )
        public
        view
        returns (
            uint256 forFarmer,
            uint256 forDao
        )
    {
        uint256 amount = _to.sub(_from).mul(REWARD_PER_BLOCK).mul(_daoBonusMultiplier);
        uint256 GovernanceTokenCanMint = Raisy.cap().sub(Raisy.totalSupply());

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
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply > 0) {
            uint256 RaisyForFarmer;
            (, RaisyForFarmer, , , ) = getPoolReward(
                pool.lastRewardBlock,
                block.number,
                pool.allocPoint
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

                if(block.number >= pool.endBlock + LOCK_DURATION) {
                  // Transfer all the rewards if the linear vesting is finished
                  rewards = pending;
                } else {
                  // Transfer rewards determined by the linear vesting ratio
                  uint256 unlock_pct = block.number.sub(pool.endBlock).div(LOCK_DURATION);
                  rewards = pending.mul(unlock_pct);
                }

                Raisy.transfer(msg.sender, rewards);

                emit SendGovernanceTokenReward(
                    msg.sender,
                    _pid,
                    rewards
                );
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
    function deposit(
        uint256 _pid,
        uint256 _amount
    ) public nonReentrant {
        require(
            _amount > 0,
            "RaisyChef::deposit: amount must be greater than 0"
        );

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        UserInfo storage devr = userInfo[_pid][devaddr];
        UserGlobalInfo storage refer = userGlobalInfo[_ref];
        UserGlobalInfo storage current = userGlobalInfo[msg.sender];

        current.globalAmount =
            current.globalAmount +
            _amount.mul(userDepFee).div(100);

        // When a user deposits, we need to update the pool and harvest beforehand,
        // since the rates will change.
        updatePool(_pid);
        _harvest(_pid);
        pool.lpToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        if (user.amount == 0) {
            user.rewardDebtAtBlock = block.number;
        }
        user.amount = user.amount.add(
            _amount.sub(_amount.mul(userDepFee).div(10000))
        );
        user.rewardDebt = user.amount.mul(pool.accRaisyPerShare).div(1e12);
        devr.amount = devr.amount.add(
            _amount.sub(_amount.mul(devDepFee).div(10000))
        );
        devr.rewardDebt = devr.amount.mul(pool.accRaisyPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
        if (user.firstDepositBlock > 0) {} else {
            user.firstDepositBlock = block.number;
        }
        user.lastDepositBlock = block.number;
    }

    // Withdraw LP tokens from MasterGardener.
    function withdraw(
        uint256 _pid,
        uint256 _amount,
        address _ref
    ) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        UserGlobalInfo storage refer = userGlobalInfo[_ref];
        UserGlobalInfo storage current = userGlobalInfo[msg.sender];
        require(user.amount >= _amount, "MasterGardener::withdraw: not good");
        if (_ref != address(0)) {
            refer.referrals[msg.sender] = refer.referrals[msg.sender] - _amount;
            refer.globalRefAmount = refer.globalRefAmount - _amount;
        }
        current.globalAmount = current.globalAmount - _amount;

        updatePool(_pid);
        _harvest(_pid);

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            if (user.lastWithdrawBlock > 0) {
                user.blockdelta = block.number - user.lastWithdrawBlock;
            } else {
                user.blockdelta = block.number - user.firstDepositBlock;
            }
            if (
                user.blockdelta == blockDeltaStartStage[0] ||
                block.number == user.lastDepositBlock
            ) {
                //25% fee for withdrawals of LP tokens in the same block this is to prevent abuse from flashloans
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[0]).div(100)
                );
                pool.lpToken.safeTransfer(
                    address(devaddr),
                    _amount.mul(devFeeStage[0]).div(100)
                );
            } else if (
                user.blockdelta >= blockDeltaStartStage[1] &&
                user.blockdelta <= blockDeltaEndStage[0]
            ) {
                //8% fee if a user deposits and withdraws in between same block and 59 minutes.
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[1]).div(100)
                );
                pool.lpToken.safeTransfer(
                    address(devaddr),
                    _amount.mul(devFeeStage[1]).div(100)
                );
            } else if (
                user.blockdelta >= blockDeltaStartStage[2] &&
                user.blockdelta <= blockDeltaEndStage[1]
            ) {
                //4% fee if a user deposits and withdraws after 1 hour but before 1 day.
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[2]).div(100)
                );
                pool.lpToken.safeTransfer(
                    address(devaddr),
                    _amount.mul(devFeeStage[2]).div(100)
                );
            } else if (
                user.blockdelta >= blockDeltaStartStage[3] &&
                user.blockdelta <= blockDeltaEndStage[2]
            ) {
                //2% fee if a user deposits and withdraws between after 1 day but before 3 days.
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[3]).div(100)
                );
                pool.lpToken.safeTransfer(
                    address(devaddr),
                    _amount.mul(devFeeStage[3]).div(100)
                );
            } else if (
                user.blockdelta >= blockDeltaStartStage[4] &&
                user.blockdelta <= blockDeltaEndStage[3]
            ) {
                //1% fee if a user deposits and withdraws after 3 days but before 5 days.
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[4]).div(100)
                );
                pool.lpToken.safeTransfer(
                    address(devaddr),
                    _amount.mul(devFeeStage[4]).div(100)
                );
            } else if (
                user.blockdelta >= blockDeltaStartStage[5] &&
                user.blockdelta <= blockDeltaEndStage[4]
            ) {
                //0.5% fee if a user deposits and withdraws if the user withdraws after 5 days but before 2 weeks.
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[5]).div(1000)
                );
                pool.lpToken.safeTransfer(
                    address(devaddr),
                    _amount.mul(devFeeStage[5]).div(1000)
                );
            } else if (
                user.blockdelta >= blockDeltaStartStage[6] &&
                user.blockdelta <= blockDeltaEndStage[5]
            ) {
                //0.25% fee if a user deposits and withdraws after 2 weeks.
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[6]).div(10000)
                );
                pool.lpToken.safeTransfer(
                    address(devaddr),
                    _amount.mul(devFeeStage[6]).div(10000)
                );
            } else if (user.blockdelta > blockDeltaStartStage[7]) {
                //0.1% fee if a user deposits and withdraws after 4 weeks.
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[7]).div(10000)
                );
                pool.lpToken.safeTransfer(
                    address(devaddr),
                    _amount.mul(devFeeStage[7]).div(10000)
                );
            }
            user.rewardDebt = user.amount.mul(pool.accRaisyPerShare).div(1e12);
            emit Withdraw(msg.sender, _pid, _amount);
            user.lastWithdrawBlock = block.number;
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY. This has the same 25% fee as same block withdrawals to prevent abuse of thisfunction.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        //reordered from Sushi function to prevent risk of reentrancy
        uint256 amountToSend = user.amount.mul(75).div(100);
        uint256 devToSend = user.amount.mul(25).div(100);
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amountToSend);
        pool.lpToken.safeTransfer(address(devaddr), devToSend);
        emit EmergencyWithdraw(msg.sender, _pid, amountToSend);
    }

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

    // Update Finish Bonus Block
    function bonusFinishUpdate(uint256 _newFinish) public onlyOwner {
        FINISH_BONUS_AT_BLOCK = _newFinish;
    }

    // Update Halving At Block
    function halvingUpdate(uint256[] memory _newHalving) public onlyOwner {
        HALVING_AT_BLOCK = _newHalving;
    }

    // Update Liquidityaddr
    function lpUpdate(address _newLP) public onlyOwner {
        liquidityaddr = _newLP;
    }

    // Update comfundaddr
    function comUpdate(address _newCom) public onlyOwner {
        comfundaddr = _newCom;
    }

    // Update founderaddr
    function founderUpdate(address _newFounder) public onlyOwner {
        founderaddr = _newFounder;
    }

    // Update Reward Per Block
    function rewardUpdate(uint256 _newReward) public onlyOwner {
        REWARD_PER_BLOCK = _newReward;
    }

    // Update Rewards Mulitplier Array
    function rewardMulUpdate(uint256[] memory _newMulReward)
        public
        onlyOwner
    {
        REWARD_MULTIPLIER = _newMulReward;
    }

    // Update % lock for general users
    function lockUpdate(uint256[] memory _newlock) public onlyOwner {
        PERCENT_LOCK_BONUS_REWARD = _newlock;
    }

    // Update % lock for dev
    function lockdevUpdate(uint256 _newdevlock) public onlyOwner {
        PERCENT_FOR_DEV = _newdevlock;
    }

    // Update % lock for LP
    function locklpUpdate(uint256 _newlplock) public onlyOwner {
        PERCENT_FOR_LP = _newlplock;
    }

    // Update % lock for COM
    function lockcomUpdate(uint256 _newcomlock) public onlyOwner {
        PERCENT_FOR_COM = _newcomlock;
    }

    // Update % lock for Founders
    function lockfounderUpdate(uint256 _newfounderlock) public onlyOwner {
        PERCENT_FOR_FOUNDERS = _newfounderlock;
    }

    // Update START_BLOCK
    function starblockUpdate(uint256 _newstarblock) public onlyOwner {
        START_BLOCK = _newstarblock;
    }

    function getNewRewardPerBlock(uint256 pid1) public view returns (uint256) {
        uint256 multiplier = getMultiplier(block.number - 1, block.number);
        if (pid1 == 0) {
            return multiplier.mul(REWARD_PER_BLOCK);
        } else {
            return
                multiplier
                    .mul(REWARD_PER_BLOCK)
                    .mul(poolInfo[pid1 - 1].allocPoint)
                    .div(totalAllocPoint);
        }
    }

    function userDelta(uint256 _pid) public view returns (uint256) {
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.lastWithdrawBlock > 0) {
            uint256 estDelta = block.number - user.lastWithdrawBlock;
            return estDelta;
        } else {
            uint256 estDelta = block.number - user.firstDepositBlock;
            return estDelta;
        }
    }

    function reviseWithdraw(
        uint256 _pid,
        address _user,
        uint256 _block
    ) public onlyOwner {
        UserInfo storage user = userInfo[_pid][_user];
        user.lastWithdrawBlock = _block;
    }

    function reviseDeposit(
        uint256 _pid,
        address _user,
        uint256 _block
    ) public onlyOwner {
        UserInfo storage user = userInfo[_pid][_user];
        user.firstDepositBlock = _block;
    }

    function setStageStarts(uint256[] memory _blockStarts)
        public
        onlyOwner
    {
        blockDeltaStartStage = _blockStarts;
    }

    function setStageEnds(uint256[] memory _blockEnds) public onlyOwner {
        blockDeltaEndStage = _blockEnds;
    }

    function setUserFeeStage(uint256[] memory _userFees) public onlyOwner {
        userFeeStage = _userFees;
    }

    function setDevFeeStage(uint256[] memory _devFees) public onlyOwner {
        devFeeStage = _devFees;
    }

    function setDevDepFee(uint256 _devDepFees) public onlyOwner {
        devDepFee = _devDepFees;
    }

    function setUserDepFee(uint256 _usrDepFees) public onlyOwner {
        userDepFee = _usrDepFees;
    }

    function reclaimTokenOwnership(address _newOwner) public onlyOwner {
        Raisy.transferOwnership(_newOwner);
    }
}
