// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {SalesFactory} from "../../src/sales/SalesFactory.sol";
import {FSSale} from "../../src/sales/FSSale.sol";

contract Deploy_sales is Script {
    function run() public returns (FSSale) {
        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment("SalesFactory", block.chainid);
        SalesFactory salesFactory = SalesFactory(mostRecentlyDeployed);
        vm.startBroadcast();
        salesFactory.deploySale();
        address salse = salesFactory.getLastDeployedSale();
        vm.stopBroadcast();
        return new FSSale(salse);
    }
}
