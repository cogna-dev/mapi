# mapi 设计文档

## 1. 目标与定位

`mapi` 是一个 **OpenAPI-first** 的 MoonBit Web 框架。它的单一事实来源（single source of truth）是 OpenAPI YAML 文件，而不是业务代码中的注解或路由声明。

目标不是在 MoonBit 中复刻 Python FastAPI 的语法，而是复刻它的核心体验：

- 强类型的请求与响应模型
- 最小样板代码的接口实现方式
- 自动完成请求解析、校验、序列化与路由绑定
- 从契约出发生成服务骨架，避免手写重复代码

因此，`mapi` 的基本工作流是：

1. 用户编写 `openapi.yaml`
2. `mapi` CLI 读取 spec 并生成 MoonBit 项目骨架与类型安全的服务接口
3. 用户只在受保护的实现目录中填写 handler 逻辑
4. MoonBit runtime lib 提供路由、请求解析、响应编码、错误处理与宿主集成
5. 重新生成时，生成代码可覆盖，用户代码不被覆盖

这个框架本质上是一个 **契约驱动的应用脚手架系统**，由两部分组成：

- `mapi-cli`：负责解析 OpenAPI、生成代码、校验生成结果、管理 regen
- `mapi-lib`：负责运行时抽象、请求/响应类型、路由分发、中间件、错误模型、宿主桥接

## 1.1 当前仓库基线

当前仓库还是一个非常早期的 MoonBit skeleton：

- `moon.mod.json` 已存在，但尚未声明依赖
- `lib/` 目前只有一个 `hello()` stub
- `main/` 目前只有一个打印 `mapi` 的入口
- 没有 OpenAPI、YAML、HTTP、codegen 相关实现
- CI 已具备 `moon check` / `moon fmt --check` / `moon build` / `moon test`

这意味着 `design.md` 的任务不是解释已有实现，而是给出一条 **从最小 MoonBit 模板演进到 OpenAPI-first 框架** 的可执行蓝图。

## 2. 设计原则

### 2.1 Spec-first，不做 code-first 回推

V1 明确只支持 **OpenAPI -> MoonBit code** 的单向生成链路，不支持从 MoonBit handler 再反推 OpenAPI。这样可以保证契约始终是唯一真相源。

### 2.2 生成代码与业务代码隔离

所有可再生内容放到 `gen/` 或 `_generated/` 目录；所有用户编写内容放到 `impl/`、`app/` 或 `handlers/` 目录。CLI 必须做到 **可重复生成且不破坏用户代码**。

### 2.3 运行时保持薄层

运行时只做协议与框架工作：

- 路由匹配
- 请求解码
- 参数组装
- 响应编码
- 错误映射
- 中间件链

业务能力（数据库、鉴权策略、服务调用）由用户应用层自行组合。

### 2.4 先做可落地子集，再扩展规范覆盖率

V1 不追求完整 OpenAPI 3.1 覆盖，而是先支持最有业务价值的一组能力，使生成链路从 day 1 就能跑通。

## 3. 非目标

以下内容不属于 V1：

- 完整 OpenAPI 3.1 全特性支持
- 从 MoonBit 代码自动反向生成 OpenAPI
- WebSocket / SSE / streaming response
- multipart file upload/download 的完整支持
- OpenAPI callbacks / links / webhooks
- 自动 ORM、自动数据库迁移、自动鉴权 provider 集成
- 像 FastAPI 一样的 decorator/annotation 风格 API

## 4. 核心架构决策

### 决策 A：CLI 与 runtime 分离

`mapi` 分为两个独立产品面：

1. **CLI**：负责“理解 OpenAPI 并产出 MoonBit 代码”
2. **lib**：负责“运行这些代码”

这样做的原因是两类问题完全不同：

- OpenAPI/YAML 解析是生态工具问题
- 请求分发/响应编码是运行时问题

如果混在一起，CLI 的解析复杂度会污染运行时 API，反过来也会让 runtime 很难保持稳定。

进一步地，整体系统按三个阶段来理解最清晰：

1. **Codegen-time**：读取 OpenAPI，生成 MoonBit 代码与工程骨架
2. **Compile-time**：`moon check/build/test`，让类型不匹配尽早暴露
3. **Runtime**：宿主接收请求，runtime 执行路由与 handler

