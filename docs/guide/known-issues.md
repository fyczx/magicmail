# 已知问题

记录用户反馈的问题及处理进度。


## 问题列表

### 企业微信邮件中文乱码 (GBK/GB18030 编码)

- **状态**：✅ 已修复未发布
- **记录时间**：2026-07-02
- **问题描述**：接收企业微信邮箱（`@exmail.weixin.qq.com`）的邮件时，邮件正文中的中文字符显示为乱码（如 `浣犲ソ锛岀粏鐣岀箒鏄�`），而标题和发件人/收件人显示正常。该问题仅影响使用 `gb18030`/`gbk` 字符集编码的非 UTF-8 邮件。
- **根因分析**：
  1. Go 标准库 `mime.WordDecoder` 默认只支持 UTF-8，无法解码 RFC 2047 头部中声明的 GBK/GB18030 字符集；
  2. `go-message` 库的全局 `message.CharsetReader` 虽然被正确调用并返回了 GBK 解码器，但其**内部对 CharsetReader 返回值的处理存在缺陷**，导致双重编码（Mojibake）：原始 GBK 字节 → 正确解码为 UTF-8 → 又被当作 Latin-1 读入 → 再次编码为 UTF-8 = 最终乱码；
  3. 含大量 ASCII HTML 标签的正文在自动检测时会被误判为有效 UTF-8，跳过了手动解码步骤。
- **修复方案**：
  1. **全局 CharsetReader 改为透传**：将 `message.CharsetReader` 设为始终返回原始输入流，阻止 `go-message` 自行解码 body；
  2. **自定义解码函数 `decodeTextContentWithCharset()`**：根据 MIME 头部声明的 charset 参数精确选择解码器（`simplifiedchinese.GBK.NewDecoder()`），一次性正确转换为目标 UTF-8 字符串；
  3. **头部字段解码**：使用带 `CharsetReader` 回调的 `mime.WordDecoder` 解码 Subject、From/To 显示名等 RFC 2047 编码头部；
  4. **Charset 值清理**：所有读取 charset 的位置均添加 `strings.Trim(charset, "\"' \t")`，处理 MIME 声明中可能包裹的引号。
- **涉及文件**：
  - `server/main.go` — 全局 `message.CharsetReader` 设置（透传模式）
  - `server/imap/fetcher.go` — IMAP 邮件正文/头部解码逻辑
  - `server/pop3/fetcher.go` — POP3 邮件正文/头部解码逻辑
  - `server/services/attachment_service.go` — 附件名 RFC 2047 解码
- **依赖新增**：`golang.org/x/text v0.21.0`（`simplifiedchinese.GBK` 解码器）

### 163/126 等网易邮箱无法发送邮件

- **状态**：✅ 已修复并于v1.1.0发布
- **记录时间**：2026-07-01
- **问题描述**：使用 163、126 等网易邮箱时，虽然可以正常收信（IMAP），但无法发送邮件（SMTP）。原因是用户在添加账号时通常只填写 IMAP 服务器地址，系统未能正确推断对应的 SMTP 服务器地址和端口，导致 SMTP 连接失败。
- **修复方案**：
  1. 新增常见邮箱服务商的 SMTP 服务器映射表（`smtpHostMap`），支持 163、126、QQ、新浪、阿里云、Gmail、Yahoo、Outlook 等主流邮箱；
  2. 新增 SMTP 端口映射表（`smtpPortMap`），针对不同服务商使用正确的端口（如网易系使用 465 SSL/TLS，Gmail/Outlook 使用 587 STARTTLS）；
  3. 实现 `inferSMTPHost()` 函数，根据 IMAP 地址自动推断 SMTP 服务器地址（优先匹配已知服务商，否则将 `imap.` 替换为 `smtp.`）；
  4. 实现 `DefaultSmtpPort()` 函数，根据 SMTP 服务器地址返回正确的默认端口。
- **涉及文件**：`server/models/mail_account.go`

### IMAP IDLE 不兼容部分邮件服务器

