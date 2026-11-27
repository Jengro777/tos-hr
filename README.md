# Tospino-HR

这是一个对接企业微信“获取打卡记录数据”接口的 Flutter 应用：

- 接口文档：<https://developer.work.weixin.qq.com/document/path/90262>
- 查询类型：上下班打卡、外出打卡、全部打卡
- 支持从统计起点开始生成月报、年报和历史汇总
- 打卡数据统一保存到 TiDB，打卡明细和统计页面都只读取数据库
- 自动获取并缓存 `access_token`，失效时自动刷新并重试一次
- 加载、搜索并选择当前打卡应用可见范围内的成员
- 支持手机号或企业/个人邮箱换取成员 UserID
- 支持单次 1～100 个 UserID、最长 30 天的时间范围校验

## 配置

应用启动后先进入登录页。当前使用写死的账号与密码摘要进行校验，源码中不保存密码明文；校验采用固定盐值、SHA-256 摘要和常量时间比较。

Debug 构建的登录页会显示“Debug 跳过登录”按钮，Release 构建不显示。正式使用前应将认证迁移到服务端。

本地 Debug 使用单一 YAML 文件 `config/app.local.yaml`，企业微信与 TiDB 配置都放在这里。该文件已加入 `.gitignore`，不会上传到 Git 仓库：

```bash
open config/app.local.yaml
```

配置结构如下。`contact_secret` 不是必需项；需要走通讯录同步接口时再自行添加：

```yaml
wecom:
  corp_id: 企业ID
  agent_id: AgentId
  secret: 应用Secret

database:
  host: TiDB主机
  port: 4000
  username: TiDB用户名
  password: TiDB密码
  database: 数据库名
  ssl_verify: true
  ssl_ca_file: client-cert.pem
```

需要恢复模板时，可以复制 `config/app.example.yaml`。

`ssl_ca_file` 相对于 YAML 文件所在目录解析。Debug 启动时直接读取
`config/client-cert.pem` 并用于 TLS 校验，不把整段 PEM 写入 Dart 编译参数，
避免 Linux 构建把证书内容误判为文件路径。

同步 API 提供两个 GET 接口：

```text
GET /api/attendance/sync/full
GET /api/attendance/sync/incremental
```

请求必须携带 `X-Api-Token` 请求头，或使用 `?token=...` 查询参数。设置页会显示当前设备可用地址和复制按钮。

同步 API 的端口、主机和访问令牌不放在本地 YAML 中；如需启用，通过编译参数
`SYNC_API_ENABLED`、`SYNC_API_HOST`、`SYNC_API_PORT` 和 `SYNC_API_TOKEN` 注入。

Flutter 不直接读取 YAML 作为 `dart-define`，项目提供了转换脚本。`just run` 会自动执行转换：

```bash
just run
```

也可以手动运行：

```bash
flutter pub get
dart run tool/dart_defines.dart
flutter run \
  --dart-define-from-file=.dart_tool/local_dart_defines.json
```

正式环境不读取本地 YAML，直接注入环境变量：

```bash
flutter build apk \
  --dart-define=WECOM_CORP_ID=... \
  --dart-define=WECOM_AGENT_ID=... \
  --dart-define=WECOM_SECRET=... \
  --dart-define=DB_HOST=... \
  --dart-define=DB_PORT=4000 \
  --dart-define=DB_USERNAME=... \
  --dart-define=DB_PASSWORD=... \
  --dart-define=DB_DATABASE=... \
  --dart-define=DB_SSL_VERIFY=true \
  --dart-define=SYNC_API_ENABLED=true \
  --dart-define=SYNC_API_HOST=0.0.0.0 \
  --dart-define=SYNC_API_PORT=9010 \
  --dart-define=SYNC_API_TOKEN=...
```

## 企微侧权限

1. 在企业微信管理后台创建自建应用并获取企业ID、AgentId、Secret。
2. 将应用配置到“打卡 - 可调用接口的应用”。
3. 确保应用可见范围包含要查询的成员。
4. 在应用详情中启用需要的 Secret，并从通讯录成员详情获取对应的 UserID。

AgentId 作为应用配置保存在本地并显示在配置状态中；“获取打卡记录数据”请求本身只使用 `access_token`、打卡类型、时间范围和 UserID 列表。