这三段职责必须严格分层，不能把 spec 解析逻辑泄漏到 runtime。

### 决策 B：CLI 不要求用 MoonBit 实现

V1 推荐 **CLI 使用成熟生态语言实现**（优先 Rust，其次 TypeScript/Node），而不是强行用 MoonBit 实现。

原因：

- OpenAPI 解析、YAML 解析、模板渲染、文件系统操作在 Rust/TS 生态更成熟
- MoonBit 当前更适合承载业务运行时代码，而不是承担完整 OpenAPI 工具链
- 这样能显著降低 V1 风险，把 MoonBit 资源集中在运行时和类型模型上

这并不影响产品定位，因为生成目标仍然是 MoonBit，最终用户仍然以 MoonBit 为主语言开发服务。

### 决策 C：MoonBit runtime 通过 Host Adapter 挂接 HTTP 宿主

V1 不要求 MoonBit 直接实现底层 HTTP 服务器，而是采用 **Host Adapter** 架构：

- 宿主进程负责监听 socket、接收原始 HTTP 请求
- 宿主把标准化请求对象传给 `mapi-lib`
- `mapi-lib` 执行路由、解码、校验、handler 调用、响应编码
- 宿主再把标准化响应对象写回网络

这意味着 `mapi-lib` 的核心边界不是 socket API，而是：

- `RequestEnvelope`
- `ResponseEnvelope`
- `HostContext`
- `AppService`

这样设计的好处：

- 避免把 V1 卡死在 MoonBit HTTP 生态成熟度上
- 同一个 runtime 可被不同宿主复用（native host、Node host、wasm host）
- 单元测试可以直接对标准化请求做测试，而不必启动真实网络栈

### 决策 D：代码生成采用 “generated contract + user implementation” 模型

CLI 生成两类代码：

1. **Contract 层（可再生）**
   - schema types
   - operation input/output types
   - 路由注册代码
   - handler trait / interface / record contract
   - 请求解析与响应编码胶水代码

2. **Implementation 层（用户维护）**
   - 每个 operation 的具体 handler
   - 应用装配逻辑
   - 中间件配置
   - 基础设施依赖注入

CLI 在首次生成时会创建缺省 handler 文件；后续 regen 只重写 generated 层，并为缺失的用户实现生成新的 stub，不覆盖已有用户文件。

这里采用的是接近 Generation Gap / Strict Server Interface 的思路，但按 MoonBit 能力做适配：

- generated 层生成稳定的输入输出类型和 handler contract
- user 层只实现 contract，不依赖模板细节
- runtime 只依赖 generated 后的 MoonBit 类型，不在运行时读取 OpenAPI

也就是说，**generated code 必须是 model-ignorant 的运行时代码**：一旦生成完成，运行时不需要持有或解释原始 spec。

### 决策 E：路由生成优先基于 operationId

V1 要求每个可生成 endpoint 都有稳定的 `operationId`。`operationId` 是生成 handler 名称、文件名、类型名与测试名的主键。

例如：

- `listPets` -> `ListPetsInput`
- `listPets` -> `ListPetsOk`
- `listPets` -> `list_pets_handler.mbt`

这样可以避免仅通过 `GET /pets/{id}` 这类路径推导名字时产生不稳定结果。

## 5. 总体系统边界

```text
openapi.yaml
   |
   v
mapi-cli
   |
   +--> parse + validate + normalize OpenAPI
   |
   +--> generate MoonBit generated packages
   |
   +--> scaffold user-owned implementation packages
   v
MoonBit app project
   |
   +--> depends on mapi-lib
   +--> imports generated contracts
   +--> imports user handlers
   v
Host Adapter
   |
   +--> HTTP server / runtime / process host
   v
Network
```

### 关键模块分层

```text
spec layer
  - OpenAPI YAML

codegen layer
  - parser
  - normalizer
  - naming
  - type mapper
  - template renderer
  - manifest updater

generated app layer
  - schemas
  - operations
  - routers
  - server contract

user app layer
  - handlers
  - services
  - middleware config
  - app bootstrap

runtime layer
  - request/response model
  - router runtime
  - codec contracts
  - validation hooks
  - error model
  - host adapter boundary
```

## 6. 包结构建议

### 仓库级别

建议最终把仓库拆成以下逻辑模块：

