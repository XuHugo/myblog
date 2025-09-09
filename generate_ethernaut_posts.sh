#!/bin/bash

# Ethernaut Blog Post Generator Script
# This script converts the remaining Ethernaut solutions to blog posts

TEMP_DIR="/home/zaq1/xxx/myblog/temp_ethernaut/solutions"
OUTPUT_DIR="/home/zaq1/xxx/myblog/source/_posts"

# Challenge metadata array (level, title, difficulty, attack_type, date_offset)
declare -a challenges=(
    "4,Telephone,⭐⭐☆☆☆,tx.origin vs msg.sender,60"
    "5,Token,⭐⭐⭐☆☆,整数下溢攻击,70"
    "7,Force,⭐⭐☆☆☆,强制发送以太币,80"
    "8,Vault,⭐⭐⭐☆☆,私有变量读取,90"
    "9,King,⭐⭐⭐⭐☆,拒绝服务攻击,100"
    "11,Elevator,⭐⭐⭐☆☆,接口实现攻击,110"
    "12,Privacy,⭐⭐⭐⭐☆,存储布局分析,120"
    "13,GatekeeperOne,⭐⭐⭐⭐⭐,多重验证绕过,130"
    "14,GatekeeperTwo,⭐⭐⭐⭐⭐,高级验证绕过,140"
    "15,NaughtCoin,⭐⭐⭐☆☆,ERC20 授权攻击,150"
    "16,Preservation,⭐⭐⭐⭐☆,存储槽劫持,160"
    "17,Recovery,⭐⭐⭐⭐☆,合约地址计算,170"
    "18,MagicNumber,⭐⭐⭐⭐⭐,字节码分析,180"
    "19,AlienCodex,⭐⭐⭐⭐⭐,数组边界攻击,190"
    "20,Denial,⭐⭐⭐☆☆,Gas 耗尽攻击,200"
    "21,Shop,⭐⭐⭐☆☆,视图函数攻击,210"
    "22,Dex,⭐⭐⭐⭐☆,DEX 价格操控,220"
    "23,DexTwo,⭐⭐⭐⭐☆,代币注入攻击,230"
    "24,PuzzleWallet,⭐⭐⭐⭐⭐,多重签名钱包攻击,240"
    "25,Motorbike,⭐⭐⭐⭐⭐,UUPS 代理攻击,250"
)

# Function to create blog post for a challenge
create_blog_post() {
    local level=$1
    local title=$2  
    local difficulty=$3
    local attack_type=$4
    local date_offset=$5
    
    local padded_level=$(printf "%02d" $level)
    local source_file="${TEMP_DIR}/${padded_level}_${title}_zh.md"
    local output_file="${OUTPUT_DIR}/ethernaut-level-${padded_level}-$(echo $title | tr '[:upper:]' '[:lower:]').md"
    
    if [[ ! -f "$source_file" ]]; then
        echo "Source file not found: $source_file"
        return 1
    fi
    
    if [[ -f "$output_file" ]]; then
        echo "Output file already exists: $output_file"
        return 0
    fi
    
    # Calculate date
    local base_date="2025-01-25 14:"
    local minute=$((date_offset))
    local date="${base_date}${minute}:00"
    
    echo "Creating blog post for Level $level: $title"
    
    # Create the blog post (this is a simplified template)
    cat > "$output_file" << EOF
---
title: 'Ethernaut Level $level: $title - $attack_type'
date: $date
updated: $date
categories:
  - Web3安全
  - 智能合约
  - Ethernaut
tags:
  - Ethernaut
  - Foundry
  - $(echo $attack_type | sed 's/ /\n  - /g')
  - 智能合约安全
  - Solidity
series: Ethernaut Foundry Solutions
excerpt: "学习 $attack_type 攻击技术，理解 $title 关卡的安全漏洞和防护措施。"
---

# 🎯 Ethernaut Level $level: $title - $attack_type

> **关卡链接**: [Ethernaut Level $level - $title](https://ethernaut.openzeppelin.com/level/$level)  
> **攻击类型**: $attack_type  
> **难度**: $difficulty

## 📋 挑战目标

$(head -20 "$source_file" | grep -A 10 "## 目标" | tail -5 || echo "待完善...")

## 🔍 漏洞分析

$(head -40 "$source_file" | grep -A 15 "## 漏洞" | tail -10 || echo "待完善...")

## 💻 Foundry 实现

\`\`\`solidity
$(head -60 "$source_file" | grep -A 20 "## 解答" | tail -15 || echo "// 攻击代码待完善")
\`\`\`

## 🛡️ 防御措施

- 使用最新版本的 Solidity 编译器
- 遵循安全开发最佳实践  
- 进行充分的代码审计和测试
- 使用 OpenZeppelin 等安全库

## 🎯 总结

$title 关卡展示了 $attack_type 的安全风险，提醒开发者在智能合约开发中需要特别注意相关安全问题。

---

## 🔗 相关链接

- **[系列目录: Ethernaut Foundry Solutions](/2025/01/25/ethernaut-foundry-solutions-series/)**
- **[GitHub 项目](https://github.com/XuHugo/Ethernaut-Foundry-Solutions)**

EOF
    
    echo "Created: $output_file"
}

# Main execution
echo "Starting Ethernaut blog post generation..."

for challenge in "${challenges[@]}"; do
    IFS=',' read -r level title difficulty attack_type date_offset <<< "$challenge"
    create_blog_post "$level" "$title" "$difficulty" "$attack_type" "$date_offset"
    sleep 1
done

echo "Blog post generation completed!"
echo ""
echo "Generated posts for challenges: ${#challenges[@]}"
echo "You can now review and enhance the generated posts with more detailed content."