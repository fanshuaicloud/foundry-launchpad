//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {Airdrop} from "../../src/sales/AirDrop.sol";
import {FSToken} from "../../src/FSToken.sol";
import {Deploy_airdrop_fs} from "../../script/deployment/Deploy_airdrop_fs.s.sol";

contract MerkleAirdropTest is Test {
    Airdrop public merkleAirdrop;

    FSToken public airdropToken;
    bytes32 public ROOT = 0x4dad3e929e5eadd10708dedac2bc28ee1d6e373d1704de70627ebf36e3db5659;
    uint256 public AMOUNT_TO_CLAIM = 25 ether;
    uint256 public AMOUNT_TO_MINT = AMOUNT_TO_CLAIM * 5;

    bytes32 public proof1 = 0x0fd7c981d39bece61f7499702bf59b3114a90e66b51ba2c53abdf7b62986c00a;
    bytes32 public proof2 = 0xe5ebd1e1b5a5478a944ecab36a9a954ac3b6b8216875f6524caa7a1d87096576;
    bytes32 public proof3 = 0x5e64fbae66b27bc267a15cbb7add73cc1485128099b4f4beb7760ad5f9f0ce1a;
    bytes32[] public PROOF = [proof1, proof2,proof3];

    address user;
    uint256 userPrivateKey;

    address public gasPayer;

    function setUp() public {
        Deploy_airdrop_fs deployMerkleAirDrop = new Deploy_airdrop_fs();
        (merkleAirdrop, airdropToken) = deployMerkleAirDrop.run();
        (user, userPrivateKey) = makeAddrAndKey("user");
        gasPayer = makeAddr("gasPayer");
    }

    function testUsersCanClaim() public {
        uint256 startBalance = airdropToken.balanceOf(user);
        bytes32 mtessage = merkleAirdrop.getMessageHash(user, AMOUNT_TO_CLAIM);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, mtessage);

        vm.startPrank(gasPayer);
        merkleAirdrop.claimBySign(user, AMOUNT_TO_CLAIM, PROOF, v, r, s);
        vm.stopPrank();

        uint256 endBalance = airdropToken.balanceOf(user);
        assertEq(endBalance - startBalance, AMOUNT_TO_CLAIM);
    }
}
