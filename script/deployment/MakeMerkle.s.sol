// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console} from "forge-std/console.sol";
import {Merkle} from "murky/src/Merkle.sol";
import {ScriptHelper} from "murky/script/common/ScriptHelper.sol";

// Merkle证明生成脚本
contract MakeMerkle is Script, ScriptHelper {
    using stdJson for string; // 启用我们使用字符串的json作弊码

    Merkle private m = new Merkle(); 

    string private inputPath = "/script/deployment/target/input.json";
    string private outputPath = "/script/deployment/target/output.json";

    string private elements = vm.readFile(string.concat(vm.projectRoot(), inputPath)); // 获取绝对路径
    string[] private types = elements.readStringArray(".types"); // 使用forge标准库作弊码从json中获取Merkle树叶子类型
    uint256 private count = elements.readUint(".count"); // 获取叶子节点的数量

    // 创建与叶子节点数量相同的三个数组
    bytes32[] private leafs = new bytes32[](count);

    string[] private inputs = new string[](count);
    string[] private outputs = new string[](count);

    string private output;

    function getValuesByIndex(uint256 i, uint256 j) internal pure returns (string memory) {
        return string.concat(".values.", vm.toString(i), ".", vm.toString(j));
    } 

    /// @dev 生成输出文件的JSON条目
    function generateJsonEntries(string memory _inputs, string memory _proof, string memory _root, string memory _leaf)
        internal
        pure
        returns (string memory)
    {
        string memory result = string.concat(
            "{",
            "\"inputs\":",
            _inputs,
            ",",
            "\"proof\":",
            _proof,
            ",",
            "\"root\":\"",
            _root,
            "\",",
            "\"leaf\":\"",
            _leaf,
            "\"",
            "}"
        );

        return result;
    }

    /// @dev 读取输入文件并生成Merkle证明，然后写入输出文件
    function run() public {

        for (uint256 i = 0; i < count; ++i) {
            string[] memory input = new string[](types.length); // 字符串化数据（地址和字符串都作为字符串）
            bytes32[] memory data = new bytes32[](types.length); // 实际数据作为bytes32

            for (uint256 j = 0; j < types.length; ++j) {
                if (compareStrings(types[j], "address")) {
                    address value = elements.readAddress(getValuesByIndex(i, j));
                    // 你不能直接将地址转换为32字节，因为地址是20字节，所以首先转换为uint160（20字节），然后转换为uint256（32字节），最后转换为bytes32
                    data[j] = bytes32(uint256(uint160(value))); 
                    input[j] = vm.toString(value);
                } else if (compareStrings(types[j], "uint")) {
                    uint256 value = vm.parseUint(elements.readString(getValuesByIndex(i, j)));
                    data[j] = bytes32(value);
                    input[j] = vm.toString(value);
                }
            }
            // 创建Merkle树叶子节点的哈希
            // 对数据数组进行abi编码（每个元素都是地址和金额的bytes32表示）
            // Helper from Murky (ltrim64) 返回删除前64字节的字节数据
            // ltrim64删除了偏移量和长度。存在偏移量是因为数组在内存中声明
            // 哈希编码的地址和金额
            // bytes.concat将bytes32转换为bytes
            // 再次哈希以防止预映像攻击
            leafs[i] = keccak256(bytes.concat(keccak256(ltrim64(abi.encode(data)))));
            // 将字符串数组转换为JSON数组字符串。
            // 存储每个叶子节点对应的值/输入
            inputs[i] = stringArrayToString(input);
        }

        for (uint256 i = 0; i < count; ++i) {
            // 获取证明获取证明所需的节点并转换为字符串（来自辅助库）
            string memory proof = bytes32ArrayToString(m.getProof(leafs, i));
            // 获取根哈希并转换为字符串
            string memory root = vm.toString(m.getRoot(leafs));
            // 获取当前处理的特定叶子
            string memory leaf = vm.toString(leafs[i]);
            // 获取字符串化的输入（地址，金额）
            string memory input = inputs[i];

            // 生成输出文件的Json（树转储）
            outputs[i] = generateJsonEntries(input, proof, root, leaf);
        }

        // 将字符串数组转换为单个字符串
        output = stringArrayToArrayString(outputs);
        // 将字符串化的输出json（树转储）写入输出文件
        vm.writeFile(string.concat(vm.projectRoot(), outputPath), output);

    }
}
