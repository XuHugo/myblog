# 02. Rust元编程与eDSL原理

## 元编程概念与Rust实现

### 什么是元编程？
元编程（Metaprogramming）是指编写能够操作其他程序（或者自身）作为数据的程序。在Rust中，元编程主要通过宏系统实现，允许在编译时生成和操作代码。

### Rust宏系统架构
Rust提供了三种主要的宏类型：

1. **声明式宏（Declarative Macros）**
   - 使用`macro_rules!`语法
   - 基于模式匹配的代码生成
   - 相对简单但功能强大

2. **过程宏（Procedural Macros）**
   - 作为外部crate实现
   - 三种子类型：派生宏、属性宏、函数式宏
   - 提供完整的AST操作能力

3. **属性宏（Attribute Macros）**
   - 应用于项（item）的元数据
   - 可以修改或替换被标记的项
   - xwasm项目主要使用这种类型

## Rust过程宏深度解析

### 派生宏（Derive Macros）
```rust
#[proc_macro_derive(MyTrait)]
pub fn my_derive(input: TokenStream) -> TokenStream {
    // 解析输入并生成代码
}
```

### 属性宏（Attribute Macros）
```rust
#[proc_macro_attribute]
pub fn my_attr(attr: TokenStream, item: TokenStream) -> TokenStream {
    // attr: 属性参数
    // item: 被标记的项
    // 返回修改后的代码
}
```

### 函数式宏（Function-like Macros）
```rust
#[proc_macro]
pub fn my_macro(input: TokenStream) -> TokenStream {
    // 类似声明式宏但更灵活
}
```

## eDSL设计原则

### 什么是eDSL？
领域特定语言（Domain-Specific Language）是针对特定问题域设计的编程语言。在智能合约领域，eDSL需要：

1. **表达合约逻辑**：清晰表达合约业务规则
2. **安全性保障**：内置安全检查和约束
3. **性能优化**：生成高效的底层代码
4. **开发体验**：提供友好的开发接口

### xwasm的eDSL设计

#### 合约结构定义
```rust
#[contract("erc20")]
mod erc20_contract {
    #[state]
    struct Balances {
        balances: HashMap<Address, u64>
    }
    
    #[init]
    fn initialize() -> Result<()> {
        // 初始化逻辑
    }
    
    #[call]
    fn transfer(to: Address, amount: u64) -> Result<()> {
        // 转账逻辑
    }
}
```

#### 宏实现原理
```rust
#[proc_macro_attribute]
pub fn contract(
    attr: TokenStream, 
    item: TokenStream
) -> TokenStream {
    let contract_name = parse_contract_name(attr);
    let ast = parse_macro_input!(item as ItemMod);
    
    // 生成合约包装代码
    generate_contract_wrapper(contract_name, ast)
}
```

## TokenStream操作技术

### TokenStream结构
`TokenStream`是Rust宏系统的核心数据类型，表示一系列的token：

```rust
pub struct TokenStream {
    inner: Vec<TokenTree>,
}

enum TokenTree {
    Group(Group),
    Ident(Ident),
    Punct(Punct),
    Literal(Literal),
}
```

### 常用解析模式

#### 1. 解析属性参数
```rust
let attrs = parse_macro_input!(attr as AttributeArgs);
let contract_name = find_named_arg(&attrs, "contract")?;
```

#### 2. 解析函数签名
```rust
let function = parse_macro_input!(item as ItemFn);
let fn_name = function.sig.ident;
let params = function.sig.inputs;
let return_type = function.sig.output;
```

#### 3. 生成新代码
```rust
let output = quote! {
    // 原始函数保留
    #function
    
    // 生成包装函数
    #[export_name = #wrapper_name]
    pub extern "C" fn #wrapper_fn(#params) -> #return_type {
        // 前置处理
        let result = #fn_name(#args);
        // 后置处理
        result
    }
};
```

## 代码生成最佳实践

### 1. 错误处理
```rust
fn parse_contract_args(attrs: AttributeArgs) -> Result<ContractConfig> {
    let contract = find_named_arg(&attrs, "contract")
        .ok_or_else(|| syn::Error::new(
            Span::call_site(), 
            "missing contract name"
        ))?;
    Ok(ContractConfig { contract })
}
```

### 2. 类型安全
```rust
fn generate_safe_wrapper(
    function: &ItemFn,
    config: &ContractConfig
) -> TokenStream {
    // 检查函数签名是否符合要求
    validate_function_signature(function)?;
    
    // 生成类型安全的包装代码
    quote! { /* ... */ }
}
```

### 3. 性能优化
```rust
fn optimize_generated_code(tokens: TokenStream) -> TokenStream {
    // 移除不必要的代码
    // 内联小函数
    // 优化内存布局
    tokens
}
```

## 实际案例：xwasm的init宏

### 宏定义
```rust
#[proc_macro_attribute]
pub fn init(
    attr: TokenStream, 
    item: TokenStream
) -> TokenStream {
    let attrs = parse_macro_input!(attr as AttributeArgs);
    let contract = get_named_arg(&attrs, "contract").unwrap();
    
    let function = parse_macro_input!(item as ItemFn);
    
    // 生成初始化函数包装
    generate_init_wrapper(contract, function)
}
```

### 生成的代码
```rust
// 原始函数
#[init(contract = "erc20")]
fn initialize(ctx: Context) -> Result<()> {
    // 初始化逻辑
}

// 宏生成的代码
#[export_name = "init_erc20"]
pub extern "C" fn init_erc20_wrapper(
    amount: u64
) -> i32 {
    // 参数检查
    if amount != 0 { return -1; }
    
    // 调用原始函数
    match initialize(ContractContext) {
        Ok(()) => 1,
        Err(e) => {
            ContractContext.error(e.to_string());
            0
        }
    }
}
```

## 测试与调试

### 单元测试
```rust
#[test]
fn test_init_macro() {
    let input = quote! {
        #[init(contract = "test")]
        fn test_init(ctx: Context) -> Result<()> {
            Ok(())
        }
    };
    
    let output = init(
        quote! { contract = "test" },
        input
    );
    
    // 验证生成的代码
    assert!(output.to_string().contains("init_test"));
}
```

### 调试技巧
1. **输出生成的代码**：使用`cargo expand`查看宏展开结果
2. **逐步调试**：在宏中添加`println!`调试信息
3. **AST可视化**：使用`syn`和`quote`的调试功能

## 总结

Rust的元编程系统为eDSL开发提供了强大的工具。通过过程宏，我们可以在编译时生成优化的合约代码，同时保持开发体验的友好性。xwasm项目充分利用了这些特性，实现了类型安全、高性能的智能合约eDSL。

在下一章中，我们将深入探讨WebAssembly技术基础，了解WASM虚拟机的内部工作原理。