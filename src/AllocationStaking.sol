// SPDX-License-Identifier: MIT

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISalesFactory} from "./interfaces/ISalesFactory.sol";

pragma solidity ^0.8.18;

contract AllocationStaking is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    uint256 public constant ACC_ERC20_PRECISION = 1e36;

    //每秒发放的ERC20代币奖励
    uint256 public rewardPerSecond;
    //开始时间
    uint256 public startTimestamp;
    //结束时间
    uint256 public endTimestamp;
    //池子总资金
    uint256 public totalRewards;
    //总分配点数。必须是所有池中所有分配点数的总和。
    uint256 public totalAllocPoint;
    // 已作为奖励支付的总ERC20代币数量。
    uint256 public paidOut;

    IERC20 public erc20;
    ISalesFactory public salesFactory;

    //每个质押LP代币的用户的详细信息。
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    PoolInfo[] public poolInfo;

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
        uint256 tokensUnlockTime; //如果用户已注册参与销售，则返回代币解锁的时间。
        address[] salesRegistered;
    }

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event CompoundedEarnings(address indexed user, uint256 indexed pid, uint256 amountAdded, uint256 totalDeposited);

    error AllocationStaking__SalesFactoryCannotBeZero();
    error AllocationStaking__FarmingEnded();
    error AllocationStaking__SaleNotCreatedThroughFactory();
    error AllocationStaking__TokensAlreadyUnlocked();
    error AllocationStaking__WithdrawAmountExceedsBalance();
    error AllocationStaking__UserDoesNotHaveAnythingStaked();

    // 限制调用仅限于已验证的销售
    modifier onlyVerifiedSales() {
        if (!salesFactory.isSaleCreatedThroughFactory(msg.sender)) {
            revert AllocationStaking__SaleNotCreatedThroughFactory();
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(IERC20 _erc20, uint256 _rewardPerSecond, uint256 _startTimestamp, address _salesFactory)
        public
        initializer
    {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        erc20 = _erc20;
        rewardPerSecond = _rewardPerSecond;
        startTimestamp = _startTimestamp;
        endTimestamp = _startTimestamp;
        salesFactory = ISalesFactory(_salesFactory);
    }

    // 所有者可以在升级某些智能合约的情况下设置销售工厂
    function setSalesFactory(address _salesFactory) external onlyOwner {
        if (_salesFactory == address(0)) {
            revert AllocationStaking__SalesFactoryCannotBeZero();
        }
        salesFactory = ISalesFactory(_salesFactory);
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // 转入资金，开始farming
    function fund(uint256 _amount) public {
        if (block.timestamp > endTimestamp) {
            revert AllocationStaking__FarmingEnded();
        }
        erc20.safeTransferFrom(address(msg.sender), address(this), _amount);
        endTimestamp += _amount / rewardPerSecond;
        totalRewards = totalRewards + _amount;
    }

    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTimestamp = block.timestamp > startTimestamp ? block.timestamp : startTimestamp;
        totalAllocPoint += _allocPoint;
        // Push new PoolInfo
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

    //更新给定池的ERC20分配点数
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint -poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    //查看用户存入的LP代币
    function deposited(uint256 _pid, address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_pid][_user];
        return user.amount;
    }

    //查看用户待领取ERC20代币
    function pending(uint256 _pid, address _user) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accERC20PerShare = pool.accERC20PerShare;

        uint256 lpSupply = pool.totalDeposits;

        if (block.timestamp > pool.lastRewardTimestamp && lpSupply != 0) {
            uint256 lastTimestamp = block.timestamp < endTimestamp ? block.timestamp : endTimestamp;
            uint256 nrOfSeconds = lastTimestamp - pool.lastRewardTimestamp;
            uint256 erc20Reward = nrOfSeconds * rewardPerSecond * pool.allocPoint / totalAllocPoint;
            accERC20PerShare += (erc20Reward * ACC_ERC20_PRECISION / lpSupply);
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

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function setTokensUnlockTime(uint256 _pid, address _user, uint256 _tokensUnlockTime) external onlyVerifiedSales {
        UserInfo storage user = userInfo[_pid][_user];
        // 要求代币当前是解锁状态
        if (user.tokensUnlockTime > block.timestamp) {
            revert AllocationStaking__TokensAlreadyUnlocked();
        }
        user.tokensUnlockTime = _tokensUnlockTime;
        // 将销售添加到用户注册的销售数组中。
        user.salesRegistered.push(msg.sender);
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 lastTimestamp = block.timestamp < endTimestamp ? block.timestamp : endTimestamp;
        if (lastTimestamp <= pool.lastRewardTimestamp) {
            lastTimestamp = pool.lastRewardTimestamp;
        }
        uint256 lpSupply = pool.totalDeposits;
        if (lpSupply == 0) {
            pool.lastRewardTimestamp = lastTimestamp;
            return;
        }
        uint256 nrOfSeconds = lastTimestamp - pool.lastRewardTimestamp;
        uint256 erc20Reward = nrOfSeconds * rewardPerSecond * pool.allocPoint / totalAllocPoint;
        //更新池的累积每份ERC20代币数量。
        pool.accERC20PerShare += erc20Reward * ACC_ERC20_PRECISION / lpSupply;
        // 更新池的上次奖励时间戳。
        pool.lastRewardTimestamp = lastTimestamp;
    }

    //将LP代币存入池子，开始farming
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 depositAmount = _amount;
        updatePool(_pid);

        //如果用户已经在质押，则将待领取的金额转移到用户账户
        if (user.amount > 0) {
            uint256 pendingAmount = user.amount * pool.accERC20PerShare / ACC_ERC20_PRECISION - user.rewardDebt;
            erc20Transfer(msg.sender, pendingAmount);
        }

        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        //将存款添加到总存款中
        pool.totalDeposits += depositAmount;
        // 将存款添加到用户的金额中。
        user.amount += depositAmount;
        //计算奖励债务
        user.rewardDebt = user.amount * pool.accERC20PerShare / ACC_ERC20_PRECISION;
        emit Deposit(msg.sender, _pid, depositAmount);
    }

    // 转移ERC20代币并更新支付所有奖励所需的ERC20代币数量。
    function erc20Transfer(address _to, uint256 _amount) internal {
        erc20.transfer(_to, _amount);
        paidOut += _amount;
    }

    //提取代币
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.tokensUnlockTime > block.timestamp) {
            revert AllocationStaking__TokensAlreadyUnlocked();
        }
        if (user.amount < _amount) {
            revert AllocationStaking__WithdrawAmountExceedsBalance();
        }

        updatePool(_pid);
        //计算用户待领取的数量。
        uint256 pendingAmount = user.amount * pool.accERC20PerShare / ACC_ERC20_PRECISION - user.rewardDebt;

        erc20Transfer(msg.sender, pendingAmount);
        user.amount -= _amount;
        user.rewardDebt = user.amount * pool.accERC20PerShare / ACC_ERC20_PRECISION;
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        pool.totalDeposits -= _amount;
        if (_amount > 0) {
            //重置代币的解锁时间。
            user.tokensUnlockTime = 0;
        }
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // 将收益复利到存款中的函数
    function compound(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.amount <= 0) {
            revert AllocationStaking__UserDoesNotHaveAnythingStaked();
        }
        updatePool(_pid);
        uint256 pendingAmount = user.amount * pool.accERC20PerShare / ACC_ERC20_PRECISION - user.rewardDebt;

        // 增加用户质押的数量。
        user.amount += pendingAmount;
        user.rewardDebt = user.amount * pool.accERC20PerShare / ACC_ERC20_PRECISION;

        //增加池的总存款。
        pool.totalDeposits += pendingAmount;
        emit CompoundedEarnings(msg.sender, _pid, pendingAmount, user.amount);
    }

    //在不考虑奖励的情况下提取。仅限紧急情况。
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.tokensUnlockTime > block.timestamp) {
            revert AllocationStaking__TokensAlreadyUnlocked();
        }
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        // Adapt contract states
        pool.totalDeposits -= user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.tokensUnlockTime = 0;
    }

    // 用于一次性获取传入池ID的多个用户的存款和收益。
    function getPendingAndDepositedForUsers(address[] memory users, uint256 pid)
        external
        view
        returns (uint256[] memory, uint256[] memory)
    {
        uint256[] memory deposits = new uint256[](users.length);
        uint256[] memory earnings = new uint256[](users.length);
        //获取选定用户的存款和收益。
        for (uint256 i = 0; i < users.length; i++) {
            deposits[i] = deposited(pid, users[i]);
            earnings[i] = pending(pid, users[i]);
        }

        return (deposits, earnings);
    }

     function getPoolAllocPoint(uint256 _pid) public view returns(uint256 allocPoint){
         return poolInfo[_pid].allocPoint;
    }

  

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
