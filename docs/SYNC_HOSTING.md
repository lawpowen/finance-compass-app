# 账号登录与跨设备同步

同步版和原有[静态自托管版](SELF_HOSTING.md)使用同一套录入、报表和导入导出界面。用户可从登录页注册，每个账号有独立账本。同一账号可以在多个浏览器登录。手机、平板和桌面浏览器可使用公网 HTTPS 链接，移动端也可以把网页添加到主屏幕。当前 Android、Windows 等原生应用继续使用本地 SQLite。

## 使用和迁移

1. 在 0.10.1 的“导入与导出”中导出完整 JSON，并留一份独立备份。如果多个设备各自已有数据，先确定哪一份账本负责首次迁移。
2. 打开同步站点，用用户名和密码注册或登录。依次打开“设置 → 导入与导出 → 导入数据文件”，选择完整 JSON。核对预览里的账户和交易数量，确认替换当前账号的同步账本。原设备保留原账本。
3. 在另一台设备登录同一账号。打开时读取服务端最新版，页面在前台且没有打开编辑器时约每 15 秒先检查修订号，有变化才下载账本。在同步模式中，保存先写本机并进入待同步队列，随后由应用后台上传。网络短暂断开时仍可在已打开的账本继续录入。重新联网或下次同账号打开后继续上传；也可在设置主动触发。
4. 可以退出同步账本并使用本地模式。本地模式继续使用当前设备、浏览器和网址的本地 SQLite，两套账本通过显式 JSON 导入导出迁移。

旧备份可能把上级分类存成名称。导入预览会列出可唯一对应的同类型分类，以及无法确认的上级关系。确认修复后，前者恢复正确关联，后者保留为顶层分类。两种情况都保留该分类及其交易和预算。取消可返回原账本。

退出同步账号与手动刷新都在“设置”。黑白极简为默认外观，各设备可在「外观与主题」预览并应用多巴胺或苹果液态玻璃。进入网页时会优先请求主脚本，首次只挂载总览，其余标签首次打开时才加载，并保留已打开标签的状态。

PWA 检测并下载新版后弹出“有新版本”。点“更新”才重新载入，点“稍后”可继续当前操作，也可从“设置 → 更新应用”重新打开提示。正在编辑、储存或恢复同步时会延后提示。首次安装不会弹出提示。仍停在不含更新提示的旧版页面时，先关闭再重新打开一次。

切换标签会保留各自打开的详情或编辑页。远端更新和 PWA 重新载入会等待这些页面关闭；等待期间已保存的改动仍从持久队列自动上传。

## 系统提醒

登录后，在“设置 → 通知与提醒”选择“启用系统通知”，允许浏览器通知，再发送一条测试通知。每台设备单独启用。iPhone 和 iPad 要先添加到主屏幕，再从该图标打开并启用。可以停用当前设备的推送，退出登录也会尝试撤销该设备的订阅。

- 信用卡结算提醒按配置的结算日发出。信用卡还款使用已设置的结算日和还款日。账期未结算且到期不足三天时，提前通知会标明该日期为预计。
- 信用卡和贷款默认提前 3 天及到期当天提醒。贷款采用录入的每月还款日，短月取当月最后一天。已可靠匹配并覆盖全额的实际还款会抑制该期推送。计划交易和未来交易不视为已还款。
- Homelab 按订阅时区从每日 09:00 开始派发，同一天内可补发。通知会显示账户名称和提示，不附带余额或流水金额。

## 数据与并发

同步服务将完整 JSON v3 与单调递增的服务端修订号写入独立 SQLite 卷。客户端通过独立的内存 Drift 工作副本执行既有校验和余额更新。浏览器在操作完成前把待上传内容写入按账号隔离的 IndexedDB 队列。后台顺序提交，网络回复未确定时用同一操作 ID 重试；上传期间的后续改动合并为下一份待上传快照。同一基础版本只允许一次新写入，服务器拒绝过期请求。网络错误可后台重试，真实版本冲突需用户处理，仍可下载本机未同步的账本。

后台上传由打开的 PWA 进程执行。应用关闭时，待上传内容留在设备，登录同一账号后恢复。主动清除网站数据会删除本机等待上传的队列。

原生和默认 Web 构建依然使用数据库 schema 9 和 JSON v3。同步 API、会话和修订号存放在服务端 SQLite 中，不进入可携 JSON。同步 API 响应禁止缓存，Service Worker 只为应用资源提供离线支持并跳过 API。

升级前的同步账本、会话和重试记录会迁入原账号，保留原有账本修订号。不同账号分别维护修订号和重试记录。标签页继续绑定打开账本时的账号，即使另一标签页切换了会话也不能把旧账本写入新账号。升级后的服务端数据库只由支持多账号的版本读取。

## 同步接口

