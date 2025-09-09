# 03. WebAssembly技术基础

## WebAssembly概述

### 什么是WebAssembly？
WebAssembly（WASM）是一种低级的二进制指令格式，设计目标包括：

- **高效执行**：接近原生代码性能
- **安全沙箱**：内存安全的执行环境
- **跨平台**：独立于硬件和操作系统
- **多语言支持**：支持C/C++、Rust、Go等多种语言

### WASM在区块链中的应用优势

1. **性能优势**：比EVM快10-100倍
2. **内存安全**：Rust等语言提供内存安全保证
3. **工具链成熟**：完善的编译和调试工具
4. **生态丰富**：庞大的开源库支持

## WASM规范与执行原理

### WASM模块结构
```
+----------------+
|    头部        |  Magic number, version
+----------------+
|    类型段      |  函数签名定义
+----------------+
|    导入段      |  外部依赖声明
+----------------+
|    函数段      |  函数定义
+----------------+
|    表段        |  间接函数调用表
+----------------+
|    内存段      |  线性内存定义
+----------------+
|    全局段      |  全局变量定义
+----------------+
|    导出段      |  导出接口声明
+----------------+
|    代码段      |  函数体字节码
+----------------+
|    数据段      |  初始化数据
+----------------+
```

### 执行流程
1. **解码**：解析二进制格式
2. **验证**：检查类型安全和约束
3. **编译**：生成机器代码
4. **实例化**：创建运行实例
5. **执行**：运行代码

## wasmtime运行时架构

### 核心组件

#### 1. Engine - 引擎
```rust
let engine = Engine::new(Config::new()
    .epoch_interruption(true)  // 支持超时中断
    .cranelift_opt_level(OptLevel::Speed)  // 优化级别
);
```

#### 2. Store - 状态存储
```rust
let mut store = Store::new(&engine, ());  // 空状态
// 或者带有上下文的存储
let mut store = Store::new(&engine, context);
```

#### 3. Module - 模块
```rust
let module = Module::new(&engine, wasm_bytes)?;  // 从字节码创建
// 或者从预编译模块创建
let module = unsafe { Module::deserialize(&engine, precompiled_bytes)? };
```

#### 4. Instance - 实例
```rust
let instance = Instance::new(&mut store, &module, &imports)?;
```

### 预编译优化

#### AOT编译（Ahead-of-Time）
```rust
// 预编译模块
let precompiled_bytes = engine.precompile_module(wasm_bytes)?;

// 反序列化预编译模块
let module = unsafe { Module::deserialize(&engine, precompiled_bytes)? };
```

**性能优势**：
- 减少运行时编译开销
- 更好的代码优化
- 更快的实例化速度

## WASM内存模型

### 线性内存
WASM使用单一的线性地址空间：

```rust
// 创建内存
let memory_type = MemoryType::new(1, Some(10));  // 初始1页，最大10页
let memory = Memory::new(&mut store, memory_type)?;

// 读写内存
memory.write(&mut store, offset, data)?;
let data = memory.read(&store, offset, length)?;
```

### 内存页管理
- 1页 = 64KB
- 动态增长
- 边界检查

## 函数调用与FFI

### 导出函数调用
```rust
// 获取导出函数
let add_func = instance.get_typed_func::<(i32, i32), i32>(&mut store, "add")?;

// 调用函数
let result = add_func.call(&mut store, (1, 2))?;
```

### 导入外部函数
```rust
// 创建Linker
let mut linker = Linker::new(&engine);

// 添加外部函数
linker.func_wrap("env", "log", |msg: i32| {
    println!("Log: {}", msg);
})?;

// 实例化时传入导入
let instance = linker.instantiate(&mut store, &module)?;
```

## 智能合约的WASM编译优化

### 编译选项优化
```rust
// Rust编译配置
[package.metadata.wasm-pack.profile.release]
wasm-opt = ["-O3", "--enable-bulk-memory"]

// 或者使用wasm-bindgen
[package.metadata.wasm-bindgen]
optimize = "size"
```

