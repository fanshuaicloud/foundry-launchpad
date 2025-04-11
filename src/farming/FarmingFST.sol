// SPDX-License-Identifier: MIT

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

pragma solidity ^0.8.18;

contract FarmingFST is Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant ACC_ERC20_PRECISION = 1e36;

    //每秒发放的ERC20代币奖励
    uint256 public rewardPerSecond;
    //farming开始时间
    uint256 public startTimestamp;
    //farming结束时间
    uint256 public endTimestamp;
    //池子总资金
    uint256 public totalRewards;
    //总分配点数。必须是所有池中所有分配点数的总和。
    uint256 public totalAllocPoint;
    // 已作为奖励支付的总ERC20代币数量。
    uint256 public paidOut;

    //每个质押LP代币的用户的详细信息。
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    PoolInfo[] public poolInfo;
    IERC20 public erc20;

    struct PoolInfo {
        IERC20 lpToken; //LP代币合约地址
        uint256 allocPoint; //分配给这个池的分配点数是多少。每个区块要分配的ERC20代币数量。
        uint256 lastRewardTimestamp; //最后一次ERC20代币分配的时间戳。
        uint256 accERC20PerShare; // 每份累积的ERC20代币数量，乘以1e36。
        uint256 totalDeposits; //当前存入（质押）的代币总量。
    }

    //用户信息
    struct UserInfo {
        uint256 amount; // 用户提供了多少LP代币。
        uint256 rewardDebt; //奖励债务
            //   待领取奖励 = (用户数量 * 池的累积每份ERC20代币数量) - 用户的奖励债务
            //   当用户向池中存入或提取LP代币时，会发生以下情况：
            //   1.池子累积每份ERC20代币数量（和 上次奖励区块）会得到更新。
            //   2.用户会收到发送到其地址的待领取奖励。
            //   3.用户的数量会得到更新。
            //   4.用户的奖励债务会得到更新。
    }

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    error FarmingFST__FarmingEnded();
    error FarmingFST__WithdrawalAmountExceedsDeposit();

    constructor(IERC20 _erc20, uint256 _rewardPerSecond, uint256 _startTimestamp) Ownable(msg.sender) {
        erc20 = _erc20;
        rewardPerSecond = _rewardPerSecond;
        startTimestamp = _startTimestamp;
        endTimestamp = _startTimestamp;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // 转入资金，开始farming
    function fund(uint256 _amount) public {
        if (block.timestamp > endTimestamp) {
            revert FarmingFST__FarmingEnded();
        }
        erc20.safeTransferFrom(address(msg.sender), address(this), _amount);
        endTimestamp += _amount / rewardPerSecond;
        totalRewards = totalRewards + _amount;
    }

    // 添加一个新的lp池.只能管理员调用.
    //不要重复添加相同的LP代币。如果这样做，奖励将会混乱。
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTimestamp = block.timestamp > startTimestamp ? block.timestamp : startTimestamp;
        totalAllocPoint += _allocPoint;
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardTimestamp: lastRewardTimestamp,
                accERC20PerShare: 0,
                totalDeposits: 0
            })
        );
    }

    // 更新给定池的ERC20分配点数
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    //查看用户存入的LP代币
    function deposited(uint256 _pid, address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_pid][_user];
        return user.amount;
    }

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    //查看用户待领取ERC20代币
    function pending(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accERC20PerShare = pool.accERC20PerShare;

        uint256 lpSupply = pool.totalDeposits;

        if (block.timestamp > pool.lastRewardTimestamp && lpSupply != 0) {
            uint256 lastTimestamp = block.timestamp < endTimestamp ? block.timestamp : endTimestamp;
            uint256 timestampToCompare =
                pool.lastRewardTimestamp < endTimestamp ? pool.lastRewardTimestamp : endTimestamp;
            uint256 nrOfSeconds = lastTimestamp - timestampToCompare;
            uint256 erc20Reward = nrOfSeconds * rewardPerSecond * pool.allocPoint / totalAllocPoint;
            accERC20PerShare = accERC20PerShare + (erc20Reward * ACC_ERC20_PRECISION / lpSupply);
        }
        return user.amount * accERC20PerShare / ACC_ERC20_PRECISION - user.rewardDebt;
    }

    //查看farm未领取的累计奖励的视图函数。
    function totalPending() external view returns (uint256) {
        if (block.timestamp <= startTimestamp) {
            return 0;
        }

        uint256 lastTimestamp = block.timestamp < endTimestamp ? block.timestamp : endTimestamp;
        return rewardPerSecond * (lastTimestamp - startTimestamp) - paidOut;
    }

    // 更新给定池的奖励变量，以确保其是最新的。
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 lastTimestamp = block.timestamp < endTimestamp ? block.timestamp : endTimestamp;

        if (lastTimestamp <= pool.lastRewardTimestamp) {
            return;
        }
        uint256 lpSupply = pool.totalDeposits;

        if (lpSupply == 0) {
            pool.lastRewardTimestamp = lastTimestamp;
            return;
        }

        uint256 nrOfSeconds = lastTimestamp - pool.lastRewardTimestamp;
        uint256 erc20Reward = nrOfSeconds * rewardPerSecond * pool.allocPoint / totalAllocPoint;

        pool.accERC20PerShare = pool.accERC20PerShare + (erc20Reward * ACC_ERC20_PRECISION / lpSupply);
        pool.lastRewardTimestamp = block.timestamp;
    }

    //将LP代币存入池子，开始farming
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);

        if (user.amount > 0) {
            uint256 pendingAmount = user.amount * pool.accERC20PerShare / ACC_ERC20_PRECISION - user.rewardDebt;
            erc20Transfer(msg.sender, pendingAmount);
        }

        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        pool.totalDeposits += _amount;

        user.amount += _amount;
        user.rewardDebt = user.amount * pool.accERC20PerShare / ACC_ERC20_PRECISION;
        emit Deposit(msg.sender, _pid, _amount);
    }

    // 包含两个功能，收取奖励，撤回质押
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.amount < _amount) {
            revert FarmingFST__WithdrawalAmountExceedsDeposit();
        }
        updatePool(_pid);

        // 计算奖励
        uint256 pendingAmount = user.amount * pool.accERC20PerShare / ACC_ERC20_PRECISION - user.rewardDebt;

        erc20Transfer(msg.sender, pendingAmount);
        user.amount -= _amount;
        user.rewardDebt = user.amount * pool.accERC20PerShare / ACC_ERC20_PRECISION;
        // 撤回流动性
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        pool.totalDeposits -= _amount;

        emit Withdraw(msg.sender, _pid, _amount);
    }

    //不关心奖励的情况下提取。仅限紧急情况。
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        pool.totalDeposits -= user.amount;
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // 转移ERC20代币并更新支付所有奖励所需的ERC20代币数量。
    function erc20Transfer(address _to, uint256 _amount) internal {
        erc20.transfer(_to, _amount);
        paidOut += _amount;
    }

    function getPoolAllocPoint(uint256 _pid) public view returns(uint256 allocPoint){
         return poolInfo[_pid].allocPoint;
    }

    
}
