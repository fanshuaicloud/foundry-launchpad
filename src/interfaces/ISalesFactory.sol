// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

interface ISalesFactory {
    //设置销售合约的所有者和销售代币的地址
    function setSaleOwnerAndToken(address saleOwner, address saleToken) external;
    
    //检查某个销售合约是否是通过工厂合约创建的
    function isSaleCreatedThroughFactory(address sale) external view returns (bool);
}
