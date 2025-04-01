// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

interface IAllocationStaking {
    //获取用户在特定质押池中的质押数量
    function deposited(uint256 _pid,address _user) external view returns (uint256);
    //设置指定用户在某个质押池中的代币解锁时间
    function setTokensUnlockTime(uint256 _pid,address _user,uint256 _tokensUnlockTime) external;
    
}