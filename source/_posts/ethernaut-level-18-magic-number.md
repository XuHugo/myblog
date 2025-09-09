---
title: 'Ethernaut Level 18: Magic Number - 手写EVM字节码'
date: 2025-01-25 16:35:00
updated: 2025-01-25 16:35:00
categories:
  - Ethernaut 系列
  - 进阶攻击篇 (11-20)
tags:
  - Ethernaut
  - Foundry
  - EVM
  - Bytecode
  - Assembly
  - Opcodes
  - 智能合约安全
series: Ethernaut Foundry Solutions
excerpt: "深入EVM底层，学习如何手动编写合约的创建和运行时字节码。理解 `creation code` 和 `runtime code` 的区别，掌握 `PUSH1`, `MSTORE`, `CODECOPY`, `RETURN` 等核心操作码，完成 Magic Number 关卡的挑战。"
---

# 🎯 Ethernaut Level 18: Magic Number - 手写EVM字节码

> **关卡链接**: [Ethernaut Level 18 - Magic Number](https://ethernaut.openzeppelin.com/level/18)  
> **攻击类型**: EVM字节码编写  
> **难度**: ⭐⭐⭐⭐⭐

## 📋 挑战目标

你需要部署一个合约，它必须满足两个条件：
1.  它的运行时字节码（`runtime bytecode`）大小不能超过10个字节。
2.  当调用它的 `whatIsTheMeaningOfLife()` 函数时，必须返回 `42`。

![Magic Number Requirements](https://ethernaut.openzeppelin.com/imgs/BigLevel18.svg)

## 🔍 漏洞分析

这个挑战将我们带入EVM的底层。使用Solidity编写一个返回42的函数非常简单，但编译后的字节码会远远超过10字节的限制，因为它包含了函数调度器、安全检查等大量额外代码。

```solidity
// 编译后字节码会很长，无法通过关卡
contract NormalSolver {
    function whatIsTheMeaningOfLife() public pure returns (uint256) {
        return 42;
    }
}
```

因此，我们必须手动编写EVM字节码。我们需要分别构建两部分代码：

1.  **运行时代码 (Runtime Code)**: 这是最终存储在链上的代码，负责在被调用时返回42。这部分代码的长度必须小于等于10字节。
2.  **创建代码 (Creation Code)**: 这是部署合约时执行的代码。它的任务只有一个：将运行时代码返回，以便EVM将其存储为新合约的代码。

### 1. 构建运行时代码 (Runtime Code)

我们的运行时代码需要做两件事：
1.  将数字 `42` (十六进制为 `0x2a`) 放入内存。
2.  从内存中返回这个数字。

这需要以下操作码（Opcodes）：

| Opcode | 名称   | 作用                               |
| :----- | :----- | :--------------------------------- |
| `0x60` | `PUSH1`| 将1个字节的数据压入堆栈。          |
| `0x52` | `MSTORE`| `MSTORE(p, v)`: 将值 `v` 存入内存地址 `p`。 |
| `0xf3` | `RETURN`| `RETURN(p, s)`: 从内存地址 `p` 开始，返回 `s` 字节的数据。 |

执行步骤如下：
1.  `PUSH1 0x2a`: 将 `42` 压入堆栈。
2.  `PUSH1 0x80`: 将内存地址 `0x80` 压入堆栈。（`0x80` 是Solidity中自由内存指针的起始位置，使用它是惯例）。
3.  `MSTORE`: `mstore(0x80, 0x2a)`，将 `42` 存入内存。
4.  `PUSH1 0x20`: 将返回值大小 `32` 字节（一个 `uint256`）压入堆栈。
5.  `PUSH1 0x80`: 将返回的内存地址 `0x80` 压入堆栈。
6.  `RETURN`: `return(0x80, 0x20)`，返回结果。

将这些步骤转换为字节码：
`602a` `6080` `52` `6020` `6080` `f3`

这个字节码的长度是10字节：`0x602a60805260206080f3`。完美符合要求！

### 2. 构建创建代码 (Creation Code)

创建代码的任务是将上面的10字节运行时代码返回给EVM。它需要做两件事：
1.  将运行时代码从创建代码的末尾复制到内存中。
2.  从内存中返回这段运行时代码。

这需要 `CODECOPY` 操作码：

| Opcode | 名称     | 作用                               |
| :----- | :------- | :--------------------------------- |
| `0x39` | `CODECOPY`| `CODECOPY(d, p, s)`: 从代码的 `p` 位置开始，复制 `s` 字节到内存的 `d` 位置。 |

执行步骤如下：
1.  将运行时代码复制到内存 `0x00` 处。
2.  从内存 `0x00` 处返回10字节的代码。

字节码如下：
-   `600a`: `PUSH1 0x0a` (运行时代码长度: 10字节)
-   `600c`: `PUSH1 0x0c` (运行时代码在创建代码中的起始位置: 第12字节)
-   `6000`: `PUSH1 0x00` (目标内存地址: 0)
-   `39`: `CODECOPY`
-   `600a`: `PUSH1 0x0a` (要返回的数据长度: 10字节)
-   `6000`: `PUSH1 0x00` (要返回的内存地址: 0)
-   `f3`: `RETURN`

创建代码为: `0x600a600c600039600a6000f3`。它的长度是12字节。

### 3. 组合最终字节码

最终部署的字节码是 **创建代码 + 运行时代码**：
`0x600a600c600039600a6000f3` + `602a60805260206080f3`

最终字节码: `0x600a600c600039600a6000f3602a60805260206080f3`

## 💻 Foundry 实现

我们可以使用 Foundry 的内联汇编和 `create` 操作码来部署这段字节码。

### Foundry 测试代码

```solidity
// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/18_MagicNumber.sol";

interface ISolver {
    function whatIsTheMeaningOfLife() external view returns (uint256);
}

contract MagicNumberTest is Test {
    MagicNum instance;
    Attack attack;
    address player;

    function setUp() public {
        player = vm.addr(1);
        attack = new Attack();
        instance = new MagicNum();
    }

    function testAttacker() public {
        // 部署我们的手写字节码合约
        address solverAddress = attack.deploySolver();
        instance.setSolver(solverAddress);

        // 验证返回值是否为 42
        assertEq(ISolver(solverAddress).whatIsTheMeaningOfLife(), 42);

        // 验证字节码长度是否为 10
        uint256 size;
        assembly {
            size := extcodesize(solverAddress)
        }
        assertEq(size, 10);
    }
}

contract Attack {
    function deploySolver() public returns (address) {
        address solver;
        // 最终的部署字节码
        bytes memory bytecode = hex"600a600c600039600a6000f3602a60805260206080f3";
        
        assembly {
            // create(v, p, s): 部署合约
            // v: 发送的 ether 值 (0)
            // p: 字节码在内存中的位置 (bytecode + 0x20)
            // s: 字节码的长度 (mload(bytecode))
            solver := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        return solver;
    }
}
```

### 关键攻击步骤

1.  **设计运行时代码**: 精心设计一段不超过10字节的代码，使其能够返回 `42`。
2.  **设计创建代码**: 设计一段代码，其功能是返回第一步中设计的运行时代码。
3.  **组合字节码**: 将创建代码和运行时代码拼接成最终的部署字节码。
4.  **部署**: 使用 `create` 操作码（可以通过内联汇编或发送裸交易）来部署这段字节码，得到求解器合约的地址。
5.  **提交**: 将求解器合约的地址提交给 `Ethernaut` 关卡。

## 🛡️ 防御措施

这个关卡本身不是一个漏洞，而是一个EVM编程的练习。然而，它揭示了在进行字节码级别的审计时需要注意的事项：

-   **理解底层操作**: 仅仅审计Solidity代码可能不足以发现所有问题。对于高度优化的或使用内联汇编的合约，必须理解其生成的EVM操作码的实际行为。
-   **警惕不寻常的部署模式**: 如果一个合约的创建过程不标准（例如，使用裸 `create` 或 `create2`），需要特别审查其字节码的来源和功能。

## 🔧 相关工具和技术

-   **EVM Opcodes**: EVM的操作码是其执行所有计算的基础。`evm.codes` 是一个极好的交互式参考网站。
-   **内联汇编 (`assembly`)**: Solidity允许在代码中直接嵌入汇编语言，提供了对EVM更底层的控制，但同时也带来了更大的风险和复杂性。
-   **`create` 操作码**: 用于从代码中部署新合约。
-   **`extcodesize` 操作码**: 用于获取一个地址上的代码大小。

## 🎯 总结

**核心概念**:
-   合约的字节码分为 `creation code` 和 `runtime code`。
-   `creation code` 在部署时执行一次，其返回值是 `runtime code`。
-   `runtime code` 是永久存储在链上的代码，响应外部调用。
-   通过直接操作EVM操作码，可以创建出非常紧凑和高效的合约。

**攻击向量**:
-   通过手写汇编，绕过高级语言的限制（如本例中的代码大小限制）。

**防御策略**:
-   在安全审计中，不能忽视对底层字节码和汇编的分析，特别是当合约行为不寻常时。

## 📚 参考资料

-   [EVM Codes - An Interactive Reference](https://www.evm.codes/)
-   [Deconstructing a Solidity Contract](https://blog.openzeppelin.com/deconstructing-a-solidity-contract-part-i-introduction-832efd2d7737)
-   [Solidity Docs: Inline Assembly](https://docs.soliditylang.org/en/latest/assembly.html)