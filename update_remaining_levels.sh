#!/bin/bash

# Script to update remaining Ethernaut levels (11-25) with complete content

# Array of levels to update with their information
declare -A levels=(
    ["11"]="Elevator;接口实现攻击"
    ["12"]="Privacy;存储布局分析"
    ["13"]="GatekeeperOne;条件绕过攻击"
    ["14"]="GatekeeperTwo;条件绕过攻击"
    ["15"]="NaughtCoin;ERC20代币攻击"
    ["16"]="Preservation;委托调用攻击"
    ["17"]="Recovery;合约地址计算"
    ["18"]="MagicNumber;字节码构造"
    ["19"]="AlienCodex;数组下溢攻击"
    ["20"]="Denial;拒绝服务攻击"
    ["21"]="Shop;接口操纵攻击"
    ["22"]="Dex;价格操纵攻击"
    ["23"]="DexTwo;ERC20假币攻击"
    ["24"]="PuzzleWallet;代理合约攻击"
    ["25"]="Motorbike;初始化攻击"
)

# Function to convert title to URL format
title_to_url() {
    local title="$1"
    echo "${title}" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g'
}

# Process each level
for level_num in {11..25}; do
    level_info=${levels[$level_num]}
    IFS=';' read -r title attack_type <<< "$level_info"
    
    # Format level number with leading zero if needed
    formatted_num=$(printf "%02d" $level_num)
    
    # Source file name mapping
    case $title in
        "GatekeeperOne") source_file="13_GatekeeperOne_zh.md" ;;
        "GatekeeperTwo") source_file="14_GatekeeperTwo_zh.md" ;;
        "NaughtCoin") source_file="15_NaughtCoin_zh.md" ;;
        "AlienCodex") source_file="19_AlienCodex_zh.md" ;;
        "PuzzleWallet") source_file="24_PuzzleWallet_zh.md" ;;
        "DexTwo") source_file="23_DexTwo_zh.md" ;;
        *) source_file="${formatted_num}_${title}_zh.md" ;;
    esac
    
    # Target file
    target_url=$(title_to_url "$title")
    target_file="source/_posts/ethernaut-level-${formatted_num}-${target_url}.md"
    
    echo "Processing Level $level_num: $title ($attack_type)"
    echo "Source: temp_ethernaut/solutions/$source_file"
    echo "Target: $target_file"
    
    # Check if source file exists
    if [ ! -f "temp_ethernaut/solutions/$source_file" ]; then
        echo "Warning: Source file not found: temp_ethernaut/solutions/$source_file"
        continue
    fi
    
    # Check if target file exists
    if [ ! -f "$target_file" ]; then
        echo "Warning: Target file not found: $target_file"
        continue
    fi
    
    echo "Files verified. Ready for processing..."
    echo "---"
done

echo "Script completed analysis. Ready for manual processing."