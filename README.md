# dart_anyio

面向工业现场与边缘计算的 Dart 通信与 RPC 解决方案，包含：
- Modbus Server/Client
- AnyRPC 数据网关（支持多种协议适配器，如 Modbus、CAN），并对外提供统一 RPC 接口
- **隔离通道架构**：支持通道独立运行在隔离环境中，具备自动崩溃检测与重启能力
- 基于 json_rpc_2 与代码生成的强类型 RPC 框架：json_rpc_builder / annotation / runtime

## 模块简介

- modbus server/client
  - 提供 Modbus 通信能力（Server/Client）
  - 可扩展寄存器映射与数据源，支持异常与超时处理
- anyrpc service
  - 以“协议适配器 + 统一 RPC”的网关形态聚合现场数据（示例协议：Modbus、CAN 等）
  - 通过 RPC 对外暴露读写接口，屏蔽底层差异
- json_rpc_builder / annotation / runtime
  - 通过注解与代码生成产生服务端适配器与客户端代理
  - 基于 json_rpc_2，端到端类型约束与更少手写字符串

## 示例目录结构（以实际仓库为准）

```
dart_anyio/
├─ packages/
│  ├─ dart_modbus/
│  ├─ json_rpc_builder/
│  ├─ json_rpc_annotation/
│  ├─ json_rpc_runtime/
│  ├─ protocol/
│  ├─ service/
│  └─ template/
├─ examples/
└─ configs/
```

## 隔离通道架构

本服务网关支持**隔离通道架构**，为工业现场通信提供高可靠性保障：

### 🛡️ 故障隔离
- 每个通道运行在独立的 Dart 隔离环境 (Isolate) 中
- 单个通道崩溃不会影响其他通道或主服务
- 内存和执行隔离，防止相互干扰

### 🔄 自动恢复
- 自动检测通道崩溃和通信故障
- 可配置的重启策略（重试次数、重试间隔）
- 透明的故障恢复，无需人工干预

### 📊 监控支持
- 内置重启统计和错误跟踪
- 通道健康状态监控
- 支持手动重启指定通道

### 使用示例

```dart
// 启用隔离通道
final channelManager = ChannelManagerImpl(useIsolatedChannels: true);

// 配置自动重启
final serviceManager = ServiceManager(
  channelManager: channelManager,
  transportManager: transportManager,
  enableChannelRestart: true,    // 启用自动重启
  maxRestartAttempts: 3,         // 最大重试次数
  restartDelaySeconds: 5,        // 重试间隔
);

// 获取重启统计
final stats = serviceManager.getRestartStats();

// 手动重启通道
await serviceManager.restartChannel('device-id');
```

详细文档请参考：[隔离通道架构文档](docs/isolated-channels.md)

## 快速开始

前置
- Dart SDK（稳定版）
- 可选：构建工具 build_runner（用于 RPC 代码生成）

安装依赖
- 在仓库根目录执行：dart pub get

构建（如使用代码生成）
- dart run build_runner build --delete-conflicting-outputs

## 使用概览

### 1) Modbus Server/Client（概念性说明）
当前接口尚未最终确定，具体代码示例将在接口稳定后补充。可预期能力包括：
- 提供 TCP/RTU 等多种传输形态
- 可扩展寄存器映射、超时与异常处理

说明
- 实际 API/类型名以仓库实现为准
- RTU/串口等形态可通过对应适配器/Transport 接入

### 2) AnyRPC 数据网关

用于把多协议设备纳入统一数据访问接口，典型流程：
- 配置协议适配器与数据点映射
- 启动网关服务，对外暴露 JSON-RPC（或其他）接口

示例配置与调用将在接口稳定后补充。
启动方式
- 可通过命令行启动网关（具体命令与参数将在接口稳定后补充）

### 3) 强类型 JSON-RPC 框架：json_rpc_builder / annotation / runtime

目标
- 通过注解声明接口，自动生成：
  - 服务端适配器（负责把 JSON-RPC 方法路由到实现类）
  - 客户端代理（提供类型安全的调用 API）

步骤
1. 在接口上添加注解（示例稍后提供）
2. 运行代码生成（build_runner）
3. 服务端绑定生成的适配器
4. 使用生成的客户端进行类型安全调用

与 json_rpc_2 的关系
- 传输与协议栈依赖 json_rpc_2
- 生成器屏蔽 method 字符串与参数序列化，提供类型安全 API

底层通道示意将在接口稳定后补充。

## 开发与质量

- 代码格式化：dart format .
- 静态检查：dart analyze
- 单元测试：dart test
- 约定
  - 生成代码不纳入手工修改
  - 公共 API 慎改名，注意向后兼容
  - 协议适配器采用可插拔设计（新增协议以 Adapter 形式接入）

## 路线图

- 协议适配器：扩展更多现场协议（如 Modbus RTU、CANOpen、OPC UA 网关对接等）
- 安全：鉴权/鉴别、ACL、TLS
- 可观测性：日志分级、指标与追踪
- 订阅/推送：数据变更事件上报

## 贡献

- 提交 PR 前请先创建 issue 说明变更
- 遵循现有代码风格与测试覆盖要求

## 许可

- BSD 3-Clause License
