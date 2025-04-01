// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {FSSale} from "./FSSale.sol";

contract SalesFactory is Ownable {
    address public allocationStaking;

    mapping(address => bool) public isSaleCreatedThroughFactory;
    address[] public allSales;

    event SaleDeployed(address indexed saleContract);

    error SalesFactory__AddressCannotBeZero();
    error SalesFactory__EndIndexIsSmallerThanStartIndex();

    constructor(address _allocationStaking) Ownable(msg.sender) {
        allocationStaking = _allocationStaking;
    }

    function setAllocationStaking(address _allocationStaking) public onlyOwner {
        if (_allocationStaking == address(0)) {
            revert SalesFactory__AddressCannotBeZero();
        }
        allocationStaking = _allocationStaking;
    }

    function deploySale() external onlyOwner {
        FSSale sale = new FSSale(allocationStaking);
        isSaleCreatedThroughFactory[address(sale)] = true;
        allSales.push(address(sale));
        emit SaleDeployed(address(sale));
    }

    function getNumberOfSalesDeployed() external view returns (uint256) {
        return allSales.length;
    }

    function getLastDeployedSale() external view returns (address) {
        //
        if (allSales.length > 0) {
            return allSales[allSales.length - 1];
        }
        return address(0);
    }

    function getAllSales(uint256 startIndex, uint256 endIndex) external view returns (address[] memory) {
        require(endIndex > startIndex, "Bad input");
        if (startIndex > endIndex) {
            revert SalesFactory__EndIndexIsSmallerThanStartIndex();
        }

        address[] memory sales = new address[](endIndex - startIndex);
        uint256 index = 0;

        for (uint256 i = startIndex; i < endIndex; i++) {
            sales[index] = allSales[i];
            index++;
        }
        return sales;
    }
}