```text
mapi/
  moon.mod.json
  design.md
  README.md
  lib/
    runtime/
    http/
    json/
    validation/
    errors/
    middleware/
    host/
  cli/
    (可单独语言实现，也可独立子仓库)
  examples/
    petstore/
    todo/
  templates/
    app/
    generated/
  specs/
    petstore.yaml
```

### 生成后的应用结构

`mapi init --spec openapi.yaml` 之后，推荐生成：

```text
my_service/
  moon.mod.json
  openapi.yaml
  app/
    generated/
      moon.pkg
      schemas.mbt
      operations.mbt
      router.mbt
      codecs.mbt
      errors.mbt
      server_contract.mbt
    handlers/
      moon.pkg
      list_pets.mbt
      create_pet.mbt
    bootstrap/
      moon.pkg
      app_main.mbt
  tests/
    generated_contract_test.mbt
    integration_test.mbt
```

其中：

- `app/generated/`：CLI 全权管理，可覆盖
- `app/handlers/`：用户拥有，不覆盖
- `app/bootstrap/`：用户可控，用于装配依赖和 host

### 6.1 从当前仓库到目标结构的演进建议

考虑到当前仓库只有 `lib/` 和 `main/` 两个最小包，建议分两步演进，而不是一次性重构到底：

#### Step 1：保留现有骨架，先把 runtime 做出来

```text
mapi/
  lib/
    core.mbt
    http.mbt
    router.mbt
    server.mbt
    testing.mbt
  main/
    main.mbt
```

先在现有 `lib/` 中验证 request/response、router、middleware、in-memory host 这些抽象，降低初期目录迁移成本。

#### Step 2：当 runtime API 稳定后，再细分子包

```text
lib/core/
lib/http/
lib/router/
lib/codec/
lib/server/
lib/testing/
```

这样更贴合 MoonBit 按目录分包的组织方式，也更利于发布独立 runtime API。

## 7. CLI 设计

## 7.1 CLI 子命令

建议提供以下命令：

### `mapi init`

用途：从 spec 初始化项目。

示例：

```bash
mapi init --spec ./openapi.yaml --out ./my_service
```

职责：

- 校验 OpenAPI 文件是否可解析
- 初始化 MoonBit 项目结构
- 生成全部 generated 文件
- 为每个 operation 生成初始 handler stub
- 生成示例 bootstrap

### `mapi generate`

用途：在已有项目上重新生成 generated 层。

示例：

```bash
mapi generate --spec ./openapi.yaml --project ./my_service
```

职责：

- 比较当前 spec 与上次生成快照
- 仅重写 generated 层
- 检查是否有新增/删除 operation
- 为新增 operation 创建 handler stub
- 对被删除 operation 给出迁移提醒

### `mapi check`

用途：做 spec 与项目的一致性检查。

职责：

- 检查 handler 是否完整实现
- 检查 operationId 是否冲突
- 检查类型命名冲突
- 检查生成输出是否脏（未重新生成）

### `mapi diff`

用途：展示 spec 改动会影响哪些 generated/user contract。

这对团队协作很重要，因为 OpenAPI 改动往往会影响 handler 签名。

### `mapi doctor`

用途：检查运行环境与生成前置条件。

职责：

- 检查 MoonBit 工具链是否存在
- 检查项目是否存在 `.mapi/state.json`
- 检查模板版本与 CLI 版本是否兼容
- 检查 spec 是否使用了 V1 不支持的 OpenAPI 特性

## 7.2 CLI 内部流水线

CLI 内部推荐做成 6 个阶段：

1. `load_spec`
2. `validate_spec`
3. `normalize_spec`
4. `build_ir`
5. `render_files`
6. `write_manifest_and_lock`

其中最关键的是 **IR（intermediate representation，中间表示）**。不要直接从 OpenAPI AST 渲染模板，而是先转成框架内部 IR。

IR 推荐包含：

- `ApiModel`
- `SchemaModel`
- `OperationModel`
- `ParameterModel`
- `RequestBodyModel`
- `ResponseModel`
- `SecurityModel`

这样可以把 “OpenAPI 的复杂性” 隔离在 parser/normalizer 层，把模板层简化成稳定的结构化渲染。

## 8. Runtime lib 设计

## 8.1 核心运行时对象

V1 runtime 需要围绕以下抽象展开：