### 代码大小优化

#### 1. 移除调试信息
```bash
wasm-strip contract.wasm
```

#### 2. 优化级别调整
```bash
wasm-opt -O3 contract.wasm -o contract.optimized.wasm
```

#### 3. 使用LTO
```toml
[profile.release]
lto = true
codegen-units = 1
```

### 性能优化技巧

#### 1. 内存布局优化
```rust
// 使用 packed 结构体
#[repr(packed)]
struct CompactData {
    field1: u32,
    field2: u16,
}
```

#### 2. 避免不必要的复制
```rust
// 使用引用而非值拷贝
fn process_data(data: &[u8]) -> Result<()> {
    // 处理数据，避免复制
}
```

#### 3. 批量操作
```rust
// 批量处理数据
fn process_batch(data: &[Data]) -> Result<()> {
    for item in data {
        // 处理每个项
    }
}
```

## 安全考虑

### 1. 内存安全
```rust
// 边界检查
fn safe_memory_access(
    memory: &Memory,
    offset: usize,
    length: usize
) -> Result<()> {
    if offset + length > memory.size() {
        return Err("Out of bounds");
    }
    Ok(())
}
```

### 2. 资源限制
```rust
// 设置执行超时
let engine = Engine::new(Config::new().epoch_interruption(true));

// 监控线程
std::thread::spawn(move || {
    std::thread::sleep(Duration::from_secs(1));
    engine.increment_epoch();  // 触发超时
});
```

### 3. Gas计量
```rust
// 简单的Gas计数
struct GasCounter {
    remaining: u64,
    limit: u64,
}

impl GasCounter {
    fn charge(&mut self, amount: u64) -> Result<()> {
        if self.remaining < amount {
            return Err("Out of gas");
        }
        self.remaining -= amount;
        Ok(())
    }
}
```

## 调试与测试

### 1. 调试工具
```bash
# 使用wasmtime调试
wasmtime --dir=. --invoke main contract.wasm

# 使用wasm-gdb
wasm-gdb contract.wasm
```

### 2. 单元测试
```rust
#[cfg(test)]
mod tests {
    use super::*;
    use wasmtime::*;
    
    #[test]
    fn test_contract() -> Result<()> {
        let wasm_bytes = include_bytes!("../target/wasm32-unknown-unknown/release/contract.wasm");
        let engine = Engine::default();
        let module = Module::new(&engine, wasm_bytes)?;
        
        // 测试逻辑
        Ok(())
    }
}
```

### 3. 性能分析
```bash
# 使用wasmtime的profiling功能
wasmtime --profile=profiling.data contract.wasm

# 分析性能数据
wasmtime analyze profiling.data
```

## 实际应用：xwasm的WASM集成

### 虚拟机封装
```rust
pub struct WasmtimeRuntime {
    engine: Engine,
    precompiled_modules: HashMap<Vec<u8>, Vec<u8>>,
}

impl WasmtimeRuntime {
    pub fn execute(
        &self,
        function_name: &str,
        context: Context,
        wasm_bytes: &[u8],
        amount: u64
    ) -> Result<ExecutionResult> {
        // 执行WASM合约
    }
}
```

### 链接器配置
```rust
fn configure_linker(linker: &mut Linker<Context>) -> Result<()> {
    // 添加链环境接口
    linker.func_wrap("xq", "get_owner", |caller: Caller<Context>, ptr: i32| {
        // 实现获取合约拥有者
    })?;
    
    linker.func_wrap("xq", "get_balance", |caller: Caller<Context>| -> u64 {
        // 实现获取余额
    })?;
    
    Ok(())
}
```

## 总结

WebAssembly为智能合约执行提供了高性能、安全的基础设施。wasmtime作为成熟的WASM运行时，提供了丰富的功能和优化选项。通过合理的编译优化、内存管理和安全措施，可以构建出高效可靠的智能合约执行环境。

在下一章中，我们将深入探讨合约语言语法设计，了解如何设计优雅且功能强大的eDSL。