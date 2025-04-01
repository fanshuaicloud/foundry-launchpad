// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {FsLpToken} from "../../src/farming/FSLpToken.sol";

contract DeployFSToken is Script {
    function run() external returns (FsLpToken) {
        vm.startBroadcast();
        FsLpToken fsLpToken = new FsLpToken();
        vm.stopBroadcast();
        console.log("FsLpToken deployed to:", address(fsLpToken));
        return fsLpToken;
    }
}