- `RequestEnvelope`
- `ResponseEnvelope`
- `PathParams`
- `QueryParams`
- `HeaderMap`
- `BodyBytes` 或 `JsonValue`
- `RouteHandler`
- `Middleware`
- `App`
- `HostAdapter`

一个典型请求生命周期如下：

1. Host 收到 HTTP 请求
2. Host 构造 `RequestEnvelope`
3. `App` 根据 method + path 匹配 operation
4. generated decoder 解析 path/query/header/body
5. generated glue 把参数组合成 `OperationInput`
6. user handler 执行业务逻辑
7. generated encoder 把 `OperationOutput` 转成 `ResponseEnvelope`
8. Host 把 `ResponseEnvelope` 写回客户端

### 8.1.1 建议的核心接口形状

下面不是最终语法承诺，而是 V1 必须达到的抽象边界：

```text
struct RequestEnvelope {
  method : HttpMethod
  path : String
  query : Map[String, Array[String]]
  headers : Map[String, String]
  body : Bytes?
}

struct ResponseEnvelope {
  status : Int
  headers : Map[String, String]
  body : Bytes?
}

struct RequestContext {
  request_id : String
  matched_operation : String
  host_context : HostContext
}

type RouteHandler = (RequestContext, RequestEnvelope) -> ResponseEnvelope
type Middleware = RouteHandler -> RouteHandler

trait AppService {
  serve(req : RequestEnvelope, host : HostContext) -> ResponseEnvelope
}
```

真正生成给用户的 operation handler 则应该比 `RouteHandler` 更强类型：

```text
handle_list_pets(ctx : RequestContext, input : ListPetsInput)
  -> Result[ListPetsResponse, AppError]
```

runtime 负责把弱类型 HTTP 信封转换成强类型 operation contract。

## 8.2 Handler 合约

V1 推荐 handler 以“显式函数签名”暴露，而不是魔法注解。

例如对一个 operation：

```text
handle_list_pets(ctx, input) -> Result[ListPetsResponse, AppError]
```

其中：

- `ctx`：请求级上下文、trace、宿主注入对象
- `input`：已通过生成代码解析好的强类型入参
- 返回值：OpenAPI 声明过的响应联合类型

这样可以保持：

- 强类型
- 易测试
- 低反射依赖
- 不依赖 MoonBit 的宏/注解能力

### 8.2.1 推荐的 generated contract 形状

V1 推荐生成“服务契约记录”而不是要求用户理解复杂框架注册 API。概念上类似：

```text
struct PetApiHandlers {
  list_pets : (RequestContext, ListPetsInput) -> Result[ListPetsResponse, AppError>
  create_pet : (RequestContext, CreatePetInput) -> Result[CreatePetResponse, AppError>
}
```

然后 generated router 只负责把 `operationId` 映射到这个记录里的对应函数。这样做有三个好处：

- 用户看到的是普通函数签名，不是魔法 trait 系统
- 单元测试可以直接替换某个 handler 函数
- regen 时 contract 稳定，装配点也稳定

## 8.3 中间件模型

中间件建议设计成包裹 `RouteHandler` 的高阶函数：

```text
Middleware = RouteHandler -> RouteHandler
```

这允许实现：

- logging
- auth
- tracing
- timeout
- panic/error normalization

同时也比注解式 DI 更贴近 MoonBit 当前的语言能力。

## 9. OpenAPI 到 MoonBit 的类型映射

V1 建议先支持以下映射：

| OpenAPI | MoonBit | 说明 |
|---|---|---|
| `string` | `String` | 基础字符串 |
| `integer` | `Int` | 默认使用有符号 Int |
| `number` | `Double` | 浮点数 |
| `boolean` | `Bool` | 布尔 |
| `array<T>` | `Array[T]` | 数组 |
| `object` with fixed properties | `struct` | 生成命名 struct |
| nullable schema | `T?` | `Some/None` |
| enum string | MoonBit `enum` 或受限别名 | 优先生成 enum |
| `$ref` | 命名类型引用 | 指向 generated schema type |
| map-like object (`additionalProperties`) | `Map[String, T]` | V1 可选支持 |

### 9.1 V1 支持的 schema 子集

- primitives
- object
- array
- `$ref`
- string enum
- nullable
- nested object

### 9.2 V1 暂不支持或降级处理

