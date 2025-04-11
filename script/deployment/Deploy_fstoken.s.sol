// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {FSToken} from "../../src/FSToken.sol";

contract DeployFSToken is Script {

    string private outputPath = "/deployments/contract.address";

    function run() external returns (FSToken) {
        vm.startBroadcast();
        FSToken fsToken = new FSToken();
        vm.stopBroadcast();
        console.log("FSToken deployed to:", address(fsToken));
        return fsToken;
    }
}