- **状态**：✅ 已修复并于v1.1.0发布
- **记录时间**：2026-07-01
- **问题描述**：部分邮件服务器不支持 IMAP IDLE 命令（RFC 2177），当 Worker 尝试使用 IDLE 实时监听时会报错并反复重试，导致日志大量错误信息，且每次重启都会重新尝试。
- **修复方案**：
  1. 新增 IDLE 支持服务器白名单（`idleVerifiedServers`），仅对 Gmail、Yahoo、Outlook、QQ 等已验证服务器启用 IDLE；
  2. 新增运行时学习机制（`idleLearnedUnsupported`），首次遇到不支持的 IDLE 错误（包含 "BAD"、"not support"、"not allowed" 关键字）时，自动将该服务器标记为不支持并加入全局黑名单；
  3. 后续同服务器的其他 Worker 可共享黑名单信息，避免重复尝试。
- **涉及文件**：`server/imap/worker.go`
- **备注**：未知服务器仍会首次尝试 IDLE，失败后自动降级为轮询模式（30秒间隔），符合渐进式兼容策略。

### SMTP 邮件头部 CRLF 注入漏洞 (CWE-93)

- **状态**：✅ 已修复并于v1.1.0发布
- **记录时间**：2026-06-26
- **安全等级**：中等（CVSS ≈ 5.3）
- **问题描述**：发送邮件时，`buildMessage` 函数直接将用户输入的收件人地址、主题等字段拼接到 RFC822 邮件头部中，未对 `\r`、`\n` 等控制字符进行过滤。攻击者可在收件人或主题字段中注入换行符，从而注入额外的 SMTP 头部或篡改邮件内容。
- **修复方案**：
  1. 新增 `sanitizeHeaderValue` 和 `sanitizeEmailAddr` 函数，在构建邮件头部时清洗所有用户输入，移除控制字符；
  2. 在 `Send` handler 入口处增加输入校验，检测并拒绝包含 `\r\n` 的字段值（纵深防御）。
- **涉及文件**：`server/smtp/client.go`, `server/handlers/mail_handler.go`
- **参考**：同类漏洞 (CVE form-data v4.0.5) — 本项目虽不依赖该库，但存在相同的攻击面

### 密码解密失败导致账号列表查询异常

- **状态**：✅ 已修复并于v1.1.0发布
- **记录时间**：2026-06-26
- **问题描述**：当某个邮箱账号的密码加密数据损坏或密钥不匹配时，`AfterFind` 钩子中的解密失败会阻断整个账号列表查询接口（500 错误），导致用户无法查看任何账号。
- **修复方案**：
  1. 解密失败时仅记录警告日志并清空密码字段，不再返回错误阻断查询；
  2. 新增 `AccountListDTO` 专用列表查询模型，避免列表场景触发 `AfterFind` 解密逻辑；
  3. 新增账号健康检查接口 `/api/v1/accounts/health`，便于排查异常账号。
- **涉及文件**：`server/models/mail_account.go`, `server/services/account_service.go`, `server/handlers/account_handler.go`, `server/services/health_check_service.go`, `web/src/stores/accountStore.js`

### 163/126 网易邮箱登录失败 (Unsafe Login)

- **状态**：✅ 已修复并于v1.1.0发布
- **记录时间**：2026-06-25
- **问题描述**：使用 163、126 等网易邮箱时，IMAP 登录返回 "SELECT Unsafe Login" 错误，导致无法正常收信。原因是网易邮箱要求客户端在登录前必须发送 ID 命令声明身份（符合 RFC 2971 规范）。
- **修复方案**：在 IMAP 登录前主动发送 ID 命令，声明客户端信息（Name: MagicMail, Version: 1.0.0, Vendor: MagicCode）。若服务器不支持 ID 命令则仅记录日志，不阻塞登录流程。
- **涉及文件**：`server/imap/client.go`

### 邮箱管理页面中等宽度下信息与按钮重叠

- **状态**：✅ 已修复并于v1.1.0发布
- **记录时间**：2026-06-26
- **问题描述**：在 768px ~ 900px 宽度区间，邮箱管理页面的桌面端 Grid 布局会导致邮箱地址信息与右侧操作按钮（编辑、同步、删除）发生重叠，影响使用体验。
- **修复方案**：将 `AccountManage.vue` 的响应式断点从 `768px` 调整为 `900px`，使中等屏幕更早切换到卡片布局。
- **涉及文件**：`web/src/views/AccountManage.vue`