- `oneOf`
- `anyOf`
- `allOf` 的完整组合继承
- `discriminator`
- patternProperties
- deeply polymorphic unions

对于这些高级特性，V1 应明确报错，而不是悄悄生成错误代码。

### 9.3 V1 支持矩阵

| 能力 | V1 结论 | 说明 |
|---|---|---|
| OpenAPI 版本 | 支持 3.0.x，部分兼容 3.1 | 先以 3.0.x 为主路径 |
| `operationId` | 必需 | 缺失时 CLI 报错 |
| path params | 支持 | 必须可解析到强类型 |
| query params | 支持 | 先支持 primitive / array |
| header params | 支持 | 先支持常规字符串/布尔/数字 |
| cookie params | 暂不支持 | 可在 V1.1 扩展 |
| JSON request body | 支持 | 主路径能力 |
| non-JSON body | 暂不支持 | 明确报错 |
| JSON response | 支持 | 主路径能力 |
| multiple success responses | 有限支持 | 允许多个 status，但都必须能静态建模 |
| `oneOf/anyOf/allOf` | 暂不支持 | 避免错误生成 |
| file upload | 暂不支持 | 不纳入 V1 |
| security schemes | 透传建模，不做完整执行 | 先用于生成中间件钩子 |

## 10. 响应与错误模型

每个 operation 的返回值必须映射到 **有限响应集合**。不要让 handler 直接返回任意 `ResponseEnvelope`，否则会失去契约约束。

更好的方式是生成 operation 级响应类型，例如：

- `ListPetsResponse::Ok(Array[Pet])`
- `ListPetsResponse::BadRequest(ErrorBody)`
- `ListPetsResponse::Unauthorized(ErrorBody)`

运行时统一把这些响应类型编码成：

- HTTP status
- headers
- serialized body

### 错误分层

建议错误分为三层：

1. **DecodeError**：请求不符合 OpenAPI 输入约束
2. **AppError**：业务逻辑返回的领域错误
3. **InternalError**：框架或宿主错误

并由统一错误映射器把它们转成 OpenAPI 响应或通用 500 响应。

### 10.1 错误到响应的映射原则

- `DecodeError` 默认映射到 `400 Bad Request`
- 缺失认证信息可映射到 `401 Unauthorized`
- 中间件拒绝访问可映射到 `403 Forbidden`
- 未捕获 `AppError` 若有显式映射，则按 operation 声明输出；否则落到统一 `500`
- `InternalError` 永远不把内部堆栈直接暴露给客户端

## 11. 代码生成策略

### 11.1 生成文件分类

建议约定文件头：

- generated 文件带 `// Code generated by mapi. DO NOT EDIT.`
- user 文件带 `// User-owned file. Safe from regeneration.`

### 11.2 Regen 策略

`mapi generate` 执行时：

- 始终重写 `app/generated/*`
- 从不重写 `app/handlers/*` 已存在文件
- 若 spec 新增 operation，则新增对应 handler stub
- 若 spec 删除 operation，则 CLI 报告 orphaned handler，由用户决定是否清理

### 11.3 Manifest 与快照

建议 CLI 维护一个内部元数据文件，例如：

```text
.mapi/state.json
```

记录：

- 上次生成的 spec hash
- operationId 列表
- 已生成文件索引
- CLI 版本
- codegen schema version

这样便于实现增量生成、兼容性检查与升级迁移。

## 12. Host Adapter 设计

V1 推荐先定义宿主接口，而不是先绑定某一种 HTTP 实现。

### Host 负责

- 监听网络端口
- 接收 HTTP 请求
- 把请求转换为 runtime 认可的 envelope
- 执行 app
- 把响应写回客户端

### Runtime 负责

- 路由匹配
- OpenAPI 输入解析
- handler 调度
- 输出编码
- 中间件执行

### 12.1 精确边界：Host 与 Runtime 之间交换什么

V1 文档层面应直接锁定下面这个边界，而不是只写“某种 adapter”：

#### Host -> Runtime

- `method : String`
- `path : String`
- `raw_query : String` 或已解析 query map
- `headers : Map[String, String]`
- `body : Bytes?`
- `remote_addr : String?`
- `request_id : String?`

#### Runtime -> Host

- `status : Int`
- `headers : Map[String, String]`
- `body : Bytes?`

