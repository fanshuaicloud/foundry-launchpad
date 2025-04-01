// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Airdrop} from "../../src/sales/AirDrop.sol";
import {FSToken} from "../../src/FSToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract Deploy_airdrop_fs is Script {
    bytes32 public merkleRoot = 0x4dad3e929e5eadd10708dedac2bc28ee1d6e373d1704de70627ebf36e3db5659;
    uint256 public amountToAirDrop = 5000 ether;

    function run() public returns (Airdrop, FSToken) {
        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment("FSToken", block.chainid);
        FSToken token = FSToken(mostRecentlyDeployed);
        vm.startBroadcast();
        Airdrop airdrop = new Airdrop(merkleRoot, IERC20(mostRecentlyDeployed));
        token.mint(token.owner(), amountToAirDrop);
        token.transfer(address(airdrop), amountToAirDrop);
        vm.stopBroadcast();
        return (airdrop, token);
    }
}
