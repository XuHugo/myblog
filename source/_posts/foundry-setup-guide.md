---
title: 'Foundry 环境搭建与 Ethernaut 项目配置'
date: 2025-01-25 14:05:00
updated: 2025-01-25 14:05:00
categories:
  - Web3开发
  - 工具配置
  - Ethernaut
tags:
  - Foundry
  - 环境搭建
  - Ethernaut
  - Solidity
  - Web3开发
  - 测试框架
series: Ethernaut Foundry Solutions
excerpt: "详细介绍如何安装和配置 Foundry 开发环境，为学习 Ethernaut 智能合约安全挑战做好准备。"
---

# 🛠️ Foundry 环境搭建与 Ethernaut 项目配置

> 在开始 Ethernaut 安全挑战之前，我们需要搭建一个完整的 Foundry 开发环境。本文将详细介绍从零开始的完整配置流程。

## 📚 什么是 Foundry?

**Foundry** 是一个用 Rust 编写的快速、可移植和模块化的以太坊开发工具包，包含：

- **Forge**: 测试框架
- **Cast**: 瑞士军刀般的 RPC 工具
- **Anvil**: 本地测试网络
- **Chisel**: Solidity REPL

### 与其他工具对比

| 工具 | 语言 | 测试速度 | 配置复杂度 | 社区支持 |
|------|------|----------|------------|----------|
| **Foundry** | Rust | ⭐⭐⭐⭐⭐ | ⭐⭐☆☆☆ | ⭐⭐⭐⭐☆ |
| Hardhat | JavaScript | ⭐⭐⭐☆☆ | ⭐⭐⭐☆☆ | ⭐⭐⭐⭐⭐ |
| Truffle | JavaScript | ⭐⭐☆☆☆ | ⭐⭐⭐⭐☆ | ⭐⭐⭐☆☆ |

## 🚀 Foundry 安装

### 方法一：使用 Foundryup (推荐)

```bash
# 下载并安装 Foundryup
curl -L https://foundry.paradigm.xyz | bash

# 重新加载 shell 或重启终端
source ~/.bashrc  # 或 source ~/.zshrc

# 安装最新版本的 Foundry
foundryup

# 验证安装
forge --version
cast --version
anvil --version
```

### 方法二：从源码编译

```bash
# 克隆 Foundry 仓库
git clone https://github.com/foundry-rs/foundry
cd foundry

# 编译安装 (需要 Rust 环境)
cargo build --release
cargo install --path ./crates/forge --bin forge
cargo install --path ./crates/cast --bin cast
cargo install --path ./crates/anvil --bin anvil
```

### 方法三：使用包管理器

```bash
# macOS (Homebrew)
brew install foundry

# Ubuntu/Debian (需要添加 PPA)
# 暂不支持，建议使用方法一

# Windows (需要 WSL)
# 在 WSL 中执行方法一的步骤
```

## 📁 Ethernaut 项目结构

### 克隆项目

```bash
# 克隆 Ethernaut Foundry Solutions 项目
git clone https://github.com/XuHugo/Ethernaut-Foundry-Solutions.git
cd Ethernaut-Foundry-Solutions

# 查看项目结构
tree -L 2
```

### 项目目录结构

```
Ethernaut-Foundry-Solutions/
├── foundry.toml          # Foundry 配置文件
├── .gitmodules          # Git 子模块配置
├── README.md            # 项目说明
├── lib/                 # 依赖库
│   ├── forge-std/       # Foundry 标准库
│   └── openzeppelin-contracts/  # OpenZeppelin 合约库
├── src/                 # 源码目录
│   ├── Fallback.sol     # 关卡原始合约
│   ├── Fallout.sol
│   └── ...
├── test/                # 测试目录
│   ├── FallbackTest.sol # 攻击测试合约
│   ├── FalloutTest.sol
│   └── ...
├── script/              # 部署脚本
└── solutions/           # 解题说明文档
    ├── 01_Fallback_zh.md
    └── ...
```

## ⚙️ 项目配置

### Foundry 配置文件

查看 `foundry.toml` 配置：

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc = "0.8.19"

# Etherscan API 配置 (可选)
[etherscan]
mainnet = { key = "${API_KEY_ETHERSCAN}" }
sepolia = { key = "${API_KEY_ETHERSCAN}" }

# RPC 端点配置
[rpc_endpoints]
mainnet = "https://rpc.ankr.com/eth"
sepolia = "https://rpc.ankr.com/eth_sepolia"
```

### 安装依赖

```bash
# 安装项目依赖
forge install

# 手动安装特定依赖 (如果需要)
forge install openzeppelin/openzeppelin-contracts
forge install foundry-rs/forge-std

# 更新依赖到最新版本
forge update
```

## 🧪 基本使用

### 编译合约

```bash
# 编译所有合约
forge build

# 编译特定合约
forge build src/Fallback.sol

# 查看编译输出
ls out/
```

### 运行测试

```bash
# 运行所有测试
forge test

# 运行特定测试合约
forge test --match-contract FallbackTest

# 详细输出 (多个 v 增加详细程度)
forge test --match-contract FallbackTest -vvv