换句话说，runtime 不拥有 socket，不拥有监听循环；runtime 只拥有一次请求的纯逻辑执行权。

### 12.2 推荐的最小宿主接口

概念上建议固定成这样的调用方式：

```text
host.listen(addr, fn(raw_req) {
  let req = host.to_request_envelope(raw_req)
  let resp = app.serve(req, host.make_context(raw_req))
  host.write_response(raw_req, resp)
})
```

只要这个 shape 成立，未来换 Node、native、Wasm embedding 都不会推翻 runtime 核心。

### 推荐的 V1 宿主路线

优先级建议：

1. **测试宿主 / in-memory host**：最先实现，便于验证 runtime 核心
2. **简单 HTTP host adapter**：作为 demo 与 examples 的运行方式
3. **后续再扩展 wasm/native 特定 host**

这样可以先验证框架核心，而不是一开始被网络层和部署细节拖慢。

## 13. 开发者体验设计

为了接近 FastAPI 的体验，V1 应优先提供以下 DX 能力：

### 13.1 零手写路由

用户不手写 path/method 到 handler 的绑定。绑定关系全部来自 spec 与生成代码。

### 13.2 零手写 DTO

请求/响应 DTO 由 OpenAPI schema 生成，不要求用户重复定义。

### 13.3 明确的编译期失败点

当 spec 发生破坏性变更时，用户应该在 `moon check` 阶段直接看到 handler 签名不匹配，而不是运行时才发现。

### 13.4 自动文档静态资源

由于 OpenAPI 已经是源头，Swagger UI / Redoc 类型的文档托管能力可以作为 V1.1 或 V2 扩展，但不阻塞 V1 核心。

## 14. 推荐的 V1 范围

V1 建议聚焦在 CRUD 风格 JSON API：

- HTTP methods: `GET`, `POST`, `PUT`, `PATCH`, `DELETE`
- content-type: `application/json`
- parameters: path/query/header
- request body: JSON object/array
- response body: JSON
- error body: JSON

只要这条主路径打通，就已经足够支撑大部分内部服务与工具型 API。

## 15. 一个端到端例子

### 15.1 输入 spec

```yaml
openapi: 3.0.3
info:
  title: Pet API
  version: 1.0.0
paths:
  /pets:
    get:
      operationId: listPets
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: array
                items:
                  $ref: '#/components/schemas/Pet'
components:
  schemas:
    Pet:
      type: object
      required: [id, name]
      properties:
        id:
          type: integer
        name:
          type: string
```

### 15.2 生成结果（概念）

CLI 生成：

- `schemas.mbt`：`Pet`
- `operations.mbt`：`ListPetsInput`, `ListPetsResponse`
- `server_contract.mbt`：要求实现 `handle_list_pets`
- `router.mbt`：把 `GET /pets` 绑定到 `listPets`
- `handlers/list_pets.mbt`：用户 stub

### 15.3 用户实现（概念）

用户只需要写：

```text
handle_list_pets(ctx, input) -> Ok([...])
```

不需要手写：

- DTO
- router
- status code 编码
- JSON 序列化胶水

### 15.4 生成代码的概念形状

生成层应该尽量接近普通 MoonBit 代码，而不是“模板味”很重的巨型文件。概念上可以长这样：

```text
// app/generated/operations.mbt
struct ListPetsInput {}

enum ListPetsResponse {
  Ok(Array[Pet])
}

// app/generated/server_contract.mbt
struct PetApiHandlers {
  list_pets : (RequestContext, ListPetsInput) -> Result[ListPetsResponse, AppError>
}

// app/generated/router.mbt
fn serve_list_pets(ctx, req, handlers) {
  let input = decode_list_pets_input(req)
  let result = handlers.list_pets(ctx, input)
  encode_list_pets_response(result)
}
```

而用户层则保持极薄：

```text
// app/handlers/list_pets.mbt
pub fn list_pets(ctx, input) {
  Ok(ListPetsResponse::Ok([
    { id: 1, name: "fubao" },
  ]))
}
```

重点是：**用户实现的是业务函数，不是框架机制。**

## 16. 验证与验收标准

设计不是停留在概念图，必须能落到可验证结果。V1 每项关键决策都应有对应验证方式。

### 16.1 生成层验证