`WECOM_SECRET` 是打卡应用自己的 Secret；`WECOM_CONTACT_SECRET` 是管理后台“通讯录同步”的 Secret。

成员加载采用双通道：

- 配置了通讯录同步 Secret 时，通过[获取成员 ID 列表](https://developer.work.weixin.qq.com/document/path/96067)分页加载。
- 未配置时，通过自建应用的“获取部门列表”和“获取部门成员”接口加载其可见范围成员，不要求停用第三方通讯录同步。应用可见范围需要包含目标成员。

查询成员时也可以使用[手机号获取 UserID](https://developer.work.weixin.qq.com/document/path/95402)或[邮箱获取 UserID](https://developer.work.weixin.qq.com/document/path/95895)。注意企业微信限制：错误查询次数超过企业人数的 20% 时，对应接口会暂停调用 1 天。

“月报”“年报”和“历史汇总”只读取 TiDB。数据同步统一放在页面右上角的“设置”中：

查询条件按报表类型收紧：

- `月报`：直接查看所选自然月拉取的企业微信月报原数据。
- `年报`：按成员汇总所选年份各月的企业微信月报数据。
- `历史汇总`：默认统计所有成员从首条打卡记录日到今天的全部数据，也可以手动选择开始日期和结束日期；该范围使用每日原始打卡按月报口径重新统计。

以上三种报表均以当前应用可见范围的全部成员为数据范围；人员、规则和部门条件放在结果表内用作筛选。

企业微信通讯录接口不直接返回入职日期，因此应用以所选统计范围内成员的**首条打卡记录**作为统计起点。需要严格按人事入职日统计时，应由业务系统补充入职日期字段。

打卡明细按自然月拆成 `1-15 日`和 `16 日-月末`两个窗口，企业微信打卡接口明确规定单次查询跨度不能超过 30 天；月报接口按完整自然月单独拉取，每个成员每月保存一份月报原数据。

- `增量获取打卡记录`：只按最新打卡时间补齐缺失的打卡周期。
- `增量获取月报`：只按最新月报周期补齐缺失的自然月；旧版半月快照或其他未覆盖完整自然月的快照会被视为不完整并重新拉取整月。
- `增量同步全部数据`：同时补齐打卡记录和月报，以两者中更早的周期为起点。
- `全量覆盖全部数据`：重新拉取全部成员从 `2018-01` 至当前月份的打卡记录和月报。执行前必须原样输入“我已知晓全量获取时间较长，期间不可离开页面”，获取期间显示不可关闭的进度窗口。

同步内容包含：

- 全部类型的打卡明细。
- 企业微信月度考勤报告快照。
- 每次同步的开始时间、完成状态、成员数、写入量和错误信息。

月报按成员、按自然月展示企业微信返回的月报原数据；点击成员可查看基础信息、汇总、假勤统计、异常统计、加班字段，以及关联的当月原始打卡明细。年报按成员累加各月月报。历史汇总不直接累加月报，而是按企业微信月报的统计口径，从所选范围的每日原始打卡重新计算应出勤、实际出勤、正常、异常和工时字段。两套数据分别保存，不会互相覆盖。

成员超过 100 人时自动分批请求。月报表按“月份 + 成员”展示，年报表按“年份 + 成员”展示。全量表默认使用 TiDB 中第一条打卡记录日期到今天，也支持任意日期范围筛选；该视图按日精确统计打卡记录数、出勤日期数、异常次数和异常日期数。所有表都支持成员、规则、部门搜索以及“仅看有异常成员”筛选，底部合计会随筛选结果更新。重复同步同一半月周期时会覆盖对应数据，不会重复累计。

mysql 驱动不支持 Flutter Web 的原始 socket 连接，因此 Web 版本通过
Cloudflare Pages Functions 代理企业微信和 TiDB。`实际出勤天数`按真实“上班打卡/下班打卡”
的唯一日期计算，排除企业微信标记为“未打卡”的排班占位记录，外出记录不计入。
应出勤天数和标准工时来自企业微信月报，不使用排班占位记录推测。

项目不再使用 SQLite：桌面端直连 TiDB，Web 端通过 Cloudflare Pages Functions
代理访问同一个 TiDB 数据库。

## 项目结构

```text
lib/
  config/        编译期配置读取与校验
  data/          打卡数据模型和异常类型
  services/      企业微信 token、请求、缓存与错误处理
  screens/       查询表单和结果页面
functions/       Cloudflare Pages Functions 生产 API
```

## 验证

```bash
flutter analyze
flutter test
```

## 发布到 Cloudflare Pages

推送到 `main` 或发布 GitHub Release 后，[`Deploy to Cloudflare Pages`](.github/workflows/deploy-cloudflare-pages.yml)
工作流会检出对应版本代码，构建 Flutter Web 发布包，并将 `build/web` 部署到
Cloudflare Pages 项目 `tos-hr`。部署归属 `main` 分支，因此会更新生产站点。
Actions 页面会分别显示 `Build Web` 和 `Deploy Cloudflare` 两个 Job。

首次使用前需要：

1. 创建具有“Account > Cloudflare Pages > Edit”权限的 Cloudflare API Token。
2. 在 GitHub 仓库的 `Settings > Secrets and variables > Actions` 中添加：

   - `CLOUDFLARE_API_TOKEN`（必需）
   - `CLOUDFLARE_ACCOUNT_ID`（Token 可访问多个账号时必需）

粘贴 `CLOUDFLARE_API_TOKEN` 时只填写 Token 本身，不要包含 `Bearer`、引号或换行。

工作流会自动检查 Pages 项目 `tos-hr`，不存在时创建项目并将生产分支设置为
`main`；项目已存在时直接使用。未配置 `CLOUDFLARE_ACCOUNT_ID` 时，如果 Token
只能访问一个账号，工作流会自动读取该账号 ID。配置值格式无效时，工作流也会
忽略该值并尝试自动读取。

生产环境由同一仓库中的 Cloudflare Pages Functions 读取运行时变量。浏览器请求
同域 `/api/runtime-config`、`/api/wecom` 和 `/api/db`，不会收到企业微信 Secret
或数据库密码。部署工作流会同时上传 `build/web` 和 `functions/`。

### Cloudflare Access

数据库 API 必须由 Cloudflare Access 保护。在 Cloudflare Zero Trust 中为
`tos-hr` 的 Production 环境添加 Access Application，并仅允许公司账号或指定邮箱
访问整个站点。Pages Functions 在缺少 Access 身份头时默认返回 HTTP 401。

如需临时关闭 Function 自身的身份头检查，只能用于受控测试：

```text
CLOUDFLARE_ACCESS_REQUIRED=false
```

不要在公开生产环境中设置该值。

### 生产变量

在 Pages 项目的 `Settings > Variables and Secrets > Production` 中配置：

| 名称 | 类型 | 说明 |
| --- | --- | --- |
| `WECOM_CORP_ID` | 文本 | 企业 ID |
| `WECOM_AGENT_ID` | 文本 | AgentId；兼容旧名称 `WECOM_AGENT` |
| `WECOM_SECRET` | 密钥 | 打卡应用 Secret |
| `WECOM_CONTACT_SECRET` | 密钥 | 通讯录同步 Secret，可选 |
| `DB_HOST` | 文本 | TiDB Cloud Serverless 主机名，不带协议和端口 |
| `DB_USERNAME` | 密钥 | TiDB 用户名 |
| `DB_PASSWORD` | 密钥 | TiDB 密码 |
| `DB_DATABASE` | 文本 | 数据库名 |

TiDB 代理使用 `@tidbcloud/serverless` 的 HTTP 驱动，不依赖浏览器原始 socket，
也不使用 `mysql1` 直连。保存变量后需要重新部署，Pages Functions 才会读取新值。

发布新版本的流程：

1. 更新 `pubspec.yaml` 中的 `version`，提交并推送代码。
2. 推送到 `main` 后，工作流会自动构建并部署。

也可以额外创建 GitHub Release；发布 Release 同样会触发工作流。

也可以在 Actions 页面手动运行 `Deploy to Cloudflare Pages`，用于重新部署当前分支。

## 安全说明

企业微信 `access_token` 和数据库密码只由 Cloudflare Pages Functions 使用。
Flutter Web 不再读取或编译这些密钥。桌面端直连模式仍按原有本地配置工作。

生产站点必须启用 Cloudflare Access，否则公共数据库 API 会扩大数据暴露范围。
