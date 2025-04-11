// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {FSToken} from "../../src/FSToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {FarmingFST} from "../../src/farming/FarmingFST.sol";
import {DeployFSToken} from "./Deploy_fstoken.s.sol";

contract Deploy_farm is Script {
    uint256 public RPS = 1 ether;

    function run() public returns (FarmingFST, FSToken) {
        FSToken token;
        DeployFSToken deployfsToken = new DeployFSToken();
        token = deployfsToken.run();
        vm.startBroadcast();
        FarmingFST farmingFST = new FarmingFST(token, RPS, block.timestamp);
        vm.stopBroadcast();
        return (farmingFST, token);
    }
}
