// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {FSToken} from "../../src/FSToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {FarmingFST} from "../../src/farming/FarmingFST.sol";

contract Deploy_farm is Script {
    bytes32 public merkleRoot = 0x4dad3e929e5eadd10708dedac2bc28ee1d6e373d1704de70627ebf36e3db5659;
    uint256 public STARTAMOUNT = 5000 ether;
    uint256 public RPS = 1 ether;

    function run() public returns (FarmingFST) {
        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment("FSToken", block.chainid);
        FSToken token = FSToken(mostRecentlyDeployed);
        vm.startBroadcast();
        FarmingFST farmingFST = new FarmingFST(token, RPS, block.timestamp);
        token.mint(token.owner(), STARTAMOUNT);
        token.transfer(address(farmingFST), STARTAMOUNT);
        vm.stopBroadcast();
        return farmingFST;
    }
}
