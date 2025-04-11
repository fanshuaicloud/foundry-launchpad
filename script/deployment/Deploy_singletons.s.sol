// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {FSToken} from "../../src/FSToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {SalesFactory} from "../../src/sales/SalesFactory.sol";
import {AllocationStaking} from "../../src/AllocationStaking.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DeployFSToken} from "./Deploy_fstoken.s.sol";

contract Deploy_singletons is Script {
    address private immutable ZERO_ADDRESS = 0x0000000000000000000000000000000000000000;
    uint256 public RPS = 1 ether;
    uint256 public delayBeforeStart = 500;
    uint256 private totalRewards = 100 ether;

    function run() public returns (ERC1967Proxy, SalesFactory, FSToken,AllocationStaking) {
        FSToken token;
        DeployFSToken deployfsToken = new DeployFSToken();
        token = deployfsToken.run();

        vm.startBroadcast();
        uint256 time = block.timestamp;
        SalesFactory salesFactory = new SalesFactory(ZERO_ADDRESS);
        AllocationStaking allocationStaking = new AllocationStaking();
        bytes memory initCallData = abi.encodeWithSelector(
            AllocationStaking.initialize.selector, token, RPS, time + delayBeforeStart, address(salesFactory)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(allocationStaking), initCallData);
        salesFactory.setAllocationStaking(address(proxy));

        vm.stopBroadcast();
        console.log("AllocationStaking Logic Contract deployed to:", address(allocationStaking));
        console.log("AllocationStaking Proxy deployed to:", address(proxy));
        return (proxy, salesFactory, token,allocationStaking);
    }
}
