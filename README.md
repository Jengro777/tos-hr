# Tospino-HR

这是一个对接企业微信“获取打卡记录数据”接口的 Flutter 应用：

- 接口文档：<https://developer.work.weixin.qq.com/document/path/90262>
- 查询类型：上下班打卡、外出打卡、全部打卡
- 支持从统计起点开始生成逐月、分年和历史汇总
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

`ssl_ca_file` 相对于 YAML 文件所在目录解析。当前仓库的 `config/client-cert.pem` 会被转换脚本读取并写入临时 `DB_SSL_CA_PEM` 编译参数，Debug 连接 TiDB 时自动用于 TLS 校验。

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

“月度汇总”“分年汇总”和“历史汇总”只读取 TiDB。数据同步统一放在页面右上角的“设置”中：

查询条件按报表类型收紧：

- `月度报表`：只选择年份和月份。
- `分年汇总`：只选择年份。
- `历史汇总`：默认统计所有成员从首条打卡记录日到今天的全部数据，也可以手动选择开始日期和结束日期。

以上三种报表均以当前应用可见范围的全部成员为数据范围；人员、规则和部门条件放在结果表内用作筛选。

企业微信通讯录接口不直接返回入职日期，因此应用以所选统计范围内成员的**首条打卡记录**作为统计起点。需要严格按人事入职日统计时，应由业务系统补充入职日期字段。

每个自然月固定拆成 `1-15 日`和 `16 日-月末`两个窗口，两个接口单次覆盖范围均不超过 30 天，避免触发 `errcode=301024`。

- `增量获取打卡记录`：跳过已经保存的半月周期，只获取缺失周期；当前尚未结束的半月周期会重新拉取，以补入最新记录。
- `全量获取覆盖打卡记录`：重新拉取全部成员从 `2018-01` 至当前月份的数据。执行前必须原样输入“我已知晓全量获取时间较长，期间不可离开页面”，获取期间显示不可关闭的进度窗口。

同步内容包含：

- 全部类型的打卡明细。
- 每次同步的开始时间、完成状态、成员数、写入量和错误信息。

应用不会同步企业微信月报数据。月度、分年、历史汇总和详情指标全部通过 TiDB SQL 对每日原始打卡记录进行聚合。

成员超过 100 人时自动分批请求。月度表按“月份 + 成员”展示，分年表按“年份 + 成员”展示。全量表默认使用 TiDB 中第一条打卡记录日期到今天，也支持任意日期范围筛选；该视图按日精确统计打卡记录数、出勤日期数、异常次数和异常日期数。所有表都支持成员、规则、部门搜索以及“仅看有异常成员”筛选，底部合计会随筛选结果更新。重复同步同一半月周期时会覆盖对应数据，不会重复累计。

mysql 驱动不支持 Flutter Web 的原始 socket 连接，因此 Web 版本应通过服务端 API 代理 TiDB。`实际出勤天数`按“上班打卡/下班打卡”的唯一日期计算，外出记录不计入。原始打卡数据不包含完整排班日历、职务、工号、应出勤天数和标准工时，因此这些字段不会用推测值填充。

## 项目结构

```text
lib/
  config/        编译期配置读取与校验
  data/          打卡数据模型和异常类型
  services/      企业微信 token、请求、缓存与错误处理
  screens/       查询表单和结果页面
```

## 验证

```bash
flutter analyze
flutter test
```

## 发布到 Cloudflare Pages

GitHub Release 发布后，[`Deploy to Cloudflare Pages`](.github/workflows/deploy-cloudflare-pages.yml)
工作流会检出对应发布标签，构建 Flutter Web 发布包，并将 `build/web` 部署到
Cloudflare Pages 项目 `tos-hr`。部署归属 `main` 分支，因此会更新生产站点。
Actions 页面会分别显示 `Build Web` 和 `Deploy Cloudflare` 两个 Job。

首次使用前需要：

1. 创建具有“Account > Cloudflare Pages > Edit”权限的 Cloudflare API Token。
2. 在 GitHub 仓库的 `Settings > Secrets and variables > Actions` 中添加：

   - `CLOUDFLARE_API_TOKEN`（必需）
   - `CLOUDFLARE_ACCOUNT_ID`（Token 可访问多个账号时必需）

工作流会自动检查 Pages 项目 `tos-hr`，不存在时创建项目并将生产分支设置为
`main`；项目已存在时直接使用。未配置 `CLOUDFLARE_ACCOUNT_ID` 时，如果 Token
只能访问一个账号，工作流会自动读取该账号 ID。

发布新版本的流程：

1. 更新 `pubspec.yaml` 中的 `version`，提交并推送代码。
2. 在 GitHub 创建对应版本标签和 Release。
3. 点击 `Publish release` 后，工作流会自动构建并部署。

也可以在 Actions 页面手动运行 `Deploy to Cloudflare Pages`，用于重新部署当前分支。

## 安全说明

企业微信官方要求 `access_token` 由服务端获取并保存，不应返回给前端。当前实现按客户端直连需求工作，但 Secret 会被编译进应用包，存在被提取的风险，只建议用于内部工具或开发调试。

生产环境应在自有服务端代理企业微信接口：Flutter 只调用业务后端，Secret 和 `access_token` 始终留在服务端。若需要部署 Flutter Web，也应通过服务端代理规避浏览器跨域限制。