- `mapi init --spec ./specs/petstore.yaml --out ./examples/petstore`
- 预期：生成完整 MoonBit 项目骨架，且没有覆盖用户文件的风险

### 16.2 编译验证

- 在生成项目中执行 `moon check`
- 预期：generated code 与初始 stub 可通过类型检查

### 16.3 测试验证

- 执行 `moon test`
- 预期：in-memory host 可以驱动至少一个成功请求和一个 4xx 请求

### 16.4 回归生成验证

- 修改 `openapi.yaml`，新增一个 operation
- 执行 `mapi generate`
- 预期：generated 层更新，新增 handler stub 出现，已有 handler 文件保持不变

### 16.5 破坏性变更验证

- 修改某个 operation 的响应或必填参数
- 执行 `moon check`
- 预期：用户实现编译失败，错误明确指向签名不兼容的位置

## 17. 实施路线图

### Phase 0：文档与边界确认

- 锁定 V1 OpenAPI 子集
- 锁定 host adapter 边界
- 锁定 generated/user code 分层

### Phase 1：Runtime Core

- 定义 request/response envelope
- 定义 router runtime
- 定义 middleware 抽象
- 定义 operation response 编码模型
- 实现 in-memory host

### Phase 2：Codegen MVP

- 实现 OpenAPI parser + normalizer
- 建立内部 IR
- 生成 schema / operation / router / contract
- 支持初始项目脚手架

### Phase 3：Developer Workflow

- `init`, `generate`, `check`, `diff`
- `.mapi/state.json`
- handler stub 管理

### Phase 4：Examples 与稳定性

- petstore example
- todo example
- 回归测试样例
- 破坏性变更提示优化

## 18. 推荐的初始工程拆分

如果从当前仓库开始演进，建议先按责任拆出以下 MoonBit 包：

- `lib/core`：基础类型、errors、shared model
- `lib/http`：request/response envelope
- `lib/router`：路径匹配与 handler dispatch
- `lib/codec`：JSON codec contract
- `lib/server`：App / middleware / execution pipeline
- `lib/testing`：in-memory host 与测试 helper

CLI 则独立为：

- `cli/parser`
- `cli/normalizer`
- `cli/ir`
- `cli/generator`
- `cli/project`

## 18.1 外部模式对本设计的启发

本设计显式吸收了几类成熟工具链的做法，但做了 MoonBit 适配：

- **Smithy 风格三阶段架构**：把 codegen-time、compile-time、runtime 分开
- **oapi-codegen 的 strict server 思路**：生成强类型 handler contract，而不是要求用户手写框架适配
- **Generation Gap**：generated 层与 user 层严格隔离，避免 regen 覆盖业务代码
- **模板插件化思路**：后续可以把 schema、router、tests、docs 生成为独立 renderer，而不是一个超大模板器

这几种模式共同指向一个原则：`mapi` 不应让“OpenAPI 解释器”存在于运行时，而应在生成阶段就把它编译成普通 MoonBit 应用结构。

## 19. 下一步实现建议

如果按照当前仓库状态推进，最合理的起步顺序是：

1. 先在 `lib/` 里实现 `RequestEnvelope` / `ResponseEnvelope` / `App` / `Middleware` / in-memory host
2. 用手写的假 `generated` 示例验证 runtime API 是否顺手
3. 再实现 CLI 的 IR 与最小模板渲染，只覆盖一个 petstore 级别例子
4. 最后把 `mapi init` 和 `mapi generate` 接上真实项目脚手架

这样做的原因是：如果 runtime contract 没有先稳定，任何 codegen 都会很快失效；而如果先有稳定 runtime，codegen 只是在往这个 contract 上填数据。

## 20. 最终结论

`mapi` 最合理的产品形态不是“MoonBit 版 FastAPI 语法糖”，而是：

> **一个以 OpenAPI YAML 为唯一契约源、通过 CLI 生成 MoonBit 强类型服务骨架、并由轻量 runtime 承载执行的契约优先框架。**

V1 最重要的不是功能多，而是先把三件事做稳：

1. OpenAPI 子集清晰
2. generated code 与 user code 严格隔离
3. runtime 与 host 的边界稳定

一旦这三点成立，后续再逐步扩展更多 OpenAPI 特性、更多 host、更多开发体验能力，框架就会沿着一条非常清晰的演进路线成长。
