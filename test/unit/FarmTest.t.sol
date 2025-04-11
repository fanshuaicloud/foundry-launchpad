//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {FSToken} from "../../src/FSToken.sol";
import {Deploy_farm} from "../../script/deployment/Deploy_farm.s.sol";
import {FarmingFST} from "../../src/farming/FarmingFST.sol";
import {FsLpToken} from "../../src/farming/FSLpToken.sol";
import {DeployFSLpToken} from "../../script/deployment/Deploy_fsLPtoken.s.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract FarmTest is Test {
    FSToken token;
    FarmingFST farmingFST;
    FsLpToken lptoken;
    uint256 public constant STARTAMOUNT = 5000 ether;
    uint256 public constant FUNDMOUNT = 1000 ether;

    uint256 public constant ALLOCPOINT = 1;
    address OWNER;
    address USER = makeAddr("user");
    address USER1 = makeAddr("user1");

    function setUp() public {
        Deploy_farm deployFarm = new Deploy_farm();
        (farmingFST, token) = deployFarm.run();
        DeployFSLpToken deployFSLpToken = new DeployFSLpToken();
        lptoken = deployFSLpToken.run();
        OWNER = farmingFST.owner();
        vm.startPrank(token.owner());
        token.mint(OWNER, STARTAMOUNT);
        vm.stopPrank();
    }

    //测试资金注入
    function testfund() public {
        vm.startPrank(OWNER);
        token.approve(address(farmingFST), FUNDMOUNT);
        farmingFST.fund(FUNDMOUNT);
        vm.stopPrank();
        assertEq(farmingFST.totalRewards(), FUNDMOUNT);
    }

    //测试超时后继续资金注入
    function testfundAfterFramingEnd() public {
        vm.startPrank(OWNER);
        token.approve(address(farmingFST), FUNDMOUNT);
        farmingFST.fund(FUNDMOUNT);
        vm.stopPrank();
        vm.warp(farmingFST.endTimestamp() + 1);
        vm.startPrank(OWNER);
        token.approve(address(farmingFST), FUNDMOUNT);
        vm.expectRevert(abi.encodeWithSelector(FarmingFST.FarmingFST__FarmingEnded.selector));
        farmingFST.fund(FUNDMOUNT);
        vm.stopPrank();
    }

    //测试添加一个lp池子
    function testOwnerAddPool() public {
        vm.startPrank(OWNER);
        farmingFST.add(ALLOCPOINT, IERC20(address(lptoken)), true);
        vm.stopPrank();
        uint256 pollLength = farmingFST.poolLength();
        assertEq(pollLength, 1);
    }
    //测试修改池子权重

    function testSetPoolAllowPoint() public {
        vm.startPrank(OWNER);
        farmingFST.add(ALLOCPOINT, IERC20(address(lptoken)), true);
        farmingFST.set(0, ALLOCPOINT + 1, true);
        vm.stopPrank();
        uint256 poolAllowPoint = farmingFST.getPoolAllocPoint(0);
        assertEq(poolAllowPoint, ALLOCPOINT + 1);
    }

    modifier startFarming() {
        vm.startPrank(OWNER);
        farmingFST.add(ALLOCPOINT, IERC20(address(lptoken)), true);
        token.approve(address(farmingFST), FUNDMOUNT);
        farmingFST.fund(FUNDMOUNT);
        vm.stopPrank();
        _;
    }

    //测试用户抵押代币
    function testdeposit() public startFarming {
        vm.startPrank(lptoken.owner());
        lptoken.mint(USER, STARTAMOUNT);
        vm.stopPrank();
        vm.startPrank(USER);
        lptoken.approve(address(farmingFST), STARTAMOUNT);
        farmingFST.deposit(0, STARTAMOUNT);
        vm.stopPrank();
        assertEq(farmingFST.deposited(0, USER), STARTAMOUNT);
    }

    //测试farming资金计算是否正确
    function testPending() public startFarming {
        vm.startPrank(lptoken.owner());
        lptoken.mint(USER, STARTAMOUNT);
        vm.stopPrank();
        vm.startPrank(USER);
        lptoken.approve(address(farmingFST), STARTAMOUNT);
        farmingFST.deposit(0, STARTAMOUNT);
        vm.stopPrank();
        vm.warp(block.timestamp + 100);
        uint256 pending = farmingFST.pending(0, USER);
        assertEq(pending, 100 ether);
    }

    //测试farming资金计算是否正确
    function testPendingByTwoUser() public startFarming {
        vm.startPrank(lptoken.owner());
        lptoken.mint(USER, STARTAMOUNT);
        lptoken.mint(USER1, STARTAMOUNT);
        vm.stopPrank();
        vm.startPrank(USER);
        lptoken.approve(address(farmingFST), STARTAMOUNT);
        farmingFST.deposit(0, STARTAMOUNT);
        vm.stopPrank();
        vm.warp(block.timestamp + 100);
        vm.startPrank(USER1);
        lptoken.approve(address(farmingFST), STARTAMOUNT);
        farmingFST.deposit(0, STARTAMOUNT);
        vm.stopPrank();
        vm.warp(block.timestamp + 100);
        uint256 pending = farmingFST.pending(0, USER);
        assertEq(pending, 150 ether);
    }

    //测试池子总产出代币
    function testtotalPending() public startFarming {
        vm.warp(block.timestamp + 100);
        uint256 pending = farmingFST.totalPending();
        assertEq(pending, 100 ether);
    }

    //测试领取奖励
    function testwithdraw() public startFarming {
        vm.startPrank(lptoken.owner());
        lptoken.mint(USER, STARTAMOUNT);
        vm.stopPrank();
        vm.startPrank(USER);
        lptoken.approve(address(farmingFST), STARTAMOUNT);
        farmingFST.deposit(0, STARTAMOUNT);
        vm.stopPrank();
        vm.warp(block.timestamp + 100);
        vm.startPrank(USER);
        assertEq(lptoken.balanceOf(USER), 0);
        farmingFST.withdraw(0, STARTAMOUNT);
        uint256 tokenBalance = token.balanceOf(USER);
        assertEq(tokenBalance, 100 ether);
        assertEq(lptoken.balanceOf(USER), STARTAMOUNT);
    }

    //测试紧急撤回
    function testemergencyWithdraw() public startFarming {
        vm.startPrank(lptoken.owner());
        lptoken.mint(USER, STARTAMOUNT);
        vm.stopPrank();
        vm.startPrank(USER);
        lptoken.approve(address(farmingFST), STARTAMOUNT);
        farmingFST.deposit(0, STARTAMOUNT);
        vm.stopPrank();
        vm.warp(block.timestamp + 100);
        vm.startPrank(USER);
        assertEq(lptoken.balanceOf(USER), 0);
        farmingFST.emergencyWithdraw(0);
        uint256 tokenBalance = token.balanceOf(USER);
        assertEq(tokenBalance, 0);
        assertEq(lptoken.balanceOf(USER), STARTAMOUNT);
    }
}