# 运行特定测试函数
forge test --match-test testFallbackExploit -vvv

# 显示 gas 报告
forge test --gas-report
```

### 使用 Anvil 本地测试网

```bash
# 启动本地测试网 (新终端)
anvil

# 在另一个终端中，针对本地网络运行测试
forge test --fork-url http://localhost:8545
```

## 🔧 常用 Foundry 命令

### Forge 命令

```bash
# 项目管理
forge init my-project          # 初始化新项目
forge build                    # 编译合约
forge clean                    # 清理编译输出

# 测试相关
forge test                     # 运行测试
forge test --watch            # 监视文件变化并自动测试
forge coverage                # 代码覆盖率报告

# 依赖管理
forge install <dependency>     # 安装依赖
forge remove <dependency>     # 移除依赖
forge update                  # 更新依赖

# 代码格式化
forge fmt                     # 格式化 Solidity 代码
```

### Cast 命令

```bash
# 查询区块链信息
cast block-number             # 获取最新区块号
cast balance <address>        # 查询地址余额
cast storage <address> <slot> # 读取存储槽

# 调用合约
cast call <address> <signature> [args]  # 只读调用
cast send <address> <signature> [args]  # 状态变更调用

# 工具函数
cast keccak "function_signature()"      # 计算函数选择器
cast abi-encode "func(uint256)" 123     # ABI 编码
```

### Anvil 命令

```bash
# 启动本地测试网
anvil                         # 默认配置
anvil --port 8545            # 指定端口
anvil --accounts 20          # 指定账户数量
anvil --balance 1000         # 每个账户初始余额 (ETH)

# 从特定状态分叉
anvil --fork-url https://rpc.ankr.com/eth
anvil --fork-url https://rpc.ankr.com/eth --fork-block-number 19000000
```

## 🎯 Ethernaut 专用配置

### 环境变量配置

创建 `.env` 文件：

```bash
# .env 文件
ETHERSCAN_API_KEY=your_etherscan_api_key
MAINNET_RPC_URL=https://rpc.ankr.com/eth
SEPOLIA_RPC_URL=https://rpc.ankr.com/eth_sepolia
PRIVATE_KEY=your_private_key_for_testing
```

加载环境变量：

```bash
# 在 shell 中加载
source .env

# 或在 foundry.toml 中配置自动加载
[profile.default]
env_file = ".env"
```

### 测试模板

创建标准测试文件模板：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/TargetContract.sol";

contract TargetContractTest is Test {
    TargetContract public instance;
    address public attacker = makeAddr("attacker");
    
    function setUp() public {
        // 部署目标合约
        instance = new TargetContract();
        
        // 初始化攻击者账户
        vm.deal(attacker, 10 ether);
    }
    
    function testExploit() public {
        vm.startPrank(attacker);
        
        // 攻击逻辑
        
        vm.stopPrank();
        
        // 验证攻击成功
        assertTrue(/* 验证条件 */);
    }
}
```

## 🐛 常见问题解决

### 编译错误

```bash
# 清理并重新编译
forge clean && forge build

# 检查 Solidity 版本兼容性
forge build --force

# 查看详细错误信息
forge build --verbose
```

### 依赖问题

```bash
# 重新安装依赖
rm -rf lib/
forge install

# 检查 Git 子模块状态
git submodule status
git submodule update --init --recursive
```

### 测试失败

```bash
# 增加详细输出
forge test -vvvv

# 使用调试器
forge test --debug <test_function>

# 检查 gas 使用情况
forge test --gas-report
```

## 📚 进阶配置

### 多版本 Solidity 支持

```toml
# foundry.toml
[profile.default]
solc = "0.8.19"

[profile.legacy]
solc = "0.6.12"
```

### 自定义测试配置

```toml
[profile.default.fuzz]
runs = 1000
max_test_rejects = 65536

[profile.default.invariant]
runs = 256
depth = 32
```

### Gas 优化设置

```toml
[profile.default.optimizer]
enabled = true
runs = 200

[profile.default.model_checker]
contracts = { "/path/to/project/src/Contract.sol" = [ "Contract" ] }
engine = "chc"
targets = [ "assert", "underflow", "overflow", "divByZero" ]
```

## 🎓 总结

现在您已经完成了 Foundry 开发环境的搭建，可以开始 Ethernaut 安全挑战的学习之旅了！

### 下一步：

1. **熟悉 Foundry 基本命令**
2. **运行第一个测试**: `forge test --match-contract FallbackTest -vvv`
3. **开始学习**: [Level 1 - Fallback](/2025/01/25/ethernaut-level-01-fallback/)

---

## 🔗 相关链接

- **[Foundry 官方文档](https://book.getfoundry.sh/)**
- **[Foundry GitHub](https://github.com/foundry-rs/foundry)**
- **[下一篇: Level 1 - Fallback](/2025/01/25/ethernaut-level-01-fallback/)**
- **[系列目录: Ethernaut Foundry Solutions](/2025/01/25/ethernaut-foundry-solutions-series/)**

---

*工欲善其事，必先利其器。掌握好工具，才能更好地学习智能合约安全。* 🔧