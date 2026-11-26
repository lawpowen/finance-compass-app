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

总览分别读取还款、结算和到期当天开关。还款提醒列出待还账单。结算提醒在各卡结算日出现，短月取月末，即使该卡已还清也能查看提醒。资金需求预测独立于通知偏好。

设备保存服务器已确认的 IANA 时区。重新打开账本、回到前台、恢复联网或查看通知设置时，会把变化的时区更新到原账号的现有订阅。离线失败后保留上次确认值，供下次重试。退出时已显示的通知、浏览器订阅及服务端登记分别清理；推送权限、网络或浏览器清理失败时，登录与退出仍由账本会话决定。

每条推送携带收件账号与嵌套的通知内容。Service Worker 展示之前，通过同源会话和当前设备端点核对收件人。账号切换、会话到期、订阅被撤销或离线无法确认时，Worker 放弃本次展示。部署时一并更新服务端与 PWA，向仍在使用旧 Worker 的设备发送新格式时旧版仅能显示通用提示；新版 Worker 忽略旧格式中缺少收件人的消息。浏览器或操作系统已留存的历史通知取决于平台清理能力。

## 投资快照升级

阶段 2 沿用完整 JSON v3、SQLite v9 和服务端修订号。先等待旧版待传操作完成并保留升级前备份，再统一更新同一账本的各写入设备。旧客户端能识别数据结构，但写入投资流水时仍使用旧算法。兼容数据的判断依据和历史核对方法见[数据设计](DATA_DESIGN.md#旧账本兼容)。

## 贷款还款身份与版本兼容

阶段 3 完整备份仍为 JSON v3。新写端在相应的交易、模板或规则行上保存期号和跨币种合同实付额。同步服务校验目标贷款、两端币种、金额方向及本金上限。旧客户端重新导出时可能丢弃这些可选字段；升级同一账本的所有写端后再进行编辑。原始账本备份可用于核对缺少历史凭据的旧还款。字段及核销规则见[数据设计](DATA_DESIGN.md#贷款计划派生与还款落账)。

## 数据与并发

1. `FinanceSyncGate` 登录后读取账号、服务端修订号和完整账本 JSON，为本标签页创建独立的内存 Drift 工作副本。有同账号待上传记录时，优先恢复队列中的最新快照。
2. Repository 的写操作走 `LedgerSyncSession.mutate`。交易和账户余额先在工作副本事务中更新。浏览器把整份 JSON v3 快照、`baseRevision` 和 `operationId` 保存到按账号隔离的 IndexedDB 队列，随后发布本机变更供界面读取。队列写入失败会中止本次保存。若队列已落盘而内存事务失败，界面要求重新加载并从队列恢复。
3. 后台按队首顺序上传。在等待队首确认期间，后续保存合并成一份最新快照。服务器确认队首后，下一份快照以确认返回的修订号作为基准。暂时性失败采用退避重试并复用原操作 ID。
4. 服务端在一笔 SQLite 事务内校验账号、当前修订号及操作指纹，保存完整快照并写入幂等记录。相同操作 ID 和相同内容的重试返回原确认版本。过期版本或同 ID 不同内容返回 409。服务端校验格式与引用完整性，按收到的快照保存 `current_balance`。余额计算由客户端完成。
5. 另一台设备在前台且没有待上传、恢复流程、打开的详情或编辑页面时，约每 15 秒查询修订号。发现较新版本才下载并应用整份快照。恢复前台或联网会触发本轮检查和上传重试。应用远端账本前再次检查本机状态，以免覆盖请求发出后产生的编辑。

同一浏览器的标签页通过 IndexedDB 比较后替换队列，避免覆盖另一个标签页已保存的待上传数据。发生此类冲突时重新加载工作副本。跨设备修订冲突会暂停写入并保留本机副本。可先点「下载本次账本」保存待同步 JSON，再用「放弃并刷新」并确认采用服务器账本。整份快照是冲突处理单位，需要人工核对两份账本。认证失效时保留待上传快照并要求重新验证原账号。检测到其他标签页切换账号时，在恢复原身份之前隐藏草稿下载。

后台上传由打开的 PWA 进程执行。应用关闭时，待上传内容留在设备，登录同一账号后恢复。主动清除网站数据会删除本机等待上传的队列。

原生和默认 Web 构建依然使用数据库 schema 9 和 JSON v3。同步 API、会话和修订号存放在服务端 SQLite 中，不进入可携 JSON。同步 API 响应禁止缓存，Service Worker 只为应用资源提供离线支持并跳过 API。

升级前的同步账本、会话和重试记录会迁入原账号，保留原有账本修订号。不同账号分别维护修订号和重试记录。标签页继续绑定打开账本时的账号，即使另一标签页切换了会话也不能把旧账本写入新账号。升级后的服务端数据库只由支持多账号的版本读取。

## 同步接口

以下请求同源，统一前缀 `/api/sync/v1`。请求和响应 JSON 编码为 UTF-8。

| 请求 | 成功响应 |
| --- | --- |
| `GET /health` | 健康状态，匿名可用 |
| `GET /ai/status` | 绑定会话及账号。关闭时返回 `{"enabled":false}`，启用时另返回 `streaming:true` 与适配器名称 |
| `POST /ai/chat` | 同源、绑定账号。用 JSON 提交问题，接收 UTF-8 SSE。事件与限制见[接口说明](INTERFACES.md#内置-ai-理财助手) |
| `POST /register` | `{username,password}`，创建独立账本，成功 204 并设置 HttpOnly 会话 Cookie |
| `POST /login` | `{username,password}`，成功 204 并设置 HttpOnly 会话 Cookie |
| `POST /logout` | 204 并清除会话 |
| `GET /ledger` | `{accountId,username,revision,snapshot}`，初始化前 snapshot 为 null |
| `GET /ledger/revision` | `{accountId,username,revision}`，后台检查用 |
| `PUT /ledger` | 提交 `{baseRevision,operationId,snapshot}`，并以 `X-Finance-Account` 绑定当前账号，返回 `{revision}` |
| `GET /push/config` | 返回当前部署的 VAPID 公钥 |
| `PUT /push/subscription` | 保存当前账号的浏览器订阅与 IANA 时区 |
| `PATCH /push/subscription` | 以 `{endpoint,timezone}` 更新当前账号已登记设备的时区，成功返回 204 |
| `DELETE /push/subscription` | 移除当前账号的设备订阅 |
| `POST /push/verify-delivery` | Worker 传入当前端点，以收件账号绑定请求头和会话核对登记，204 才展示通知 |
| `POST /push/test` | 发送一条测试通知至当前账号持有的设备订阅 |

写请求检查 Origin，未登录返回 401，账号绑定变化或修订冲突返回 409。账本上传的请求体上限为 16 MiB，注册和登录的请求体上限为 4 KiB。同步客户端使用同源浏览器会话，原生客户端目前使用本地模式。

### 超限草稿的处理

若另一标签页也在编辑本账号，遇到设备队列版本不一致时选择「重新载入本机草稿」。本页先读取当前账号在浏览器中持久保存的最新版本，可离线继续精简。若另一页已完成上传并清空队列，则重新读取服务器账本。设备队列重新载入前暂不提供重试或放弃操作；真正的服务端修订冲突仍需核对草稿与服务器版本。

保存前按实际 PUT 的 UTF-8 JSON 字节数检查完整请求体，包括 `baseRevision`、`operationId` 和 `snapshot`。16 MiB 边界本身可上传。首次超限会回滚这次工作库变更并保留原待传队列。页面暂存本次候选快照，可下载、取消，或点击「保留并编辑本机草稿」把它持久保存到当前账号的浏览器存储；在作出选择前关闭标签页可能丢失这次尚未保存的更改。

旧版本遗留的超限队列或代理返回 HTTP 413 的队列，会在可编辑账本上方显示草稿提示。可以先下载备份，再分多次删减记录或导入精简备份。每一步在当前浏览器持久保存；达到可上传大小后，客户端按原修订号恢复同步。代理的实际限额低于 16 MiB 时，只有内容变小后才重新尝试被拒的请求。若服务端在清理期间产生了独立修订，仍保留本机草稿并进入现有冲突处理流程。

## 可选的内置 AI 理财助手

Web 29 同步前端与同版本同步服务配套使用。在部署目录的私有 `runtime.env` 中选择模型和连接方式。AI 默认关闭。

| 环境变量 | 配置 |
| --- | --- |
| `FINANCE_AI_PROVIDER` | `openai_compatible` 使用 HTTP 网关；Homelab 的 `codex_terra` 使用 Finance 专用 Unix socket |
| `FINANCE_AI_BASE_URL` | 网关 API 根地址。例如 `http://host.docker.internal:<端口>/v1`。也接受反代前缀或完整的 `/v1/chat/completions` 地址 |
| `FINANCE_AI_MODEL` | 网关登记的对话模型标识，须支持流式文本及函数调用 |
| `FINANCE_AI_GATE_MODEL` | 可选。支持 JSON 对象回复的门控模型，留空沿用对话模型 |
| `FINANCE_AI_API_KEY` | 可选，仅由同步服务发送 Bearer 凭据，值保存在部署机私有配置中 |
| `FINANCE_AI_TIMEOUT_MS` | 单次上游请求时限，默认 90000 毫秒。整条对话请求另有 120 秒总时限 |
| `FINANCE_AI_CODEX_DIR` | Codex 模式下只读挂载的宿主 socket 专用目录，如 `/var/lib/finance-compass-codex-lawpowen`。容器内使用 `/run/finance-codex/chat.sock` |

HTTP 网关须支持 `POST /v1/chat/completions`。门控使用 `stream:false` 和 `response_format:{"type":"json_object"}`，主回复使用 `stream:true`、`tools` 和 `delta.tool_calls`。

### Homelab 的 Codex/Terra

宿主机使用已登录的 Codex CLI 和其模型目录中实际提供的 `gpt-5.6-terra`。桥接服务通过本机 stdio 创建临时线程，只接受本版本 Finance 的固定提示与五种账本查询定义。账本查询在同步服务执行。容器仅挂载专用 socket 目录；Codex 登录材料由宿主 CLI 自行管理。模型请求消耗该登录账号的模型额度。

1. 用宿主登录用户运行 `codex --version` 与 `codex login status`。适配器核对 CLI 0.145.0、模型和权限；升级 CLI 后先用隔离账本复验。
2. 将 `~/finance-compass-deploy/codex-bridge/current` 指向候选发布中的 `deploy/sync`。把同目录的 `finance-compass-codex@.service` 安装到 `/etc/systemd/system/`，由系统管理器重新载入并启用 `finance-compass-codex@lawpowen.service`。实例以指定的普通登录用户运行。其私有挂载命名空间隔离个人开发指引，宿主文件保持原状。socket 父目录权限为 0700，socket 为 0600；同步容器和桥接进程的有效 UID 须一致。
3. 在部署配置设 `FINANCE_AI_MODEL=gpt-5.6-terra` 与 `FINANCE_AI_CODEX_DIR=/var/lib/finance-compass-codex-lawpowen`。使用 `-f deploy/sync/compose.yml -f deploy/sync/compose.codex.yml` 两个文件管理同步服务。覆盖文件选择私有传输。此模式无需填写 API Key 或 HTTP Base URL，门控使用同一 Terra 模型。
4. 在同一同步镜像中运行仓库的 `tool/smoke_codex_terra.mjs`，可将脚本只读挂载为 `/app/tool/smoke_codex_terra.mjs`。脚本自行启动内存账本并核对两笔合成交易、工具调用和实际分段时间；只需连接 Finance socket。切回旧版本时，恢复原镜像和原部署配置，继续使用原账本卷。

同步容器内的 `host.docker.internal` 映射到宿主网桥。仅监听宿主机 `127.0.0.1` 的网关需先提供容器可访问的受控入口。由已有内网代理限制来源和认证，浏览器仅访问账本站点。状态接口表示配置已启用，真实模型、路由权限与工具兼容性可在隔离测试账号上用合成账本核对。

启用前确认网关和模型的日志、留存政策符合账本使用者的预期。问题通过主题门控后，同步服务会向管理员配置的模型发送该账号的财务摘要，工具调用还会发送按需查询的流水。Finance Compass 服务端不持久化聊天。Caddy 为聊天单设无压缩、立即刷新的反代，并从连接信息覆盖客户端地址头。

## 部署和运维

Homelab 的 Web 29 发布提交为 `94581b1`。使用 Codex 的实例从当前发布目录运行以下命令查看状态；更新或重建时沿用相同的项目名、环境文件和两个 Compose 文件。

```sh
cd ~/finance-compass-deploy/current
sudo -n docker compose -p finance-compass --env-file "$HOME/finance-compass-deploy/runtime.env" \
  -f deploy/sync/compose.yml -f deploy/sync/compose.codex.yml ps
systemctl is-active finance-compass-codex@lawpowen.service
```

构建需要 Docker Engine、Compose、对 Flutter SDK 与镜像仓库的出站访问。将 `FINANCE_SYNC_ORIGIN` 设置为公网 HTTPS 来源（无路径）。以下命令从项目根目录执行，可在 Docker 前加 `sudo`。Caddy 默认只绑定宿主 `127.0.0.1:18765`，反向代理负责 TLS 和把同一域名的所有路径转发到该端口。

```sh
export FINANCE_SYNC_ORIGIN=https://finance.example.com
docker compose -f deploy/sync/compose.yml up -d --build
docker compose -f deploy/sync/compose.yml ps
```

Homelab 的公网入口使用独立的 Tailscale Funnel 节点，首次加入 Tailnet 需要管理员批准。节点只运行在服务器。保持其状态卷持久化，使用专用节点的 HTTPS 443 和本机反向代理，避免和其他应用共享浏览器 origin。Funnel 采用 TLS 终结加 PROXY v2，Caddy 从连接元数据读取客户端 IP 并覆盖上游限流头。这个监听端口必须只绑定宿主回环。

Homelab 的 [AI 设施总览](https://homelab.tail43a542.ts.net/#services)中也有 Finance Compass 入口，直接打开公网账本地址。

Homelab 代码目录在 `~/finance-compass-deploy/current`，部署参数在 `~/finance-compass-deploy/runtime.env`。从代码目录执行下方 Compose 命令时，使用 `sudo -n docker compose --env-file "$HOME/finance-compass-deploy/runtime.env" ...`。

Web 26 启用来源信用卡入账日时，须一并更新同步后端与前端，以统一快照校验和提醒计算。先确认其他设备没有待上传的旧快照并保存 v3 备份。开始录入入账日后，各写入客户端都应使用支持该字段的版本；旧客户端重新上传整份快照时可能丢失它未识别的交易字段。

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
