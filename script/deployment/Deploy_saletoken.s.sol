// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MockSaleToken} from "../mocks/MockSaleToken.sol";

contract Deploy_sale_token is Script {
    function run() external returns (MockSaleToken) {
        vm.startBroadcast();
        MockSaleToken mockSaleToken = new MockSaleToken();
        vm.stopBroadcast();
        console.log("MockSaleToken deployed to:", address(mockSaleToken));
        return mockSaleToken;
    }
}