以下请求同源，统一前缀 `/api/sync/v1`。请求和响应 JSON 编码为 UTF-8。

| 请求 | 成功响应 |
| --- | --- |
| `GET /health` | 健康状态，匿名可用 |
| `POST /register` | `{username,password}`，创建独立账本，成功 204 并设置 HttpOnly 会话 Cookie |
| `POST /login` | `{username,password}`，成功 204 并设置 HttpOnly 会话 Cookie |
| `POST /logout` | 204 并清除会话 |
| `GET /ledger` | `{accountId,username,revision,snapshot}`，初始化前 snapshot 为 null |
| `GET /ledger/revision` | `{accountId,username,revision}`，后台检查用 |
| `PUT /ledger` | 提交 `{baseRevision,operationId,snapshot}`，并以 `X-Finance-Account` 绑定当前账号，返回 `{revision}` |
| `GET /push/config` | 返回当前部署的 VAPID 公钥 |
| `PUT /push/subscription` | 保存当前账号的浏览器订阅与 IANA 时区 |
| `DELETE /push/subscription` | 移除当前账号的设备订阅 |
| `POST /push/test` | 发送一条测试通知至当前账号持有的设备订阅 |

写请求检查 Origin，未登录返回 401，过期版本返回 409，HTTP 请求体上限 16 MiB。首版客户端使用同源浏览器会话，原生客户端连接需另行实现。

## 部署和运维

构建需要 Docker Engine、Compose、对 Flutter SDK 与镜像仓库的出站访问。将 `FINANCE_SYNC_ORIGIN` 设置为公网 HTTPS 来源（无路径）。以下命令从项目根目录执行，可在 Docker 前加 `sudo`。Caddy 默认只绑定宿主 `127.0.0.1:18765`，反向代理负责 TLS 和把同一域名的所有路径转发到该端口。

```sh
export FINANCE_SYNC_ORIGIN=https://finance.example.com
docker compose -f deploy/sync/compose.yml up -d --build
docker compose -f deploy/sync/compose.yml ps
```

Homelab 的公网入口使用独立的 Tailscale Funnel 节点，首次加入 Tailnet 需要管理员批准。节点只运行在服务器。保持其状态卷持久化，使用专用节点的 HTTPS 443 和本机反向代理，避免和其他应用共享浏览器 origin。Funnel 采用 TLS 终结加 PROXY v2，Caddy 从连接元数据读取客户端 IP 并覆盖上游限流头。这个监听端口必须只绑定宿主回环。

Homelab 的 [AI 设施总览](https://homelab.tail43a542.ts.net/#services)中也有 Finance Compass 入口，直接打开公网账本地址。

Homelab 代码目录在 `~/finance-compass-deploy/current`，部署参数在 `~/finance-compass-deploy/runtime.env`。从代码目录执行下方 Compose 命令时，使用 `sudo -n docker compose --env-file "$HOME/finance-compass-deploy/runtime.env" ...`。

生产更新从 GitHub 的指定 `main` 提交签出到新的发布目录。先验证现有同步数据库的在线备份，再使用同一 Compose 项目和数据卷构建上线。健康检查与静态版本确认后，将 `current` 指向新目录。

日常注册直接在网页完成。管理员可以在 Homelab 的交互式 Bash 提示中创建或重置指定账号密码。重置会撤销该账号的旧会话。密码通过标准输入和隐藏输入取得，勿将密码放进命令参数、配置文件或 Git。

Windows 端可以从项目根目录用 PowerShell 7 执行 `./deploy/sync/Set-HomelabPassword.ps1`，它使用现有 `homelab` SSH 别名并隐藏两次输入。默认账号为 `lawpowen`。

```bash
read -r -s -p 'Finance Compass password: ' finance_password
printf '\n'
printf '%s' "$finance_password" | docker compose -f deploy/sync/compose.yml run --rm -T --no-deps sync node server/provision.mjs lawpowen
unset finance_password
```

在线一致性备份示例。将备份定期复制到独立的受控储存位置，备份文件包含账本和认证状态。

```sh
docker compose -f deploy/sync/compose.yml exec -T sync node server/backup.mjs "/data/backups/ledger-$(date -u +%Y%m%dT%H%M%SZ).sqlite3"
```

升级前先备份。回滚应用时先核对服务端数据库格式。已升级到多账号数据库后，继续使用支持该格式的镜像。如果必须恢复升级前的单账号备份，先暂停同步进程，保存当前数据库和 WAL 恢复点，并单独保留升级后新增的账本，再由管理员恢复备份并核验账号和账本。不要使用 `docker compose down -v` 进行升级或回滚。

服务首次启动时将 VAPID 密钥存入同步 SQLite，备份会一并保存。主机需允许向受支持的浏览器推送服务发起 HTTPS，发布后无需单独注册定时任务。保留同一卷可继续使用现有设备订阅。
