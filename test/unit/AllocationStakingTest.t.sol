//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {FSToken} from "../../src/FSToken.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Deploy_singletons} from "../../script/deployment/Deploy_singletons.s.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SalesFactory} from "../../src/sales/SalesFactory.sol";
import {MockIDOToken} from "../../script/mocks/MockIDOToken.sol";
import {MockSaleToken} from "../../script/mocks/MockSaleToken.sol";
import {AllocationStaking} from "../../src/AllocationStaking.sol";
import {FSSale} from "../../src/sales/FSSale.sol";

contract AllocationStakingTest is Test {
    ERC1967Proxy proxy;
    SalesFactory salesFactory;
    FSToken token;
    MockIDOToken mockIDOToken;
    AllocationStaking allocationStaking;
    AllocationStaking deployallocationStaking;
    FSSale sale;
    MockSaleToken mockSaleToken;

    uint256 public constant STARTAMOUNT = 5000 ether;
    uint256 public constant FUNDMOUNT = 1000 ether;
    uint256 public constant PORTION_VESTING_PRECISION = 100;
    uint256 public constant REGISTRATION_DEPOSIT_AVAX = 1000 ether;
    uint256 public constant MAX_VESTING_TIME_SHIFT = 30;
    uint256 public constant TOKENSFORSALE = 10000000 ether;

    uint256[] UNLOCKINGTIMES = [block.timestamp + 10, block.timestamp + 50, block.timestamp + 70];
    uint256[] PERCENTS = [50, 20, 30];

    uint256 public constant ALLOCPOINT = 1;
    address OWNER;
    address USER = makeAddr("user");
    address USER1 = makeAddr("user1");
    address ProjectSide = makeAddr("Project Side");
    uint256 ownerPrivateKey;

    function setUp() public {
        (OWNER, ownerPrivateKey) = makeAddrAndKey("owner");
        Deploy_singletons deploy = new Deploy_singletons();
        (proxy, salesFactory, token, deployallocationStaking) = deploy.run();
        mockIDOToken = new MockIDOToken();
        mockSaleToken = new MockSaleToken();
        allocationStaking = AllocationStaking(address(proxy));
        vm.startPrank(salesFactory.owner());
        salesFactory.deploySale();
        salesFactory.transferOwnership(OWNER);
        vm.stopPrank();
        vm.startPrank(token.owner());
        token.mint(OWNER, STARTAMOUNT);
        token.transferOwnership(OWNER);
        vm.stopPrank();
        vm.startPrank(mockIDOToken.owner());
        mockIDOToken.mint(OWNER, STARTAMOUNT);
        mockIDOToken.transferOwnership(OWNER);
        vm.stopPrank();
        vm.startPrank(allocationStaking.owner());
        allocationStaking.transferOwnership(OWNER);
        vm.stopPrank();
        vm.startPrank(mockSaleToken.owner());
        mockSaleToken.mint(ProjectSide, TOKENSFORSALE);
        mockSaleToken.transferOwnership(ProjectSide);
        vm.stopPrank();
    }

    //测试添加pool
    function testAddpool() public {
        vm.startPrank(OWNER);
        allocationStaking.add(ALLOCPOINT, IERC20(address(mockIDOToken)), true);
        vm.stopPrank();
        uint256 pollLength = allocationStaking.poolLength();
        assertEq(pollLength, 1);
    }

    modifier starAllocationStaking() {
        vm.startPrank(OWNER);
        allocationStaking.add(ALLOCPOINT, IERC20(address(mockIDOToken)), true);
        token.approve(address(allocationStaking), FUNDMOUNT);
        allocationStaking.fund(FUNDMOUNT);
        vm.stopPrank();
        _;
    }

    //测试用户质押
    function testUserDeposit() public starAllocationStaking {
        vm.startPrank(OWNER);
        mockIDOToken.mint(USER, STARTAMOUNT);
        vm.stopPrank();
        vm.startPrank(USER);
        mockIDOToken.approve(address(allocationStaking), STARTAMOUNT);
        allocationStaking.deposit(0, STARTAMOUNT);
        vm.stopPrank();
        assertEq(allocationStaking.deposited(0, USER), STARTAMOUNT);
    }

    modifier userDeposit() {
        vm.startPrank(OWNER);
        mockIDOToken.mint(USER, STARTAMOUNT);
        vm.stopPrank();
        vm.startPrank(USER);
        mockIDOToken.approve(address(allocationStaking), STARTAMOUNT);
        allocationStaking.deposit(0, STARTAMOUNT);
        vm.stopPrank();
        _;
    }

    modifier saleCreated() {
        address saleAddress = salesFactory.allSales(0);
        sale = FSSale(payable(saleAddress));
        vm.startPrank(sale.owner());
        sale.setSaleParams(
            address(mockSaleToken),
            ProjectSide,
            10 ** 16,
            TOKENSFORSALE,
            block.timestamp + 100,
            block.timestamp + 150,
            PORTION_VESTING_PRECISION,
            REGISTRATION_DEPOSIT_AVAX
        );
        sale.setVestingParams(UNLOCKINGTIMES, PERCENTS, MAX_VESTING_TIME_SHIFT);
        sale.setRegistrationTime(block.timestamp + 5, block.timestamp + 90);
        sale.transferOwnership(OWNER);
        vm.stopPrank();
        _;
    }

    //测试项目方转入资金
    function testDepositTokens() public saleCreated {
        vm.startPrank(ProjectSide);
        mockSaleToken.approve(address(sale), TOKENSFORSALE);
        sale.depositTokens();
        vm.stopPrank();
        assertEq(mockSaleToken.balanceOf(address(sale)), TOKENSFORSALE);
    }

    modifier depositTokens() {
        vm.startPrank(ProjectSide);
        mockSaleToken.approve(address(sale), TOKENSFORSALE);
        sale.depositTokens();
        _;
    }

    modifier userRegister() {
        vm.warp(block.timestamp + 5);
        bytes32 mtessage = sale.getMessageHash(USER, 0, OWNER);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, mtessage);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.startPrank(USER);
        sale.registerForSale(signature, 0);
        _;
    }

    //测试用户注册购买成功
    function testRegisterForSale() public starAllocationStaking userDeposit saleCreated {
        vm.warp(block.timestamp + 5);
        bytes32 mtessage = sale.getMessageHash(USER, 0, OWNER);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, mtessage);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.startPrank(USER);
        sale.registerForSale(signature, 0);
        vm.stopPrank();
        assertEq(sale.getNumberOfRegisteredUsers(), 1);
    }

    //测试用户多次注册同一个信息
    function testRegisterTwiceForSale() public starAllocationStaking userDeposit saleCreated {
        vm.warp(block.timestamp + 5);
        bytes32 mtessage = sale.getMessageHash(USER, 0, OWNER);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, mtessage);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.startPrank(USER);
        sale.registerForSale(signature, 0);
        vm.expectRevert(abi.encodeWithSelector(FSSale.FSSale__AlreadyRegistered.selector));
        sale.registerForSale(signature, 0);
        vm.stopPrank();
    }

    //测试用户注册签名无效
    function testRegisterBadSignForSale() public starAllocationStaking userDeposit saleCreated {
        vm.warp(block.timestamp + 5);
        bytes32 mtessage = sale.getMessageHash(USER, 1, OWNER);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, mtessage);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(FSSale.FSSale__SignatureNotMatch.selector));
        sale.registerForSale(signature, 0);
        vm.stopPrank();
    }

    //测试用户注册时间过早失败
    function testRegisterBeforeRegistrationTimeStarts() public starAllocationStaking userDeposit saleCreated {
        vm.warp(block.timestamp + 2);
        bytes32 mtessage = sale.getMessageHash(USER, 0, OWNER);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, mtessage);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(FSSale.FSSale__RegistrationTimeOut.selector));
        sale.registerForSale(signature, 0);
        vm.stopPrank();
    }

    //测试用户注册时间过晚失败
    function testRegisterAfterRegistrationTimeEnds() public starAllocationStaking userDeposit saleCreated {
        vm.warp(block.timestamp + 100);
        bytes32 mtessage = sale.getMessageHash(USER, 0, OWNER);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, mtessage);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(FSSale.FSSale__RegistrationTimeOut.selector));
        sale.registerForSale(signature, 0);
        vm.stopPrank();
    }

    function test_participate() public starAllocationStaking userDeposit saleCreated depositTokens userRegister {
        bytes32 mtessage = sale.getMessageHash(USER, 50 ether, OWNER);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, mtessage);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.startPrank(USER, USER);
        vm.deal(USER, 1 ether);
        sale.participate{value: 0.5 ether}(signature, 50 ether);
        vm.stopPrank();
        assertEq(sale.isParticipated(USER), true);
        assertEq(sale.getSatotalTokensSold(), 50 ether);
    }

    modifier userRaricipe() {
        bytes32 mtessage = sale.getMessageHash(USER, 50 ether, OWNER);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, mtessage);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.startPrank(USER, USER);
        vm.deal(USER, 1 ether);
        sale.participate{value: 0.5 ether}(signature, 50 ether);
        _;
    }

    function testwithdrawTokens()
        public
        starAllocationStaking
        userDeposit
        saleCreated
        depositTokens
        userRegister
        userRaricipe
    {
        vm.warp(block.timestamp + 200);
        vm.startPrank(USER);
        sale.withdrawTokens(0);
        assertEq(mockSaleToken.balanceOf(USER), 25 ether);
    }

    function testwithdrawMultiplePortions()
        public
        starAllocationStaking
        userDeposit
        saleCreated
        depositTokens
        userRegister
        userRaricipe
    {
        vm.warp(block.timestamp + 200);
        vm.startPrank(USER);
        uint256[] memory portions = new uint256[](3);
        portions[0] = 0;
        portions[1] = 1;
        portions[2] = 2;
        sale.withdrawMultiplePortions(portions);
        assertEq(mockSaleToken.balanceOf(USER), 50 ether);
    }

    function testwithdrawEarnings()
        public
        starAllocationStaking
        userDeposit
        saleCreated
        depositTokens
        userRegister
        userRaricipe
    {
        vm.warp(block.timestamp + 300);
        vm.startPrank(ProjectSide);
        sale.withdrawEarnings();
        assertEq(address(ProjectSide).balance, 0.5 ether);
    }
}
