// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {IAllocationStaking} from "../interfaces/IAllocationStaking.sol";
import {ISalesFactory} from "../interfaces/ISalesFactory.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract FSSale is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    using Math for uint256;

    IAllocationStaking public allocationStakingContract;
    ISalesFactory public factory;
    // 部分解锁的时间集合
    uint256[] public vestingPortionsUnlockTime;
    // 用户可以提取的参与百分比
    uint256[] public vestingPercentPerPortion;
    //部分解锁百分比精度
    uint256 public portionVestingPrecision;
    //最大偏移量
    uint256 public maxVestingTimeShift;
    Sale public sale;
    // 参与销售的用户数量。
    uint256 public numberOfParticipants;
    Registration public registration;

    //用户是否已注册
    mapping(address => bool) public isRegistered;
    //用户是否已参与
    mapping(address => bool) public isParticipated;
    //用户参与信息
    mapping(address => Participation) public userToParticipation;

    struct Sale {
        IERC20 token;
        //是否初始化
        bool isCreated;
        // 收益是否提现
        bool earningsWithdrawn;
        // 剩余部分是否已提取
        bool leftoverWithdrawn;
        // 代币是否已存入
        bool tokensDeposited;
        // 销售方地址
        address saleOwner;
        // 代币的以太坊价格
        uint256 tokenPriceInETH;
        // 代币的销售数量
        uint256 amountOfTokensToSell;
        // 正在出售的代币总数
        uint256 totalTokensSold;
        // 已筹集的总ETH
        uint256 totalETHRaised;
        //销售开始时间
        uint256 saleStart;
        // 销售结束时间
        uint256 saleEnd;
        // 代币可提取时间
        uint256 tokensUnlockTime;
        // 最大参与量
        uint256 maxParticipation;
    }

    struct Registration {
        //注册开始时间
        uint256 registrationTimeStarts;
        uint256 registrationTimeEnds;
        //注册结束时间
        //已注册用户的总数量
        uint256 numberOfRegistrants;
    }

    struct Participation {
        uint256 amountBought;
        uint256 amountETHPaid;
        uint256 timeParticipated;
        bool[] isPortionWithdrawn;
    }

    event SaleCreated(
        address indexed saleOwner, uint256 tokenPriceInETH, uint256 amountOfTokensToSell, uint256 saleEnd
    );
    event RegistrationTimeSet(uint256 indexed registrationTimeStarts, uint256 indexed registrationTimeEnds);
    event StartTimeSet(uint256 indexed startTime);
    event UserRegistered(address indexed user);
    event TokenPriceSet(uint256 indexed newPrice);
    event MaxParticipationSet(uint256 indexed maxParticipation);
    event TokensSold(address indexed user, uint256 indexed amount);
    event TokensWithdrawn(address indexed user, uint256 indexed amount);

    error FSSale__NumMustMoreThanZero();
    error FSSale__NumMustLessThanMax();
    error FSSale__ArrayLengthNotMatch();
    error FSSale__AlreadySet();
    error FSSale__PercentDistributionIssue();
    error FSSale__TimeMustMoreThanNow();
    error FSSale__NumMustMoreThanOnehundred();
    error FSSale__AddressCannotBeZero();
    error FSSale__StartTimeMustLessThanEndTime();
    error FSSale__RegistrationTimeMustLessThanSaleEnd();
    error FSSale__RegistrationTimeMustLessThanSaleStart();
    error FSSale__SaleNotCreated();
    error FSSale__StartTimeMustGreaterThanRegistrationTimeEnds();
    error FSSale__StartTimeMustLessThanSaleEnd();
    error FSSale__RegistrationTimeOut();
    error FSSale__SignatureNotMatch();
    error FSSale__AlreadyRegistered();
    error FSSale__SaleAlreadyStarted();
    error FSSale__AddressMustBeSaleOwner();
    error FSSale__DepositCanBeDoneOnlyOnce();
    error FSSale__ParticipationAmountExceedsMaximum();
    error FSSale__UserNotRegistered();
    error FSSale__SaleNotStarted();
    error FSSale__SaleEnded();
    error FSSale__AlreadyParticipated();
    error FSSale__ContractCallNotAllowed();
    error FSSale__CanNotBuyZeroTokens();
    error FSSale__CanNotBuyMoreThanAllocation();
    error FSSale__NotUnlockTime();
    error FSSale__PortionIdOutOfRange();
    error FSSale__TokenAlreadyWithdrawn();
    error FSSale_SaleNotEnded();
    error FSSale_CantWithdrawTwice();

    modifier onlySaleOwner() {
        if (msg.sender != sale.saleOwner) {
            revert FSSale__AddressMustBeSaleOwner();
        }
        _;
    }

    constructor(address _allocationStaking) Ownable(msg.sender) {
        factory = ISalesFactory(msg.sender);
        allocationStakingContract = IAllocationStaking(_allocationStaking);
    }

    //设置代币在不同时间段的解锁时间以及每个时间段可以解锁的代币百分比，这个方法只能由管理员调用，并且只能在归属参数尚未设置的情况下调用。
    function setVestingParams(
        uint256[] memory _unlockingTimes,
        uint256[] memory _percents,
        uint256 _maxVestingTimeShift
    ) external onlyOwner {
        if (vestingPercentPerPortion.length > 0 || vestingPortionsUnlockTime.length > 0) {
            revert FSSale__AlreadySet();
        }
        //两个数组长度应该一致
        if (_unlockingTimes.length != _percents.length) {
            revert FSSale__ArrayLengthNotMatch();
        }
        //最大偏移量不能小于0
        if (_maxVestingTimeShift <= 0) {
            revert FSSale__NumMustMoreThanZero();
        }
        //最大偏移量不能大于30天
        if (_maxVestingTimeShift > 30) {
            revert FSSale__NumMustLessThanMax();
        }
        maxVestingTimeShift = _maxVestingTimeShift;

        uint256 sum;

        for (uint256 i = 0; i < _unlockingTimes.length; i++) {
            vestingPortionsUnlockTime.push(_unlockingTimes[i]);
            vestingPercentPerPortion.push(_percents[i]);
            sum += _percents[i];
        }
        if (sum != portionVestingPrecision) {
            revert FSSale__PercentDistributionIssue();
        }
    }

    //调整解锁时间（vestingPortionsUnlockTime）的偏移量，这个方法只能由管理员调用，并且只能只能调用一次.
    function shiftVestingUnlockingTimes(uint256 timeToShift) external onlyOwner {
        if (timeToShift < 0) {
            revert FSSale__NumMustMoreThanZero();
        }
        if (timeToShift > maxVestingTimeShift) {
            revert FSSale__NumMustLessThanMax();
        }
        // 通过归零防止重复调用
        maxVestingTimeShift = 0;
        uint256 lenght = vestingPortionsUnlockTime.length;
        for (uint256 i = 0; i < lenght; i++) {
            vestingPortionsUnlockTime[i] += timeToShift;
        }
    }

    //设置销售参数，这个方法只能由管理员调用，并且只能在销售尚未创建的情况下调用。
    function setSaleParams(
        address _token,
        address _saleOwner,
        uint256 _tokenPriceInETH,
        uint256 _amountOfTokensToSell,
        uint256 _saleEnd,
        uint256 _tokensUnlockTime,
        uint256 _portionVestingPrecision,
        uint256 _maxParticipation
    ) external onlyOwner {
        if (sale.isCreated) {
            revert FSSale__SaleNotCreated();
        }
        if (_tokenPriceInETH <= 0 || _amountOfTokensToSell <= 0 || _maxParticipation <= 0) {
            revert FSSale__NumMustMoreThanZero();
        }
        if (_tokensUnlockTime <= block.timestamp || _saleEnd <= block.timestamp) {
            revert FSSale__TimeMustMoreThanNow();
        }
        if (_portionVestingPrecision < 100) {
            revert FSSale__NumMustMoreThanOnehundred();
        }
        sale.isCreated = true;
        sale.token = IERC20(_token);
        sale.saleOwner = _saleOwner;
        sale.tokenPriceInETH = _tokenPriceInETH;
        sale.amountOfTokensToSell = _amountOfTokensToSell;
        sale.saleEnd = _saleEnd;
        sale.tokensUnlockTime = _tokensUnlockTime;
        sale.maxParticipation = _maxParticipation;

        portionVestingPrecision = _portionVestingPrecision;
        //记录事件
        emit SaleCreated(sale.saleOwner, sale.tokenPriceInETH, sale.amountOfTokensToSell, sale.saleEnd);
    }

    //
    function setSaleToken(address saleToken) external onlyOwner {
        if (saleToken == address(0)) {
            revert FSSale__AddressCannotBeZero();
        }
        sale.token = IERC20(saleToken);
    }

    //设置售出时间，这个方法只能由管理员调用，并且只能在销售尚未创建的情况下调用。
    function setRegistrationTime(uint256 _registrationTimeStarts, uint256 _registrationTimeEnds) external onlyOwner {
        if (!sale.isCreated) {
            revert FSSale__SaleNotCreated();
        }
        if (registration.registrationTimeStarts != 0) {
            revert FSSale__AlreadySet();
        }
        if (_registrationTimeStarts <= block.timestamp) {
            revert FSSale__TimeMustMoreThanNow();
        }
        if (_registrationTimeEnds < _registrationTimeStarts) {
            revert FSSale__StartTimeMustLessThanEndTime();
        }
        if (_registrationTimeEnds > sale.saleEnd) {
            revert FSSale__RegistrationTimeMustLessThanSaleEnd();
        }

        if (sale.saleStart > 0 && _registrationTimeEnds > sale.saleStart) {
            revert FSSale__RegistrationTimeMustLessThanSaleStart();
        }

        registration.registrationTimeStarts = _registrationTimeStarts;
        registration.registrationTimeEnds = _registrationTimeEnds;

        emit RegistrationTimeSet(registration.registrationTimeStarts, registration.registrationTimeEnds);
    }

    //设置销售开始时间，这个方法只能由管理员调用，并且只能在销售尚未创建的情况下调用。
    function setSaleStart(uint256 starTime) external onlyOwner {
        if (!sale.isCreated) {
            revert FSSale__SaleNotCreated();
        }
        if (sale.saleStart != 0) {
            revert FSSale__AlreadySet();
        }
        if (starTime < registration.registrationTimeEnds) {
            revert FSSale__StartTimeMustGreaterThanRegistrationTimeEnds();
        }
        if (starTime > sale.saleEnd) {
            revert FSSale__StartTimeMustLessThanSaleEnd();
        }
        if (starTime < block.timestamp) {
            revert FSSale__TimeMustMoreThanNow();
        }
        sale.saleStart = starTime;
        emit StartTimeSet(sale.saleStart);
    }
    //用户参与代币销售前的注册函数

    function registerForSale(bytes memory signature, uint256 pid) external {
        if (
            block.timestamp < registration.registrationTimeStarts || block.timestamp > registration.registrationTimeEnds
        ) {
            revert FSSale__RegistrationTimeOut();
        }
        if (!checkRegistrationSignature(signature, msg.sender)) {
            revert FSSale__SignatureNotMatch();
        }
        if (isRegistered[msg.sender]) {
            revert FSSale__AlreadyRegistered();
        }
        isRegistered[msg.sender] = true;

        // 锁定用户的质押
        allocationStakingContract.setTokensUnlockTime(pid, msg.sender, sale.saleEnd);

        // 增加注册用户数量
        registration.numberOfRegistrants++;

        emit UserRegistered(msg.sender);
    }

    //验证用户注册请求签名有效性
    function checkRegistrationSignature(bytes memory signature, address user) public view returns (bool) {
        bytes32 hash = keccak256(abi.encode(user, address(this)));
        address messageHash = ECDSA.recover(hash, signature);
        return (messageHash == this.owner());
    }

    function checkParticipationSignature(bytes memory signature, address user, uint256 amount)
        public
        view
        returns (bool)
    {
        return (this.owner() == getParticipationSigner(signature, user, amount));
    }

    //更新销售价格
    function updateTokenPriceInETH(uint256 price) external onlyOwner {
        if (price <= 0) {
            revert FSSale__NumMustMoreThanZero();
        }
        sale.tokenPriceInETH = price;
        emit TokenPriceSet(price);
    }

    //延时销售
    function postponeSale(uint256 timeToShift) external onlyOwner {
        if (block.timestamp > sale.saleStart) {
            revert FSSale__SaleAlreadyStarted();
        }

        //  延迟注册开始时间
        sale.saleStart += timeToShift;
        if (sale.saleStart + timeToShift > sale.saleEnd) {
            revert FSSale__StartTimeMustLessThanEndTime();
        }
    }

    function extendRegistrationPeriod(uint256 timeToAdd) external onlyOwner {
        if (registration.registrationTimeEnds + timeToAdd > sale.saleEnd) {
            revert FSSale__RegistrationTimeMustLessThanSaleEnd();
        }

        registration.registrationTimeEnds += timeToAdd;
    }

    function setCap(uint256 cap) external onlyOwner {
        if (block.timestamp > sale.saleStart) {
            revert FSSale__SaleAlreadyStarted();
        }
        if (cap <= 0) {
            revert FSSale__NumMustMoreThanZero();
        }
        sale.maxParticipation = cap;

        emit MaxParticipationSet(sale.maxParticipation);
    }
    //销售方存入待售代币

    function depositTokens() external onlySaleOwner {
        if (sale.tokensDeposited) {
            revert FSSale__DepositCanBeDoneOnlyOnce();
        }
        sale.tokensDeposited = true;
        sale.token.safeTransferFrom(msg.sender, address(this), sale.amountOfTokensToSell);
    }

    // Function to participate in the sales
    function participate(bytes memory signature, uint256 amount) external payable {
        if (amount > sale.maxParticipation) {
            revert FSSale__ParticipationAmountExceedsMaximum();
        }

        if (!isRegistered[msg.sender]) {
            revert FSSale__UserNotRegistered();
        }
        if (!checkParticipationSignature(signature, msg.sender, amount)) {
            revert FSSale__SignatureNotMatch();
        }
        if (block.timestamp < sale.saleStart) {
            revert FSSale__SaleNotStarted();
        }
        if (block.timestamp > sale.saleEnd) {
            revert FSSale__SaleEnded();
        }

        if (isParticipated[msg.sender]) {
            revert FSSale__AlreadyParticipated();
        }
        if (msg.sender != tx.origin) {
            revert FSSale__ContractCallNotAllowed();
        }
        if (sale.tokenPriceInETH <= 0) {
            revert FSSale__NumMustMoreThanZero();
        }
        uint256 amountOfTokensBuying =
            (msg.value) * (uint256(10) ** IERC20Metadata(address(sale.token)).decimals()) / (sale.tokenPriceInETH);

        if (amountOfTokensBuying <= 0) {
            revert FSSale__CanNotBuyZeroTokens();
        }
        if (amountOfTokensBuying > amount) {
            revert FSSale__CanNotBuyMoreThanAllocation();
        }

        sale.totalTokensSold = sale.totalTokensSold + amountOfTokensBuying;

        sale.totalETHRaised = sale.totalETHRaised + msg.value;

        bool[] memory _isPortionWithdrawn = new bool[](vestingPortionsUnlockTime.length);

        Participation memory p = Participation({
            amountBought: amountOfTokensBuying,
            amountETHPaid: msg.value,
            timeParticipated: block.timestamp,
            isPortionWithdrawn: _isPortionWithdrawn
        });

        userToParticipation[msg.sender] = p;
        isParticipated[msg.sender] = true;
        numberOfParticipants++;
        emit TokensSold(msg.sender, amountOfTokensBuying);
    }

    /// 用户可以领取他们的参与份额
    function withdrawTokens(uint256 portionId) external {
        if (block.timestamp < sale.tokensUnlockTime) {
            revert FSSale__NotUnlockTime();
        }
        if (portionId >= vestingPercentPerPortion.length) {
            revert FSSale__PortionIdOutOfRange();
        }
        Participation storage p = userToParticipation[msg.sender];

        if (vestingPortionsUnlockTime[portionId] > block.timestamp) {
            revert FSSale__NotUnlockTime();
        }
        if (p.isPortionWithdrawn[portionId]) {
            revert FSSale__TokenAlreadyWithdrawn();
        }
        p.isPortionWithdrawn[portionId] = true;
        uint256 amountWithdrawing = p.amountBought * vestingPercentPerPortion[portionId] / (portionVestingPrecision);
        if (amountWithdrawing > 0) {
            sale.token.safeTransfer(msg.sender, amountWithdrawing);
            emit TokensWithdrawn(msg.sender, amountWithdrawing);
        }
    }

    //允许用户一次性提取多个未解锁部分
    function withdrawMultiplePortions(uint256[] calldata portionIds) external {
        uint256 totalToWithdraw = 0;
        Participation storage p = userToParticipation[msg.sender];
        for (uint256 i = 0; i < portionIds.length; i++) {
            uint256 portionId = portionIds[i];
            if (portionId >= vestingPercentPerPortion.length) {
                revert FSSale__PortionIdOutOfRange();
            }
            if (!p.isPortionWithdrawn[portionId] && vestingPortionsUnlockTime[portionId] <= block.timestamp) {
                p.isPortionWithdrawn[portionId] = true;
                uint256 amountWithdrawing =
                    p.amountBought * (vestingPercentPerPortion[portionId]) / (portionVestingPrecision);
                // 提取在该部分解锁的百分比
                totalToWithdraw += amountWithdrawing;
            }
        }
        if (totalToWithdraw > 0) {
            sale.token.safeTransfer(msg.sender, totalToWithdraw);
            emit TokensWithdrawn(msg.sender, totalToWithdraw);
        }
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}(new bytes(0));
        require(success);
    }

    //提取所有收益和剩余部分
    function withdrawEarningsAndLeftover() external onlySaleOwner {
        withdrawEarningsInternal();
        withdrawLeftoverInternal();
    }

    //仅提取收益
    function withdrawEarnings() external onlySaleOwner {
        withdrawEarningsInternal();
    }

    //仅提取剩余部分
    function withdrawLeftover() external onlySaleOwner {
        withdrawLeftoverInternal();
    }

    //提取收益
    function withdrawEarningsInternal() internal {
        if (block.timestamp < sale.saleEnd) {
            revert FSSale_SaleNotEnded();
        }
        if (sale.earningsWithdrawn) {
            revert FSSale_CantWithdrawTwice();
        }
        sale.earningsWithdrawn = true;
        uint256 totalProfit = sale.totalETHRaised;
        safeTransferETH(msg.sender, totalProfit);
    }

    // 提取剩余部分
    function withdrawLeftoverInternal() internal {
        if (block.timestamp < sale.saleEnd) {
            revert FSSale_SaleNotEnded();
        }
        if (sale.earningsWithdrawn) {
            revert FSSale_CantWithdrawTwice();
        }
        // 未售出的代币数量
        uint256 leftover = sale.amountOfTokensToSell - sale.totalTokensSold;
        if (leftover > 0) {
            sale.token.safeTransfer(msg.sender, leftover);
        }
    }

    function getParticipation(address _user) external view returns (uint256, uint256, uint256, bool[] memory) {
        Participation memory p = userToParticipation[_user];
        return (p.amountBought, p.amountETHPaid, p.timeParticipated, p.isPortionWithdrawn);
    }

    function getParticipationSigner(bytes memory signature, address user, uint256 amount)
        public
        view
        returns (address)
    {
        bytes32 hash = keccak256(abi.encode(user, amount, address(this)));
        return ECDSA.recover(hash, signature);
    }

    function getNumberOfRegisteredUsers() external view returns (uint256) {
        return registration.numberOfRegistrants;
    }

    function getVestingInfo() external view returns (uint256[] memory, uint256[] memory) {
        return (vestingPortionsUnlockTime, vestingPercentPerPortion);
    }

    receive() external payable {}
}
