# 测试与质量

## 贷款月供从预计转为实际

`test/loan_plan_conversion_test.dart` 从两期贷款的合同生成预计流水，经记账表单将第一期改为今天已还，再进入贷款详情。测试核对原交易 ID 只出现在第一期，付款 510 元中本金为 500 元、利息为 10 元；第二期仍为预计，账户没有重复扣款。保留未来日期、取消转换及旧利息分录另有用例。

`test/loan_detail_screen_test.dart` 与 `test/loan_settlement_records_test.dart` 检查部分还款、冲正、跨币种拆分及历史日期过滤。明细的原币支出可与银行流水核对，合同币本息可与本期核销核对。

## Web 29 内置理财助手

GPT-6.1-Terra 验收使用 Finance 专用 Codex CLI 0.172.0 和隔离的内存测试账本。经真实 HTTP 鉴权、主题门控和 `search_transactions` 后，模型答对 2 笔、MYR 49.73；一次实测共 58 个文本增量，首段在 21.5 秒到达，整轮 23.0 秒。回归测试分别覆盖门控与回答的错误型号、运行中改派、部署配置漂移，以及当前查询与旧对话中金额不同的情形。Windows 全仓 Node 回归 121 项通过，另 1 项仅适用于 Linux 文件权限。

Homelab 真实模型验收使用独立的 Node 24 内存账本、实际 Finance HTTP 认证和宿主 Codex CLI 0.145.0。GPT-5.6-Terra 通过主题门控后调用 `search_transactions`，从最近 30 笔之外找出指定商户的两笔支出，回答 MYR 49.73。修订号为 1，26 个真实文本增量中首段在 10.4 秒到达，整轮用时 11.6 秒。回归入口 `tool/smoke_codex_terra.mjs` 可重复此测试，模型分段数及用时随调用变化。

2026-11-26 正式发布 `94581b1`。通过正式宿主服务与正式同步镜像中的内存测试账本再次确认两笔合计 MYR 49.73，返回 26 段，首段 10.0 秒、完成 11.0 秒。线上同步容器健康，Terra 服务已启用开机启动；公网首页、主程序、Worker 和 Flutter 启动文件与已验收的前端 SHA-256 一致。未登录访问 AI 状态和账本修订均返回 401。部署前在线备份和部署后的 SQLite 完整性、账户账本修订连续性校验通过。

Flutter 3.44.1 全仓 526 项通过，2 项条件跳过；真实 Chrome 的 Fetch/AbortSignal 传输测试另行通过。加入 Terra 适配器后的 Windows Node 全仓 117 项通过，1 项 Linux 文件权限用例条件跳过；该权限用例在 Homelab 隔离 Linux 容器中通过。静态分析 0 error、0 warning、61 项既有 info，默认命令因 info 返回 1，使用 `--no-fatal-infos` 返回 0。

同步前端包 `build/finance-compass-web29-sync.zip` 的 SHA-256 为 `2e896bf88f558e7ae28f890466995202b9ec8e36783ed6afd3ee50b1fb71f7a0`。已校验 144 个文件、38 项预缓存、104 份字体校验和、锁定的 SQLite WASM 与 ZIP CRC。内置助手需配套 Web 29 同步服务和代理配置。

真实 Chrome 157 经本地 Caddy 和同步服务登录合成账本，从总览点击「本月消费与预算」。测试网关延后第二段时，第一段已经显示；点击「停止生成」后上游收到取消。浏览器实际加载的主程序 SHA-256 为 `919f6973125c67e2e07b88a7ddc67a5518690c2790a44e0dbe264e8c1ab3d844`。独立代理测试中，第二个并发请求返回 429，第一条取消后再次请求返回 200。

- 用 `node --test server/*.test.mjs test/web_bootstrap.test.mjs` 运行服务端和 Web 启动回归。两个独立的合成账号覆盖认证、Origin、参数校验、分账号与分地址限流、门控期间会话失效、分段交付及断开后释放名额。模拟兼容网关覆盖多工具调用、跨块中文和上游中断。
- 财务用例覆盖新账号修订 0、跨卡还 PayLater、银行入账日、旧转账的到账金额、贷款本金与利息、未知汇率、父子分类预算及检索超过 30 笔时的全量总计。使用合成数据，不要求真实模型或个人账本参与自动测试。
- Flutter 全仓测试包含聊天页面、登录会话状态、流解码器及原生 HTTP 传输。另以 `flutter test --no-pub --platform chrome test/ai_chat_transport_browser.dart` 验证浏览器收到第一段字节时即可显示中文，取消读取会触发真实 AbortSignal。Windows Chrome 的同源 CanvasKit 测试资源准备方法与现有浏览器测试相同。
- 发布前使用与同步镜像一致的 Caddy 2.11.9 执行 `caddy validate --config deploy/sync/Caddyfile --adapter caddyfile`。通过实际代理验证首段文本早于最终事件到达。在同一账号中止一条尚未完成的流后，下一条请求应能开始。

## Web 28 交易搜索多选删除

2026-11-26 在 Homelab 发布 `510ccc1`。升级前的在线备份和升级后的账本完整性检查均通过。公网 Chrome 验证了 Web 27 确认升级至 Web 28；首页、主程序、启动脚本及 Worker 的 SHA-256 与候选镜像一致。另以发布后的前端文件连接本机隔离账本，在真实 Chrome 长按多选并删除两笔各 10 元的交易，余额由 960 恢复至 980，搜索页保留关键词并显示剩余结果。生产账本未参与删除试验。

固定 Flutter 3.44.1 全仓测试 497 项通过，2 项条件跳过（本地 AI 网关、手工截图）；Node 服务端和启动回归通过 63 项。静态分析为 0 error、0 warning、61 info。

- Web 27 回归可复现两处故障：长按搜索结果无法进入选择；从行菜单发起删除后，即使取消也已离开搜索。新用例从真实搜索入口操作，检查同一搜索路由、关键词和可滚动结果的偏移，覆盖长按多选、取消或确认删除、菜单与编辑器单笔删除、空结果及系统返回。
- 使用独立的内存 SQLite 账本核对删除记录和余额回算。同步刷新会剔除失效的选择；写操作排队期间发生账本切换时，即使两个账本存在同一交易 ID，也不能误删另一个账本的流水。

## Web 27 信用卡列表账期与配色

Homelab 已部署 `b18e357`。切换前在线 SQLite 备份通过校验，切换后核对了同一同步容器、原账本卷、SQLite 完整性、账本修订和同修订快照。公网首页、主程序、启动脚本及 Worker 的 SHA-256 与候选镜像一致，健康接口返回 200，匿名账本修订和推送配置请求返回 401。隔离 Chrome 模拟 Android 已安装模式，从 Web 26 确认更新后成功以 WebGL 绘制 Web 27 首帧。

使用项目 Flutter 3.44.1 执行全仓测试，493 项通过，2 项条件跳过（本机 AI 网关集成与手工截图）。指定的静态分析得到 0 error、0 warning、64 info，默认因 info 返回 1。

- `test/credit_card_outstanding_test.dart` 在固定的 2026-11-25 核对 Laz PayLater。其结算日为 9 日，还款日为 25 日。本期已还清，11-20 的 79.56 元和 12-09 的已确认分期 180.88 元都属于下期。行主金额为 MYR 260.44，徽章使用收入色，正数金额使用正文色；分组负债仍为月末的 MYR 79.56。
- 其他用例分别核对本期、今日和逾期应还的标签、应还额及支出色，并核对已还清且金额为零、远期承诺、资料不全、历史截止、额度使用和外币折合。美元卡的本期应还 USD 40.00 以 4 倍汇率显示约 MYR 160.00，另列下期已用 USD 17.00。

在真实 Chrome 的 390×844 视口中，通过本机同步服务载入同一套 Laz PayLater 账本并打开「账户 → 信用」。Web 26 的行主金额是「月末欠款 MYR 79.56」，Web 27 是「下期已使用 MYR 260.44」；两个版本的信用卡分组负债均为 MYR 79.56。同步版发布包 `build/finance-compass-web27-sync.zip` 已核验 144 个文件、38 个核心预缓存条目、104 份字体校验和及 ZIP CRC。SHA-256 为 `f683c1097755687ecf89de41cd37d91cb2398cd2c82a0ab0a266b1126562eb89`。

## Web 26 来源信用卡账单入账日

2026-11-25 Homelab 同时上线 `ed9208b` 的 Web 和同步后端。候选镜像在隔离账本中写入 MYR 241.94、发生日 11-25、来源入账日 11-26 的跨卡还款，重新登录后读回同一日期和修订号；试写早于发生日的日期返回 400，修订号保持不变。生产切换复核原数据卷、SQLite 完整性、账号、账本修订及同修订快照、VAPID 公钥。公网首页、主程序、启动脚本及 Worker 的 SHA-256 均与候选镜像一致，健康接口返回 200，匿名访问账本修订及推送配置返回 401。隔离 Chrome 模拟 Android standalone，从真实 Web 25 确认更新后激活 Web 26，原地址正常渲染 WebGL 首帧。

使用项目 Flutter 3.44.1 运行 `flutter test --no-pub`，491 项通过，2 项条件跳过（本机 AI 网关集成和手工截图）。`flutter analyze --no-pub lib/ test/` 得到 0 error、0 warning、64 info，默认因 info 返回 1。`node --test server/*.test.mjs test/web_bootstrap.test.mjs` 通过 63 项。

- 跨卡样例用 UOB Lazada（25 日结算，14 日还款）在 2026-11-25 偿还 Laz PayLater MYR 241.94，并将来源入账日设为 11-26。还款当天收款卡清零，来源卡额度已占用；该笔不在 11-25 的 UOB 结单，计入 12-25 结单，2027-01-14 产生一次现金需求。测试覆盖今日及更早的预测起点、已确认与预计转账、未来多期、尚未入账退款，以及旧账单后续还款的推断边界。
- 月度报表回归检查同一笔 11-30 消费、12-02 入账的 60 元在 11 月预算及分类支出中各出现一次。另一笔 11-30 卡转银行的 15 元当天计入银行余额和现金流，两笔来源卡金额合计 75 元归入 12 月结单。
- 测试在真实 v9 文件上校验增改删、关闭重开、ID 复用、跨来源编辑、非法批量回滚。手工导入与同步恢复均检查 v3 的行字段和旧版缺省，拒绝非信用卡来源、虚构日期及早于发生日的入账日。Node 测试经真实 HTTP 验证快照和修订号，并验证提醒仍按转入卡发生日和来源卡账期分别计算。
- Widget 测试操作两套记账表单及卡还卡弹窗，核对日期选择、顺延、清除、复制、模板和账单明细双日期。另验证月末批量生成保留日历日差，旧预计贷款分录仅在来源入账日相同时合并。

发布包 `build/finance-compass-web26-sync.zip` 使用 `--dart-define=FINANCE_SYNC_WEB=true` 构建，已通过渲染器 lint。144 个文件、38 个核心预缓存条目、104 份字体校验和、锁定的 SQLite WASM、同源 CanvasKit 与 ZIP CRC 均通过校验。SHA-256 为 `b7aeb9739eec3facdf9ba1b1baff59fff3d1f9951c36939b28bf0a5528024b93`。本地 Chrome 在生产 CSP 下加载发布构建，Web 26 首帧和离线 Worker 正常；真实本地 Node 服务接受并读回带入账日的 v3 修订 1，Flutter 完成认证账本恢复并开始轮询修订号。生产发布需将 Web 26 和同步后端一起更新。

## Web 26 信用卡与 PayLater 还款回归

使用项目 Flutter 3.44.1 运行全仓测试，461 项通过，2 项条件跳过（本机 AI 网关、手工截图）。`flutter analyze --no-pub lib/ test/` 得到 0 error、0 warning、64 info。`node --test server/*.test.mjs test/web_bootstrap.test.mjs` 通过 57 项。

- 还款来源测试验证现金优先，同币种活跃信用卡可支付 PayLater，自身、其他币种和停用卡被排除。选择后停用来源再确认会拒绝入账。贷款仍仅可由现金账户支付。Widget 用例通过日期选择器补录上月 15 日的 70 元还款，核对实际交易日期、录入时间和两端余额。
- 双卡测试用 100 元 PayLater 账单及 1,000 元现金，核对按时转移全部债务、逾期后只转移 80 元、预计转账不影响实际余额和付款银行随后支付 40 元等场景。逾期后由卡支付 80 元时，原卡剩余筹资额为 20 元，80 元随付款卡到期，两个账期合计仍为 100 元。另验证付款卡尚无完整账期时的估算到期日。
- 在列表及详情核对 1,000 元额度、300 元月末欠款、未来已确认分期 200 元，以及另有 500 元预计交易的样本。两页额度已用均为 50%，列表另标今日应还 241.94 元。历史及零额度有独立断言。时间线分别在结算日、到期日及普通日期验证圆点数、同日标签和高亮位置。

## 2026-11-25 Web 25 已安装 PWA 渲染性能与恢复

Homelab 生产验收使用提交 `95e4b9a`。切换前在线 SQLite 备份通过校验，仅替换 Web 容器，并核对了原同步容器、账本卷、账本修订及同修订快照。公网首页、启动脚本和 Worker 的 SHA-256 与候选镜像一致，健康接口返回 200，匿名访问账本修订和推送配置返回 401。隔离 Chrome 模拟 Android standalone，先以 Web 24 软件模式启动，等待用户确认后切换 Web 25。原 URL 上的 Flutter 首帧可见，CanvasKit 实际使用 Intel Iris Xe / ANGLE D3D11 的 WebGL 表面。

渲染器源码 lint 可在仓库根目录运行 `dart tool/lint_web_renderer.dart`。它检查 Flutter 展开模板之前的 `web/flutter_bootstrap.js`。规则 `web-renderer/platform-default` 拦截浏览器 UA、平台、触摸点、安装标记及 `display-mode` 媒体查询，`web-renderer/always-cpu` 拦截将 CanvasKit 软件选项直接设为 `true` 或引用同值常量。安装界面等其他脚本不在检查范围内。显式 CPU、会话回退和保存中延迟重载等行为由 `test/web_bootstrap.test.mjs` 验证。

PowerShell 与 shell 两个 Web 构建脚本在编译和清理输出目录前运行同一检查。静态及同步 Docker 源码构建沿用 shell 入口。直接调用 SDK 的 `flutter build web` 时先单独执行上述 lint。`flutter test --no-pub` 也会检查当前启动脚本和 lint 正反例。单独执行 `flutter analyze` 仅分析 Dart。

使用提交 `0247c65` 的原始启动脚本复验，两个构建入口均在生成输出前报告 `web-renderer/platform-default` 并返回 1。Web 25 启动脚本返回 0。

Windows 使用项目固定的 Flutter 3.44.1 及其随附 Dart SDK。Flutter 全仓测试 444 项通过，2 项条件跳过；Chrome 启动偏好测试 4 项通过。Node 启动与服务端测试通过 57 项，启用本机 Chrome 的原生画布回归通过 2 项。分析 `lib/ test/` 得到 0 error、0 warning、64 info；默认因 info 返回 1，使用 `--no-fatal-infos` 返回 0。同步发布包在本地生成，包含 144 个文件，校验了 38 个 Worker 核心预缓存条目、104 份字体校验和及整个 ZIP 的 CRC。

- 对同一 Android 用户代理和无参数入口运行 Web 24 启动脚本，普通标签页读到 `canvasKitForceCpuOnly=false`，独立 PWA 读到 `true`。Web 25 的启动测试同时核对引擎配置和 Flutter 读取的渲染标记。
- 同一 390×844 逻辑像素视口、相同总览样例与液态玻璃主题下，`test/performance_optimization_test.dart` 检查滚动内容与实际合成层。卡片背景滤镜从 5 个降至 0 个，包含悬浮底栏的 `BackdropFilterLayer` 从 6 层降至 1 层。959 和 960 像素边界分别验证窄屏与桌面卡片、环图效果，另验证 CPU 模式直接返回子组件。图层数衡量省去的背景采样次数，真机 FPS 需要设备实测。
- `node --test test/web_bootstrap.test.mjs server/*.test.mjs` 覆盖渲染默认值、60 秒内再次失活、10 分钟标记到期、显式覆盖、存储异常、短暂离开、前后台两种宽限期、占位绘制时的竞态和表单保护。设置 `CHROME_EXECUTABLE` 后运行 `node --test test/web_bootstrap_browser.test.mjs`，使用原生 WebGL 丢失事件核验 OffscreenCanvas、闭合 Shadow DOM、绘制恢复占位和不改地址的会话级降级。

本地回环站点先完整提供 Web 24，再切换至带生产 CSP 的 Web 25 同步构建。真实 Chrome 在 390×844 视口模拟 Android 安装模式，旧 Worker 等待确认，新 Worker 激活后出现登录首帧。安装模式和普通标签页均取得实际 CanvasKit WebGL 表面，驱动报告 Intel Iris Xe / ANGLE D3D11。健康页面离开再返回，页面时间原点与采样画面保持一致。

对编译产物的主画布注入 `WEBGL_lose_context`，第一次在原 URL 恢复为 GPU；再次失活时仍使用原 URL，进入带时间戳的临时 CPU 模式。恢复前的品牌占位覆盖 390×844 视口，恢复后的登录页可见。将测试会话标记置为已过期，保存保护仍可阻止切换，随后安全返回前台会恢复 GPU。`?gpu=1` 的显式覆盖也已实际验证。以上设备模式由桌面 Chrome 模拟。

## 2026-11-25 Web 24 PWA 冷启动与图标回前台

Homelab 生产部署运行 `0247c65`。升级前在线 SQLite 备份通过校验，仅替换 Web 容器。切换后复核了原同步容器、账本卷、SQLite 完整性和账本修订连续性。公网首页、启动脚本和 Worker 的 SHA-256 均与候选镜像一致，健康接口返回 200。独立 Chrome 配置先加载线上 Web 23，再确认更新，验证了 Web 24 缓存激活、启动占位消失及 Flutter 首帧显示。模拟 Android standalone 的公网入口无需查询参数即采用软件绘图。

- 升级前在 Chrome 157 用 `WEBGL_lose_context` 分别令离屏画布和闭合 Shadow DOM 画布失活。两种原生事件均为 `bubbles=false、composed=false`，旧的 window 监听器收件数为 0。Flutter 3.44.1 本地发布 SDK 的 CanvasKit 会在自然丢失时读取尚未初始化的 `late _handledContextLostEvent`；编译版本的主画布实测抛出 `LateInitializationError`。
- 启动测试覆盖本机主题存储拒绝访问、慢读超时、旧结果晚到、用户选择竞争、首次进入本机账本时沿用旧主题，以及首帧前后的 CSS 占位。Web 浏览器专测为 `flutter test --no-pub --platform chrome test/settings_boot_browser.dart`。该版本 Flutter 在 Windows 上运行 Chrome 测试时，若测试服务器对 `/canvaskit/chromium/` 返回 404，可在测试期间将项目 SDK 的两个 Chromium CanvasKit 文件放入测试静态目录 `test/canvaskit/chromium/`，测试后清理。
- `node --test test/web_bootstrap.test.mjs` 验证后台切换、BFCache、先可见后失活、静默失活探测、等待恢复、表单保护和连续失败降级。设置 `CHROME_EXECUTABLE` 指向本机 Chrome，运行 `node --test test/web_bootstrap_browser.test.mjs` 可用真实上下文检查引擎式替换后的重绘及输入保留。Flutter 的 `test/pwa_resume_repaint_test.dart` 验证同一帧返回事件合并为一次根画面重绘，已有详情路由保持打开。

Windows 工作树使用 Flutter 3.44.1 构建同步 Web release。全仓 Flutter 443 项通过，2 项条件跳过（本机 AI 网关集成、手工截图）。Chrome 主题读写与迁移 4 项通过。Node 服务端与启动策略 46 项通过，另行启用真实 Chrome 的画布回归 1 项通过。静态分析为 0 error、0 warning、64 info，默认因 info 返回 1。

发布构建在本机回环地址使用生产 CSP 验证。禁用主题读取并拒绝创建 Drift Worker 后，登录界面仍出现。对真实 CanvasKit 主画布连续触发失活，硬件重载与软件回退都恢复了可见登录画面；Web 23 Worker 等待确认，随后 Web 24 激活并再次渲染首帧。Chrome 模拟 Android standalone 时，CanvasKit 直接使用软件绘图，经 Chrome 冻结、解冻，再切换标签页使页面恢复可见后，页面时间原点保持不变，抽样画面与切换前相同。WebGL 试验采用 Chrome 的 SwiftShader 后端。本机 ADB 未连接 Android 真机。

## 2026-11-25 阶段 5 同步、迁移与状态刷新

Windows 工作树使用 Flutter 3.44.1。全仓 `flutter test --no-pub` 通过 437 项，0 项失败，2 项条件跳过（本地 AI 网关未运行、手工截图未启用）。全量 `node --test server/*.test.mjs` 通过 36 项，其中指定的同步、提醒与推送三份测试单独运行通过 31 项。`flutter analyze --no-pub lib/ test/` 得到 0 error、0 warning、64 info，默认因 info 返回 1；增加 `--no-fatal-infos` 后返回 0。推送账号隔离和时区变更使用模拟浏览器及本地服务端验证。真实设备系统通知投递尚待真机验证。

2026-11-25，Homelab 从 Web 22 更新到 Web 23，运行提交 `4906bdb`。发布前重跑 Flutter 全仓测试（437 通过，2 项条件跳过），以及 Node 服务端和 Web 启动测试（39 通过）。新镜像先在隔离内存账本中验证注册、写入修订 1、退出再登录读回和推送配置。切换后，以升级前的 SQLite 在线备份为基准，核对生产库完整性、账号、账本修订及同修订快照，并确认推送公钥连续。公网首页及健康接口返回 200，未登录读取账本修订和推送配置返回 401。全新 Chrome 配置实测 Flutter 首屏挂载、Web 23 Worker 激活及离线缓存建立。

- 设置同步测试通过真实 Provider 和待传队列保存网关地址，由测试服务端确认并保存快照，再用新客户端读取。二级页面覆盖返回后的汇率、排序和数量刷新，以及保留其他设备修改的币种字段。
- 账户测试覆盖停用、重新启用、历史交易编辑，以及选取还款来源期间账户被停用。390 像素宽度下验证含英文关键词的自定义账户和分类名，卡片显示真实名称。历史账期仍可选取同名卡片。
- 迁移测试从实际 SQLite 文件重开，验证两张预设表删空后重开及导入依然为空、旧分组在枚举读取前修复，以及损坏旧预设隔离。另以含已提交 WAL 的数据库对比升级恢复点 SQLite 与逐表 JSON。
- 同步测试使用包含多字节字符的完整请求，覆盖体积边界、拒绝后的显式保存、多次清理后重试、服务端 413，以及两个标签页离线载入同一账号已保存的草稿。Node 测试覆盖设备时区更新、旧账号解绑失败和 Worker 展示前的收件人校验。
- 预测测试核对最近已结束月份、无历史流水的存款基线和有符号转账。资产目标时间线与逐账户计算逐点对照，并记录财务写入读取账本和更新目标的次数。AI 摘要以本地午夜为界，覆盖今日实际、未来承诺及预计流水。兼容交易服务按相同边界汇总待发生支出，一笔 10 元预计支出与一笔 3 元退款在该月计为 7 元。

## 2026-11-25 阶段 4 分类、预算、汇率与周期规则

使用项目 Flutter 3.44.1 及 `--no-pub`。指定及关联的定向测试通过 134 项。全量 Flutter 测试通过 398 项，0 项失败；本地 AI 网关集成与手工截图按条件跳过 2 项。`flutter analyze --no-pub lib/ test/` 得到 0 error、0 warning、64 info，默认因 info 返回 1；同范围增加 `--no-fatal-infos` 后返回 0。Node 同步、提醒和推送三套测试通过 31 项。

- 交易页验证类型多选的候选并集、冲突项清理、选择父类命中归档孙级，以及打开或关闭筛选面板时远端删除类别与账户。手机端净退款日保留金额，窄屏日期汇总可换行。
- 分类数据库、手动导入和同步验证同类型父级、引用锁定及完整图防环。交易、模板、预算和规则的创建与历史编辑分别验证归档选择；从历史交易建立新配置时不改原交易。
- 预算覆盖自己与最近预算祖先分配、一个月内实际/预计/退款总额守恒、USD 本位币新建、只改阈值保留 10.4953 原始额度、继承删除影响提示，以及汇率不全时禁止虚假剩余与超支判断。
- 报表、AI 摘要及规划 CSV 验证同名子类、净退款、未分类实际及预计、缺价原币。320 像素工作区用 EUR 25 的账户验证补录汇率后重新估值。
- 周期规则验证 31 日在平年和闰年的跨月结果、原交易绑定、并发重试、事务失败回滚、同名重建、移月后仍按原定月份识别，以及备份往返。规则编辑器对修改过的草稿执行明确的保存与补生成操作。

## 2026-11-25 阶段 3 账期与结构化还款

Windows 工作树使用项目 Flutter 3.44.1。指定及关联测试组通过 91 项。最终全量 `flutter test --no-pub` 共 352 项通过、0 项失败、2 项条件跳过（本机 AI 网关集成和手工截图）。`flutter analyze --no-pub lib/ test/` 为 0 error、0 warning、70 info，默认因 info 返回 1；同范围增加 `--no-fatal-infos` 后返回 0。`node --test server/sync.test.mjs server/reminder-events.test.mjs server/push.test.mjs` 共 28 项通过、0 项失败。

- 贷款覆盖改备注后再次编辑、空白表单套模板、复制冲正、跨币种合同实付、跨付款账户替换计划、分次付款与零本金。旧账本、JSON 往返和无效导入回滚从账户、流水、模板和规则逐项核对。
- 平息本金 1,000 分 600 期，逐期本金以分求和等于 100,000 分。合同改名保留 3.875% 年利率，改合同起日后可继续选择合法追踪起日。
- 信用卡覆盖跨月逾期、冲正、溢付抵未来分期、贷方明细与零额度。预测检查本币和两种外币、同日还款、短月两期同日到期、晚到的现金与非现金结算，以及停用卡仍有待付账单。
- `test/fixtures/loan_settlement_v3.json` 由 Flutter 恢复测试和 Node 提醒测试共同读取。样本中的跨币种分次付款在 11 月 20 日付清第 1 期，之后的冲正重新打开 22 元本金；普通同名转账及预计流水均不算作实际清偿。

## 2026-11-25 阶段 2 余额与投资估值

在 Windows 工作树使用项目 Flutter 3.44.1。全量 `flutter test --no-pub` 共 323 项通过、0 项失败、2 项跳过（本机 AI 网关集成、手工截图）。`flutter analyze --no-pub lib/ test/` 得到 0 error、0 warning、70 info，默认因 info 返回 1；同范围只增加 `--no-fatal-infos` 后退出码为 0。`node --test server/reminder-events.test.mjs` 另有 9 项通过。

- 余额与现金测试覆盖按不同顺序录入同一组事件、补录、同秒并列快照、同账户转账、计划转实际、增改删流水与快照，以及删除唯一锚点。
- 页面回归核对无快照账户、快照行金额和百分比、日终录入、已有流水账户的编辑保护、历史目标和账单下钻。相同账户样本在总览、账户与报表均为资产 617、负债 190、净资产 427。
- 旧 v9 工作库与 JSON v3 备份覆盖迁移标记、重复恢复、歧义审计、无流水投资开账金额和显式零本金月供。换本位币测试用混合持币、恰好达标的目标验证进度和首次达成日期。

## 2026-09-25 资产目标日期与报表手机布局复验

- Claude CLI Opus 5.5 High 执行 `flutter test test/asset_goals_page_test.dart test/asset_goal_reached_date_test.dart`：13 项通过。覆盖真实跨越日、快照升值、期初余额日期未知、未来实际和预计交易排除，以及改写或删除账本后重算持久化日期。
- `flutter test test/reports_v2_screen_test.dart --reporter compact`：8 项通过；其中 390×844 回归逐段检查六个非空区块、滚动可见性、金额不换行和读屏标签。另导出 `artifacts/qa/reports-v2-390.png` 长图并人工检查，无明显横向溢出或截断。
- Claude CLI 执行全量 `flutter test --reporter compact`：156 项通过、2 项按设计跳过，退出码 0。`dart format --output=none --set-exit-if-changed lib test` 检查 140 文件、0 改动，退出码 0；`flutter analyze --no-fatal-infos --no-fatal-warnings` 为 0 error、2 项既有 warning、65 info，退出码 0。
- 自动化布局与截图不能替代真机触控、系统读屏或不同字号验收；本分支仍未打包发布。

## 2026-09-24 主题、报表与交易多选开发分支验证

- `dart format --output=none --set-exit-if-changed lib test`：139 个文件，0 个需改动，退出码 0。
- `flutter test test/appearance_carousel_test.dart`：2 项通过；`flutter test test/transactions_v2_navigation_test.dart`：4 项通过；`flutter test test/reports_v2_screen_test.dart test/interaction_wiring_test.dart`：16 项通过。定向测试由 Claude CLI 执行。
- 移除旧页面后，`flutter test --reporter compact` 全量通过：144 项通过、2 项按设计跳过，退出码 0。Claude CLI 在完整测试过程中提前结束后台任务，且续跑的 SDK 命令被宿主自动审批拦截；因此最终完整测试及全仓分析由当前工作区直接运行。
- `flutter analyze --no-fatal-infos --no-fatal-warnings`：退出码 0，0 error、2 warning、65 info。两项 warning 是既有未使用 `_referenceTransactions` 与 AI 集成测试局部变量；新增主题测试仍有两项 `containsSemantics` 弃用 info，不影响测试。
- 本次自动化验证覆盖 390 逻辑像素宽度的交易多选与主题点击，以及报表的期间联动和现金流口径；报表长页面触控与读屏仍需目标设备人工复核。

## 自托管发布包容器验收

- 必须在 Linux Docker 环境从公开发布 ZIP 开始测试，不得只验证源码目录或 Windows 本机解压结果。
- 使用 Linux 原生解压工具确认所有 ZIP 条目采用 `/` 分隔并能还原 `FinanceCompass-SelfHost/webroot`。
- 在 `read_only`、`no-new-privileges`、`cap_drop: ALL` 和 loopback 端口绑定保持启用时构建并启动 Compose；确认 `/data/caddy` 与 `/config/caddy` 仅使用临时内存盘且日志没有只读文件系统错误。
- 验证首页、Service Worker、`sqlite3.wasm`、`drift_worker.js`、WASM MIME、CSP 与缓存响应头，并检查容器无额外 capability、根文件系统不可写。
- 测试必须使用独立 Compose project name，完成后停止并删除临时容器、网络和测试目录，不影响 homelab 既有服务。

自托管 Web/PWA 发布门禁必须完成 `tool/build_web.ps1` 或 `tool/build_web.sh` 并以 `Web build complete` 结束。脚本自动检查：必需文件（含 `flutter_bootstrap.js`、`main.dart.js`、`canvaskit/chromium/`）、`service-worker.js` 的 `CORE` 每一项都存在、`sqlite3.wasm` 锁定哈希、`drift_worker.js` 与刚编译版本一致、`web/fonts/SHA256SUMS` 哈希及 `main.dart.js` 中 Roboto/Noto Sans SC 回退 URL 全部收录、bootstrap 含 `"useLocalCanvasKit":true` 与 `fontFallbackBaseUrl: 'fonts/'` 且不含 Service Worker 设置、无 `*.symbols`/`*.map`/`*.deps`/`.last_build_id`/Worker 源码；任一失败会删除 `build/web`。`test/web_delivery_contract_test.dart` 在源码层固定这些契约。此外必须在真实浏览器、同 Caddy CSP 下确认界面文字渲染、Service Worker 控制页面、重载后注册仍是 `service-worker.js`、离线重载仍能显示。静态容器应验证 `sqlite3.wasm` 为 `application/wasm`，入口/Worker 禁止长期缓存，Compose 默认只绑定 loopback，且 runtime ZIP 内的 Dockerfile、Compose、`webroot`、Windows PowerShell、Ubuntu/macOS shell 启动器路径相互匹配。

Web 回归至少覆盖：浏览器 FilePicker bytes 导入预览/替换路径、JSON 导出下载、在 HTTPS Safari 添加到主屏幕和 Android Chrome PWA 安装（实机）、首次完整加载后离线重开、不同 profile 之间不自动同步、清除站点数据后仅能依赖 JSON 恢复。Safari/Android 的安装入口为平台行为，自动化构建不能替代真机验收。

## 2026-08-04 v0.9.0 自托管 Web / PWA 验证

- 全量测试：112 项通过，2 项因外部 AI 网关/人工视觉采集条件未满足而按设计跳过。
- 静态分析：无编译错误；保留 105 项既有 info/warning。
- Web Release：Flutter、Drift Worker、完全本地 CanvasKit、`sqlite3.wasm` 和自定义 Service Worker 构建成功；输出不含 `gstatic.com`、Worker 源码、source map 或 `.deps`。
- Chrome 390×844 独立会话：界面实际渲染，Service Worker 激活并控制页面，无控制台错误或资源失败。最初误用不匹配的 sqlite3 WASM 曾复现 `xFileControl` LinkError 白屏；换为锁定的 sqlite3 2.9.4 官方资产后回归通过。
- HTTP：`/`、manifest、Service Worker、主程序、WASM 和 Drift Worker 均返回 200；WASM 为 `application/wasm`。
- 三平台自托管包：Ubuntu、Windows、macOS ZIP 均为 15,075,006 bytes、55 条目；Compose 配置通过，WASM 大小/哈希和 Worker sidecar 排除通过。
- 原生包：Android `0.9.0` / versionCode `42` 的 v2 签名、包名、三 ABI 通过；Windows `0.9.0+42` 安装版和 22 条目便携包通过。
- 环境限制：本机 Docker Desktop 卡在 `starting`，未完成实际容器启动；Compose 与回环 HTTP 已验证。iOS Safari/Android Chrome 的 HTTPS 安装、离线重开和系统存储回收仍需目标设备人工验收。完整证据见 [v0.9.0 公开发布 QA](public-release-qa-v0.9.0-2026-08-04.md)。

公开发布门禁除全量 Widget/领域测试和静态分析外，还必须验证 Android 发布签名与包身份、Windows EXE 元数据与启动、安装器/便携包完整性、支持二维码资产存在、三项二进制 SHA-256，以及 GitHub Release 文件名和大小。关于与支持页需在 390×844 视口验证版本、下载入口、自愿支持文案、无支付 SDK 声明和二维码语义标签。

## 自动化层级

- 领域单元测试：币种、现金流、模板、周期规则、信用卡账单和三种贷款摊销算法。
- 数据库迁移测试：构造 v6 SQLite，逐级升级到 v9，验证余额、空信用卡/贷款/追踪日期字段、模板 ID、本地资料 ID，并确认旧信用卡单笔结算日期归一为发生日期而现金交易不变。
- 数据可携测试：导出包含真实账户、分类、交易、模板及周期规则的 JSON v3，预览数量后导入到空数据库，并验证模板排序与规则启停状态不丢失；旧 v1/v2 信用卡 JSON 导入后以 `record_date` 作为账期发生日期，v3 则保留已编辑的 `transaction_date`。
- Widget 测试：表单、报表比较卡和主要启动界面。
- 外观回归（`theme_application_test.dart`）验证旧设备偏好归一为黑白极简，设置中移除主题切换，账本内旧字段保持原值。
- 交互接线门禁：扫描 `lib/src/features/**`，拒绝 `_noop` 及空的点击、按钮、切换和选择回调；Widget 回归覆盖周期规则编辑/补生成、报表区间、预算生效月份和货币格式持久化。
- 方向控件门禁：方向箭头、展开/折叠和下拉图标附近必须存在真实 `onTap`、`onPressed`、选择器、重排或语义按钮；账户统计截止 Widget 回归验证连续月份选择、月末金额变化、历史只读提示和返回本月，类别管理回归验证整行折叠与展开。
- 交易与账期回归：验证跨月/月末账期边界、旧账期不混入、信用卡对信用卡转账只进入来源卡账单、未来月份导航、未来预计交易可见、交易编辑保留原 ID/录入时间、已还清账单不误报逾期，以及总览预测范围切换。
- 交易计算口径回归：默认“已发生”必须同时从顶部汇总和列表排除 `planned`；选择“包含预计”后，实际与预计记录同时可见。“实际消费”排除转账；本月及未来月份的“实际现金”显示全月需准备现金，历史月份显示实际现金支出；“信用/贷款”使用当前信用负债并只叠加当月预计信用净变化。进入未来月份时使用相同合并范围，不得隐藏未来 `actual`。
- 交易多选筛选与未来月供回归（`transactions_v2_navigation_test.dart`）：账户、类型、类别各可选择多个值；组内 OR、组间 AND，转账目标账户可命中。取消保留原结果，应用后列表、实际消费与信用/贷款解释同步更新；“全部”清空可见条件，高级筛选按钮打开同一面板。全月“需准备现金”不随明细筛选缩小。未来月份同时包含实际和预计时，结构化贷款转账按完整月供 `amount` 进入现金流出，不按本金或利息差额计算。
- 月度资金需求回归：已知普通现金流出与到期信用卡/贷款合并为单一总额；已有实际或预计还款必须同时进入现金流出和覆盖额，使总额保持不变而不重复计算。覆盖结构化月供与没有系统期号文案的普通贷款转账。Widget 回归验证未来月份的中间口径卡显示正确总额、独立大卡不存在，选中后解释区显示已知流出/尚未安排及紧凑到期说明，390×844 不得溢出。
- 报表单页回归（`reports_v2_screen_test.dart`）：今年至今、最近 12 个月和全部时间切换同步更新净资产变化、实际现金流及支出分类；信用消费在刷卡时不计现金流出，现金还卡和还贷款按整笔付款计入，`planned` 排除；分类排行按交易发生口径排序并显示精确金额。验证无账户、无现金流、无分类和无成本时的空状态、零变化无正号，以及旧详细报表入口不再可达。390×844 满内容滚动测试另检查六个区块可见、金额不换行和读屏标签。未来现金投影与历史月度汇总继续复用实际现金规则。
- 预算生效链回归：4 月 MYR 200 规则在 4–7 月保持有效，8 月新增 MYR 400 规则使用新 ID 并在 8 月及以后生效；旧规则不得被编辑器覆盖。
- 资产目标回归：从账户页可进入目标管理；空状态可新增，保存后 provider 与页面即时出现真实目标，编辑/删除入口不是装饰控件；现金 MYR 1,000、投资 MYR 500、信用负债 MYR 800 的样本目标进度必须使用总资产 MYR 1,500，而不是净资产 MYR 700。`asset_goals_page_test.dart` 与 `asset_goal_reached_date_test.dart` 另外覆盖：缺省、月末和远期截止日都钳制到今天，明日实际收入与计划收入不计入当前资产、趋势末点和达成状态（含 `AssetService` 镜像与目标页显示）；上月 15 日中途达成与 20 日快照升值分别记为当天；期初余额已达标时不编造日期；把跨越交易改到明天、改小金额或删除后旧 `reachedAt` 被清除并持久化。
- 信用账户还款回归：详情页只列出同币种现金账户，确认可编辑金额后生成现金到信用账户的实际转账，并同时刷新双方余额与实际现金流出。
- 历史账单回归：验证结算日 25、还款日 14 时，4 月 29 日交易归入 5 月 25 日结算账单并对应 6 月 14 日还款；在 390×844 视口打开账单月份列表、选择往期、切换金额/时间线/明细，并确认其他账期交易不混入。
- 原始账单与每月 1 日结算回归：验证已还款历史月份仍显示原始账单额；8 月 1 日结算显示为 7 月账单；7 月三笔 MYR 69.85、161.33、82.11 合计为 MYR 313.29，且下一期已使用额度不读取累计账户余额。旧导入消费明细缺失时，验证结算日至还款日的明确转入还款可作为原始账单额下限。
- 银行结单快照回归：验证完成对账后传入的权威账单金额覆盖交易合计与还款下限；未提供快照时保持原推算，损坏 meta 必须安全回退。历史快照不得改变当前欠款和额度使用。
- 已确定账单与银行明细回归：未来 `actual` 分期按各月结算日形成可浏览账单并显示对应还款日，未来 `planned` 完全排除；UOB 样本以账单截止余额纳入消费、还款和退款，防止使用毛消费额替代待还金额；本期已还清且存在超额还款时，下期已使用额度扣除可证明的超额部分，同时保留下一结算日前未来已确定消费。
- 投资市值入口回归：在 390×844 逻辑像素验证投资账户详情可打开市值更新表单、账户被锁定为当前账户，长账户名不产生横向溢出。
- 投资成本回归：验证首张快照成本基线、后续投入和取出按截止日计算剩余成本；报表、账户卡片和详情页均以剩余成本计算未实现盈亏，取出不得制造虚假亏损，首张快照之前的取出不得重复扣除；`planned` 不参与实际投入与取出。
- 快照余额回归（`snapshot_balance_rebuild_test.dart`，17 项）：全部以内存 Drift 数据库真实写入，并通过重新 `FinanceRepository.load` 读取持久化值。多数用例额外断言远期 `accountBalanceAt` 等于 `current_balance`。
  - 删除：删除唯一快照（无交易恢复 1000；含转入与收入时按期初余额重放为 1400）；无转账时删除最新快照（1320）或历史快照（1570 不变）；1 月 1000、3 月 1200 快照后补录 2 月转入 100，删除 3 月快照被 `SnapshotBalanceAmbiguityException` 拒绝，重新加载后两张快照、3 月市值 1300 与余额 1300 均不变；仅有 `planned` 转账时不拒绝。
  - 编辑：市值 1000→1050 且其后有 100 收入时为 1150；有转账时原地编辑最新快照（1170）；把最新快照移到收入之后（1050）；改变最新快照被拒绝且数据不变；改换账户抛 `ArgumentError`。
  - 新增：回溯日期快照不覆盖锚点；已有 3 月转入 100 后插入市值 1050 的 2 月快照，存储市值为 1150、余额为 1180，2 月底读取 1050、3 月底 1180，`planned` 转账不折入。
  - 快照之后读取：1 月 10 日快照 1000、1 月 20 日收入 100、2 月收入 50 时，1 月 31 日为 1100、1 月 15 日为 1000（不是 950）；含转账的序列逐日核对，追溯终值与余额一致；`AccountService` 结果与 Repository 一致。
  - 首张快照之前：1 月底为 1050 / 0 / 0，而非 1200 / 900；`AssetService` 与 `AccountService` 镜像一致。
- 状态与时间口径回归：验证 EPF/退休账户默认余额与流入只到当前月、未来 `actual` 不提前进入普通账户默认现状、`planned` 不进入实际余额；信用卡账单不读取未来交易，但当前欠款和额度使用包含未来 `actual`、排除未来 `planned`；预测从今天余额起算并只累计一次未来实际/预计交易。
- 信用卡当前欠款回归（`credit_card_outstanding_test.dart`，7 项，其中 3 项为复审跟进新增，见下一条）：固定参考时间 2026-07-20 10:00、结算日 15 日时，`creditCardOutstandingBalance` 实时为 195（含两期后分期、排除预计 200），截至 7 月 20 日日终为 140，溢缴 80 的卡实时与历史均为 0；`creditCardBillingSummary` 把当天 18:30 的 40 计入欠款与未出账，本期账单保持 100，而不是被少算为 60；历史截止 7 月 31 日时下期只含 40。状态判定在仅有远期已确定欠款时返回 `unbilledOnly`。390×2400 账户页 Widget 验证信用分组“负债总额”470、含分期卡 350、远期分期卡 120、溢缴卡不显示 80 且只有溢缴卡显示“暂无欠款”；该 Widget 用例在未修复代码上失败（找不到“负债总额  MYR 470.00”）。
- 信用卡复审跟进回归（16 项，含主审终轮 2 项）：
  - 净资产（`credit_card_outstanding_test.dart`）：`creditCardCreditBalance` 对溢缴卡实时为 30、7 月 31 日截止为 80，对欠款卡为 0；上一 Widget 用例追加断言溢缴 80、欠款 470 时净资产为“- MYR 390.00”；新增历史月份 Widget 用例验证本月 −440（溢缴已降为 30）、切换上月后 −390，负债仍为 470。
  - 历史精确截止（同文件）：7 月 20 日 10:00 消费 20、18:00 消费 40，截止 09:00 时欠款/本期/下期为 100/100/0，截止 12:00 时为 120/100/20，18:00 消费不进入历史欠款或账单。
  - 原始账单（`credit_card_billing_test.dart` 的 original statement amount 组，7 项）：消费 100、结算后还款 150 为 100；消费 100、全额退款 100、还款 100 为 0；转出 60、调整 20 为 40；无来源流水时回退还款 184.52 且空列表为 0；旧版同币种 `toAmount=0` 还款回退为 120；无来源流水、还款 100 后以负转账撤销 150 时为 0（主审终轮）；覆盖值优先（130、90，负值下限 0）。既有 3 月 184.52、7 月 313.29、UOB 2104.56 与覆盖 212.32 用例保持通过。
  - 账户设置表单（`account_form_credit_balance_test.dart`，4 项）：标签“信用卡余额”与说明文字可见、旧标签不存在、打开时显示 `-250.00`；未修改保存 −250/+80 保持原符号；编辑为 `-300.5`/`45` 后保存保持符号；`NaN`/`Infinity`/`-Infinity` 显示“请输入有效金额”且不返回账户。
  - 还款金额（`credit_card_statement_history_test.dart`）：`NaN`/`Infinity`/`-Infinity` 均提示且对话框保持打开，账本仍只有 1 笔消费、卡余额 −500。
  - 本期已还清的提前还款（同文件，主审终轮）：本期消费 100 已还 100，下期之后连续 3 个账期各有 100 的 `actual` 分期（下一账期为空）；390×844 下主金额标签为“本期账单”、无“下期已使用额度”，状态“本期已还清”，按钮为“提前还款”且可点击、不出现“无需还款”；选择现金账户后金额框默认 `300.00`，取消后交易仍为 5 笔、当前欠款仍为 300。
  - 失效验证：旧版原始账单函数运行新组时 4 项失败，其中“消费 100 还 150”报 `Expected: <100> Actual: <150.0>`；临时撤销其余四项修复的核心行后，净资产（2）、精确截止、表单标签、表单非有限值与还款非有限值共 6 项失败；两项表单保号用例在旧代码上也通过（旧实现本就不翻转符号），属于防止将来误加翻转的守护用例；随后按备份逐字节恢复（`cmp` 一致）。主审终轮：临时撤销两项修复后，负转账用例报 `Expected: <0> Actual: <-50.0>`，提前还款用例找到“无需还款”；仅撤销默认金额回退时报 `Expected: 300.00 Actual: 0.00`；随后从备份恢复。
- 交易批量删除回归：在 390×844 视口长按第一笔、点击追加第二笔、确认删除，验证两行立即消失、成功提示出现且账户余额恢复；数据库层另以一个有效 ID 和一个失效 ID 验证整批回滚。
- 交易编辑删除与有符号金额回归：编辑页滚动至删除入口后分别验证取消与确认；确认结果只包含待删除 ID。金额用例覆盖 `0.00` 与负数保存，并在 Repository 层验证零金额无余额影响、负支出/负转账的代数方向及删除后的余额完全恢复。
- 同/跨币种转账回归：表单显示双金额；同币种自动相等、转入栏只读且保存 `toAmount=NULL`。跨币种按 Repository 当前汇率自动填值，允许覆盖后将该值写入目标余额；旧快速模板遗留的非零同币种转账 `toAmount=0` 必须按来源金额计入目标账户。应用打开与 JSON 导入会归一字段，并只为 `actual`/`settled` 补回目标余额。
- 交易菜单与周期生成回归：验证整行点击仍进入编辑，三点菜单五项均可见；复用新增使用新交易流程，保存模板和保存周期真实写入 Repository，菜单删除确认后实时刷新。快速模板管理页另覆盖“加号→填写交易→保存→确认模板名称→返回列表”完整路由，要求无已销毁输入控制器、`_dependents.isEmpty` 或退场动画异常。新增交易选择三个月时验证生成三笔且全部继承所选状态；实际规则的未来月份全部为实际，预计规则的所有月份全部为预计。
- 集成测试：AI 网关在本地服务不可用时跳过，不影响离线测试通过。
- 外部 AI 提示词回归：验证提示词同时声明消费发生、现金收付、信用负债，明确信用卡还款不是消费、投资市值调整不是收入、未来 `actual` 是未来已确定、`planned` 单列预计，并兼容完整备份 JSON。
- 贷款回归：验证等额本息常规月供与尾期清零、等额本金递减月供、平息贷款总利息、等额本息/平息贷款的银行核定月供尾期调整、中途建账余额只生成待追踪期数、31 日在短月份夹到月末、v9 合同/追踪日期字段持久化与 JSON v3 导出；390×844 Widget 验证每期预计及实际记录显示完整月供、现金扣除月供、贷款只减少本金，旧预计本金/利息自动合并，通用交易编辑器保存后仍保留这两个金额。
- 贷款删除与补齐回归：删除新版月供后验证现金及贷款余额恢复、下一期待记录期回退；删除旧版利息时验证互补本金同事务删除。按钮覆盖首次生成 N 期、部分存在时补齐 N 期、全部存在时禁用三种状态。

## 完成门禁

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build windows --debug
```

格式检查退出码非 0 时视为未通过：只对报告的文件执行 `dart format`，确认差异仅为空白后重跑全部检查，与 [发布流程](RELEASE_WORKFLOW.md) 的源码检查一致。

发布前还需执行 Android release build、实体 Android 设备触控/返回键测试，以及导入真实 v1/v6 备份的人工回归。

本次变更已验证 Windows debug 构建及 Android ARM64 Debug APK 构建。Android Debug 变体必须验证包名为 `com.financecompass.app.debug`、桌面名称为“Finance Compass Debug”，并能与正式版并存且不共享本地数据。Android release 和实体设备完整回归仍是 Play Store 发布前门禁；升级 Flutter 工具链前，需确认应用与 `file_picker`、`file_saver`、`share_plus` 的 Kotlin 兼容性。

2026-07-17 预算/主题校准回归：`flutter test` 结果为 26 项通过、2 项按设计跳过（外部 AI 网关未启动、人工视觉截图用例默认关闭）；`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，仍保留既有 lint info 与未使用声明 warning。Android ARM64 Debug 以 `--no-track-widget-creation` 构建，保留 Debug 身份与开发签名，同时将测试包控制在 Google Drive 上传限制内。

2026-07-17 交易与账期回归：`flutter test` 结果为 32 项通过、2 项按设计跳过；新增 `credit_card_billing_test` 跨月/月末用例、`cash_flow_range_test`、`transaction_composer_edit_test`、`transactions_v2_navigation_test` 和 `dashboard_forecast_range_test`。`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，保留项目既有 lint info 与未使用声明 warning。

2026-07-17 信用卡日期语义迁移回归：`flutter test` 结果为 33 项通过、2 项按设计跳过；数据库升级用例确认旧信用卡 `transaction_date` 改用 `record_date` 且现金交易不变，数据可携用例确认 v1/v2 归一化及 v3 编辑后发生日期往返保留。`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，保留 102 项既有 lint info/warning。

2026-07-17 交易状态与时间口径回归：`flutter test` 结果为 36 项通过、2 项按设计跳过；新增 EPF/退休账户未来实际与预计记录、信用卡未来记录隔离，以及现金流预测不重复累计的回归用例。`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，保留 102 项既有 lint info/warning。

2026-07-17 信用卡展示状态与投资市值入口回归：`flutter test` 结果为 39 项通过、2 项按设计跳过；信用卡已还清状态不会因还款日已过误报逾期，投资账户在 390×844 视口可打开锁定当前账户的市值更新表单，长账户名无溢出。`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，保留 101 项既有 lint info/warning。

2026-07-17 信用卡转账方向回归：`flutter test` 结果为 40 项通过、2 项按设计跳过；信用卡 A 转至信用卡 B 时，A 的账单增加且明细可见，B 只按还款减少负债。`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，保留 101 项既有 lint info/warning。

2026-07-17 交易批量删除回归：`flutter test` 结果为 42 项通过、2 项按设计跳过；长按可进入多选、点击追加第二笔并确认删除后列表实时刷新且账户余额恢复，包含失效 ID 的整批删除会完整回滚。`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，保留 101 项既有 lint info/warning。

2026-07-17 交易操作菜单与可选周期回归：`flutter test` 结果为 44 项通过、2 项按设计跳过；新增 `transaction_action_menu_test` 覆盖整行编辑、复用新增、模板/规则落库和单笔菜单删除，`transaction_composer_edit_test` 覆盖 1–12 个月选择中的三个月连续生成及实际/预计状态。`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，项目现有 lint 总数为 104 项。390×844 菜单截图已与用户旧版截图同屏对照；Android ARM64 Debug 和 Windows x64 Release 均构建成功，`aapt` 确认包名 `com.financecompass.app.debug`、标签 `Finance Compass Debug`、版本 `0.8.0-debug`、versionCode `2015`。

2026-07-18 信用卡承诺负债与周期状态回归：`flutter test` 结果为 48 项通过、2 项按设计跳过；新增信用卡未来 `actual` 计入当前欠款/额度、未来 `planned` 排除、显式账单截止仍不读取未来交易，以及实际/预计周期规则在所有生成月份保持原状态的回归。`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，项目现有 lint 总数仍为 104 项。Android ARM64 Debug 和 Windows x64 Release 均构建成功；`aapt` 确认 Debug 包名 `com.financecompass.app.debug`、标签 `Finance Compass Debug`、版本 `0.8.0-debug`、versionCode `2016`。

2026-07-18 信用卡历史账单回归：`flutter test` 结果为 50 项通过、2 项按设计跳过；领域测试确认 25 日结算、14 日还款时，4 月 29 日消费进入 5 月账单并在 6 月 14 日还款，Widget 测试在 390×844 视口完成月份列表打开、往期选择、明细隔离和返回入口检查。`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，项目既有 lint 总数为 104 项。Android ARM64 Debug 和 Windows x64 Release 均构建成功；`aapt` 确认 Debug 包名 `com.financecompass.app.debug`、标签 `Finance Compass Debug`、版本 `0.8.0-debug`、versionCode `2017`。

2026-07-18 编辑删除与有符号金额回归：`flutter test` 结果为 55 项通过、2 项按设计跳过；Widget 测试覆盖编辑页取消/确认删除以及 `0.00`、`-25.50` 保存，Repository 测试覆盖零金额、负支出、负转账及删除后的双边余额恢复。`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，项目既有 lint 总数仍为 104 项。Android ARM64 Debug 和 Windows x64 Release 均构建成功；`aapt` 确认 Debug 包名 `com.financecompass.app.debug`、版本 `0.8.0-debug`、versionCode `18`。

2026-07-18 未来已确定账单与银行余额回归：`flutter test` 结果为 58 项通过、2 项按设计跳过；新增 Shopee PayLater 未来三期已发生账单、预计排除、未来月份详情，以及 UOB 消费/还款/退款后的结算日余额回归。`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，项目既有 lint 总数仍为 104 项。Android ARM64 Debug 和 Windows x64 Release 均构建成功；`aapt` 确认 Debug 包名 `com.financecompass.app.debug`、版本 `0.8.0-debug`、versionCode `19`。Android 构建继续提示 Flutter 将来会要求应用及插件迁移至 Built-in Kotlin，当前构建不受影响。

2026-07-18 Shopee PayLater 原始账单与 UOB 还款对账回归：`flutter test` 结果为 59 项通过、2 项按设计跳过；新增已还款账单保留原始金额、每月 1 日结算按前一日命名，以及单期 MYR 313.29 不受累计余额影响的领域回归。`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译 error，项目既有 lint 总数仍为 104 项。Android ARM64 Debug 和 Windows x64 Release 均构建成功；`aapt` 确认 Debug 包名 `com.financecompass.app.debug`、标签 `Finance Compass Debug`、版本 `0.8.0-debug`、versionCode `20`。UOB 样本中的 MYR 238.38 Shopee 还款已按 7 月 1 日银行交易日核对；补齐 3 月 MYR 184.52 和 4 月 MYR 161.33 后，3–9 月账单逐期匹配，当前欠款与未来三期合计同为 MYR 870.07。SQLite 完整性检查为 `ok`，外键错误为 0；Android 构建仍仅提示未来 Built-in Kotlin 迁移要求。

2026-07-18 Lazada PayLater 数据对账：结算日校正为 9 日并保留 25 日还款；7 月四项含全额退款净额为 MYR 195.91。补齐 LiberNovo 1/12–12/12、重排两个 6 期分期并将全部已确定记录设为 `actual` 后，7–9 月各 MYR 195.91、10 月 MYR 195.97、11 月至 2027 年 5 月各 MYR 180.88；当前欠款与这些未还已确定账单合计均为 MYR 2,049.86。SQLite 完整性为 `ok`，外键错误为 0，Lazada 账户 `planned` 记录数为 0。

2026-07-18 UOB 已使用额度对账：银行口径由 6 月 25 日账单 MYR 5,346.29，加结算后消费 MYR 3,371.32，再减还款及退款 MYR 7,153.93，得到 MYR 1,563.68。删除银行不存在的第 7 笔 MYR 300 BTIPP 分期，以 MYR -984.49 校正不完整旧账本的期初余额，并重建物化余额后，账本重算与银行均为 MYR 1,563.68，差额为零；SQLite 完整性为 `ok`、外键错误为 0。`credit_card_billing_test.dart` 12 项通过，覆盖超额还款抵扣、下一结算日前未来已确定消费保留，以及缺少还款凭据的 PayLater 旧资料不被余额反推污染。全量测试 61 项通过、2 项按设计跳过；静态分析无编译错误，项目既有 lint 总数仍为 104 项。

2026-07-18 UOB 历史结单快照对账：银行 PDF/XLS 确认 2026 年 3 月 25 日、4 月 25 日、5 月 25 日和 6 月 25 日原始账单分别为 MYR 2,364.37、1,995.35、4,352.32、5,346.29。应用通过账户级 `app_meta` 快照优先展示这些权威值，避免后续还款 MYR 5,746.30 被误作 6 月原始账单；当前欠款仍为 MYR 1,563.68。写入前建立独立备份，SQLite 完整性为 `ok` 且外键错误为 0。定向账期测试 14 项通过；全量测试 61 项通过、2 项按设计跳过；静态分析无编译错误并保留 101 项既有 lint。Windows x64 Release build 22 构建并启动成功，原生界面已核对月份列表及 5 月历史详情金额。

2026-07-18 发布恢复包回归：`tool/export_release_data_test.dart` 从 SQLite 在线备份调用 Repository 生成完整 v3 JSON，并在写盘后重新解析校验全部必需集合；导出数量为账户 16、分类 29、预算 13、交易 672、投资快照 34、模板 7、周期规则 6。ARM64 Debug APK 的 `aapt` 结果为 `com.financecompass.app.debug`、`Finance Compass Debug`、`0.8.0-debug`、versionCode `2022` 和 `arm64-v8a`。本机 `G:\我的云端硬盘\Finance Compass APK` 与 Drive 云端元数据均确认 JSON 与 APK 大小分别为 371,284 和 84,956,046 bytes。

2026-07-18 交易“包含预计”口径回归：新增 390×844 Widget 测试，默认只显示 MYR 100 已发生支出，切换后保留已发生并加入 MYR 40 预计，顶部支出同步变为 MYR 140；原未来月份导航与编辑回归继续通过。全量测试 62 项通过、2 项按设计跳过；`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译错误，保留 104 项既有 lint。ARM64 Debug APK 核对包名 `com.financecompass.app.debug`、应用名 `Finance Compass Debug`、版本名 `0.8.0-debug`、versionCode `2023` 和架构 `arm64-v8a`。完整 v3 JSON 从 SQLite 在线备份导出并验证，APK 与 JSON 的 Drive 本地同步副本 SHA-256 均与工程产物一致。

2026-07-18 交易三口径与 Product Design 方案 2 回归：新增 390×844 Widget 测试，以现金支出 MYR 100、信用消费 MYR 300、还款 MYR 200、预计现金 MYR 40 和预计信用 MYR 50 分别验证消费发生 -MYR 400、现金收付 -MYR 300、当前已承诺 MYR 100，以及包含预计后 MYR 150；原“包含预计”和未来月份编辑回归继续通过。全量测试 63 项通过、2 项按设计跳过；静态分析无编译错误，保留 104 项既有 lint。390×844 实现截图与选定方案 2 合成同屏，筛选行经一次迭代后通过视觉门禁。SQLite 在线备份完整性为 `ok`、外键错误为 0；v3 JSON 验证为 16 个账户、29 个分类、13 个预算、672 笔交易、34 个快照、7 个模板、6 条周期规则。ARM64 Debug APK 核对包名 `com.financecompass.app.debug`、应用名 `Finance Compass Debug`、版本名 `0.8.0-debug`、versionCode `2024` 和架构 `arm64-v8a`；APK 与 JSON 的 Drive 本地同步副本 SHA-256 均与工程产物一致。

2026-07-19 外部 AI 提示词 v3 回归：新增 2 项提示词测试，验证消费发生、现金收付、信用负债三口径，信用卡还款与消费分离，投资调整不算收入，未来 `actual`/`settled` 标记为未来已确定、`planned` 单列预计，并兼容完整备份 JSON。全量测试 65 项通过、2 项按设计跳过；静态分析无编译错误，保留 104 项既有 lint。SQLite 在线备份完整性为 `ok`、外键错误为 0；v3 JSON 验证 16 个账户、29 个分类、13 个预算、672 笔交易、34 个快照、7 个模板和 6 条周期规则。ARM64 Debug APK 核对包名 `com.financecompass.app.debug`、标签 `Finance Compass Debug`、版本名 `0.8.0-debug`、versionCode `2025` 和 `arm64-v8a`；APK 与 JSON 的 Drive 副本 SHA-256 均与工程产物一致。

2026-07-20 现金账户转账双边余额回归：新增 `cash_transfer_balance_test.dart` 4 项测试，分别覆盖 Repository 写入与重新加载、`TransactionMutations` 发布刷新后的 provider、新版 `TransactionComposerPage` 实际选择目标现金账户后保存并落库，以及账户总览中的 Grab → UOB One 实时刷新。MYR 250 从余额 MYR 1,000 的来源账户转至余额 MYR 100 的目标账户后，两边显示与存储余额分别为 MYR 750 和 MYR 350；定向测试全部通过。该结果说明标准“同币种、当月、已发生”路径可正确更新转入账户，尚未复现手机端报告的异常。

2026-07-20 快速模板排序与指定账户刷新回归：`quick_template_reorder_test.dart` 验证完整模板 ID 顺序会持久化为连续 `sortOrder`，重载后顺序不变；390×844 Widget 用例调用可重排列表把第 6 个模板拖到第 1 位，并确认新的前五顺序立即发布。现金转账用例同时扩展为账户总览中的 Grab → UOB One，MYR 250 转账后分别显示 MYR 750 与 MYR 350。两份定向测试共 6 项通过；全量测试 71 项通过、2 项按设计跳过，静态分析无编译错误并保留 104 项既有 lint。SQLite 在线备份完整性为 `ok`、外键错误为 0；v3 JSON 包含 16 个账户、29 个分类、13 个预算、672 笔交易、34 个快照、7 个模板和 6 条周期规则。ARM64 Debug APK 为 `com.financecompass.app.debug`、`Finance Compass Debug`、`0.8.0-debug`、versionCode `2026` 和 `arm64-v8a`，APK 与 JSON 的 Drive 本地同步副本哈希一致。

2026-07-20 Android 导出与恢复安全回归：移除会吞掉 Android 写入异常的 `file_saver`，所有 JSON/CSV 保存统一走 `file_picker.saveFile(bytes: ...)`。定向测试验证 0 KB 文件会被拒绝且原账户保留、缺失目标账户的转账备份会在替换前失败且原数据库不变、合法 v3 备份恢复后 `HomeScreen` 的六个主页面可共同构建而不出现黑屏；5 项定向测试通过。全量测试 74 项通过、2 项按设计跳过；静态分析无编译错误，保留 104 项既有 lint。正式导入在同一事务内追加 SQLite 完整性检查。发布工具把 371,284-byte v3 JSON 真实恢复到空数据库，核对 16 个账户、29 个类别、13 个预算、672 笔交易、34 个快照、7 个模板和 6 条周期规则；SQLite 快照 `quick_check=ok`、外键错误为 0。build 27 ARM64 Debug APK 核对 `com.financecompass.app.debug`、`Finance Compass Debug`、`0.8.0-debug`、versionCode `2027` 与 `arm64-v8a`，APK 和 JSON 的 Drive 副本 SHA-256 与工程产物一致。

2026-07-20 同币种转账零转入金额回归：新增领域测试确认旧 `toAmount=0` 仍按唯一来源金额入账，Widget 测试确认新版表单保存 `toAmount=NULL`，数据可携测试确认导入会补回目标余额并归一交易。用户提供的 376,268-byte v3 JSON 已真实导入，17 个账户、29 个分类、13 个预算、681 笔交易全部恢复，3 笔异常转账完成修复。全量测试 76 项通过、2 项按设计跳过；静态分析无编译错误，保留 104 项既有 lint。build 28 ARM64 Debug APK 为 `com.financecompass.app.debug`、`Finance Compass Debug`、`0.8.0-debug`、versionCode `2028` 和 `arm64-v8a`；修复 JSON 为 376,326 bytes，两项 Drive 副本 SHA-256 均与工程产物一致。

2026-07-20 新版跨币种转账回归：390×844 Widget 用例确认 MYR 250 转入 MYR 时显示只读 MYR 250.00 并保存 `toAmount=NULL`；转入 TWD 时按 1 MYR = 7.1429 TWD 自动填入 TWD 1,785.71，用户覆盖为 TWD 1,800 后目标账户增加 1,800。全量测试 77 项通过、2 项按设计跳过；静态分析无编译错误，保留 104 项既有 lint。`validate_import_data_test.dart` 将可信 v3 备份真实恢复并重新导出，核对 17 个账户、29 个类别、13 个预算和 683 笔交易，未发现需要修复的旧式同币转账。build 29 ARM64 Debug APK 经 `aapt` 核对为 `com.financecompass.app.debug`、`Finance Compass Debug`、`0.8.0-debug`、versionCode `2029` 和 `arm64-v8a`；APK 为 84,689,324 bytes、JSON 为 377,347 bytes，复制到本地 Google Drive 后的 SHA-256 分别为 `90B2A37375C95FBCB1CECEB031B44230C0F451007A6A1C46C4820BDBFE62F3E0` 与 `6A7B24964E27AD48A5C3AB7824F2563F6509A8C32DD271C14A62954BCF96FAD7`，均与工程源产物一致。

2026-07-21 贷款摊销与还款落账回归：`loan_amortization_test.dart` 覆盖等额本息、等额本金、平息贷款、两种定息法的银行核定月供、月末夹取、v9 合同/追踪日期持久化和 JSON 字段。RM120,000、2.1%、108 期平息贷款按 RM1,316 常规月供生成 RM1,868 合同尾期；实际中途建账案例使用等额本息：合同始于 2022-05-23、首期合同还款日为 2022-06-23，从 2026-06-30 的 RM71,097 剩余贷款开始，只生成 57 期待记录计划，下一期为 2026-07-23，首期本金/利息为 RM1,191.58/RM124.42，预计剩余利息 RM3,654.44、剩余还款 RM74,751.44，不生成历史交易。`loan_detail_screen_test.dart` 在 390×844 验证开始余额保存及一期还款的本金/利息拆分。v6 构造库逐级升级到 v9 后旧余额保持且新增字段为空。全量测试 86 项通过、2 项按设计跳过；静态分析无编译错误，保留 103 项既有 info/warning；Windows debug 构建成功。build 30 ARM64 Debug APK 核对包名、标签、versionCode、ABI、文件大小与 SHA-256 后上传至 Drive；Drive 元数据返回 84,888,884 bytes，与本地文件一致。

2026-07-21 周期与贷款预计交易回归：`recurring_transaction_rule_test.dart` 验证保存规则即生成未来 3 个完整日历月且全部为 `planned`；交易菜单及数据可携测试同步验证自动生成记录会进入列表与完整备份。`loan_detail_screen_test.dart` 验证新建贷款后的生成询问、暂不生成、详情页再次生成、12 期本金/利息共 24 笔预计记录，以及记录首期后对应预计组合被两笔实际记录替换。全量测试 86 项通过、2 项按设计跳过；`flutter analyze --no-fatal-infos --no-fatal-warnings` 无编译错误，保留 102 项既有 info/warning。Windows Debug EXE 构建成功；build 31 ARM64 Debug APK 为 `com.financecompass.app.debug`、`Finance Compass Debug`、`0.8.0-debug`、versionCode `2031` 和 `arm64-v8a`，大小 84,892,088 bytes，Drive 回读一致。构建仍提示 Flutter 将来要求应用与插件迁移 Built-in Kotlin，当前产物不受影响。

2026-07-21 全应用交互审计回归：Windows 实机逐页检查六个主页面、规则中心、周期计划和周期规则编辑页；`interaction_wiring_test.dart` 的源码门禁及 4 项 Widget 流程全部通过。全量测试 91 项通过、2 项按设计跳过；静态分析无编译错误，保留 104 项 info/warning。Windows Debug EXE 重建并打开成功；build 32 ARM64 Debug APK 为 versionCode `2032`、`arm64-v8a`、84,897,452 bytes，Drive 回读大小一致。未实现的系统推送、Google 登录、系统主题跟随和附件均以禁用“计划中”状态保留。

2026-07-21 贷款月供金额修正回归：新增旧预计本金/利息自动合并和通用编辑器保留结构化月供两项 Widget 回归；等额本金样本验证月供 1,120、本金 1,000，现金余额减少 1,120、贷款余额只减少 1,000。全量测试 93 项通过、2 项按设计跳过；静态分析无编译错误，保留 104 项 info/warning。Windows Debug EXE 实机确认 Loan120K 月供 RM1,316；build 33 ARM64 Debug APK 的 versionCode、ABI、文件大小与 Drive 回读一致。

2026-07-21 贷款整期删除与补齐计数回归：删除新版月供后验证贷款和现金余额恢复、下一期从第 2 期退回第 1 期；选择旧版利息时验证互补本金成组删除。预计按钮验证“生成 12 期”“补齐 11 期”和“预计交易已补齐”三种状态，对任意计划总数使用相同集合差算法。全量测试 94 项通过、2 项按设计跳过；静态分析无编译错误，保留 104 项 info/warning。Windows Debug EXE 已打开；build 34 ARM64 Debug APK 的 versionCode、ABI、文件大小和 Drive 回读一致。

2026-07-21 账户统计截止专项回归：Windows Debug 先复现“统计截止”点击无响应，再在 build 35 验证月份选择器、2026 年 6 月历史横幅及资产/负债变化；保存整改前后四张证据。账户、贷款、信用卡、投资详情 Widget 用例验证历史模式隐藏写入入口并可返回当前状态，类别管理用例验证折叠。全量测试 100 项通过、2 项按设计跳过；静态分析无编译错误，保留 105 项 info/warning。Windows Debug EXE 与 ARM64 Debug APK 均构建成功；APK 经 `aapt` 核对包名 `com.financecompass.app.debug`、versionCode `2035` 和标签 `Finance Compass Debug`，大小 84,918,420 bytes，Drive 回读一致。

2026-07-22 现金口径与预算规则专项回归：新增 `actual_cash_flow_report_test.dart`、`asset_goals_page_test.dart`，并扩展交易导航与交互接线测试。样本验证现金收入 MYR 1,000、现金支出 MYR 100、还卡 MYR 200、贷款月供 MYR 1,316 合计现金流出 MYR 1,616；信用消费 MYR 300 不在刷卡时重复计现。预算验证 4–7 月 MYR 200、8 月起 MYR 400。Drive 最新 JSON 临时恢复为 18 个账户、29 个类别、12 个预算、730 笔交易和 4 个资产目标，7 月实际现金流入/流出 MYR 7,954.70 / 7,255.54，8 月含预计 MYR 7,172.45 / 2,305.00。全量测试 103 项通过、2 项因外部 AI 网关未配置按设计跳过；静态分析无编译错误，保留 105 项既有 info/warning。build 36 ARM64 Debug APK 经 `aapt` 核对为 `com.financecompass.app.debug`、`Finance Compass Debug`、versionCode `2036` 和 `arm64-v8a`；84,934,736-byte Drive 副本与本地产物大小一致。

2026-07-22 总资产目标与信用账户还款回归：目标样本包含现金 MYR 1,000、投资 MYR 500 和信用负债 MYR 800，验证目标当前值及历史末点均为总资产 MYR 1,500，净资产报表仍为 MYR 700。信用卡 Widget 用例验证只列同币种现金账户、可把建议金额改为 MYR 300、确认后生成实际转账，并把现金/信用余额更新为 MYR 1,700 / -MYR 200。全量测试 105 项通过、2 项因外部 AI 网关未配置按设计跳过；静态分析无编译错误，保留 105 项既有 info/warning。build 37 ARM64 Debug APK 为 `com.financecompass.app.debug`、`Finance Compass Debug`、versionCode `2037` 和 `arm64-v8a`；Drive 回读大小 84,936,860 bytes，与本地产物一致。

2026-07-22 月度资金需求回归：单元样本验证普通现金支出 MYR 989、贷款转账 MYR 1,316、到期贷款 MYR 1,316 与到期信用 MYR 500 的需准备总额为 MYR 2,805；新增信用还款 MYR 500 后已知现金流出与覆盖额同步增加，总额保持 MYR 2,805，证明不重复计算。贷款覆盖使用没有系统期号文案的普通转账，验证手工还贷同样有效。最新 Drive JSON 的 2026-08 需准备总额为 MYR 4,580.99：已知现金流出 MYR 2,305.00、到期信用 MYR 2,275.99、到期贷款 MYR 1,316.00，其中贷款已覆盖。全量测试 106 项通过、2 项跳过；静态分析无编译错误，保留 105 项既有 info/warning。Windows Debug 实机确认卡片层级与说明无溢出；build 38 ARM64 Debug APK 为 versionCode `2038`、`arm64-v8a`，Drive 回读 84,948,952 bytes 与本地产物一致。

2026-07-22 资金需求卡片整合回归：未来月份顶部只保留“实际消费”“实际现金”“信用/贷款”三种口径；选择“实际现金”后验证“需准备现金”副标题、“已知流出/尚未安排”解释、到期信用/贷款紧凑说明和独立资金大卡不存在。390×844 Widget 样本的需准备总额为 MYR 1,556，Windows 1266×713 Debug 实机显示 MYR 7,206 且列表上移、无横向溢出。全量测试 106 项通过、2 项按设计跳过；静态分析无编译错误，保留 105 项既有 info/warning。build 39 ARM64 Debug APK 为 versionCode `2039`、`0.8.0-debug`、`arm64-v8a`，大小 84,943,304 bytes，Drive 回读一致。

2026-07-27 快速模板创建生命周期回归：390×844 Widget 完整执行“打开快速模板管理页→点击加号→填写 MYR 12.50 交易→保存→确认模板名称→返回列表”，并验证 Repository 中新增一条模板。修复前测试先捕获已销毁 `TextEditingController`，随后复现用户截图中的 `_dependents.isEmpty`；改用表单初始值和局部字符串后不再产生框架异常。全量测试 107 项通过、2 项按设计跳过；静态分析无编译错误，保留 105 项既有 info/warning。build 40 ARM64 Debug APK 为 versionCode `2040`、`0.8.0-debug`、`arm64-v8a`，大小 84,944,204 bytes，Drive 回读一致。

## 2026-08-04 v0.8.0 公开发布验证

- 全量测试：108 项通过，2 项因外部 AI 网关未配置而按设计跳过。
- 静态分析：无编译错误；保留 105 项既有 info/warning。
- Android：核对 `com.financecompass.app`、`0.8.0`、versionCode `41`、三种 ABI、APK Signature Scheme v2、单一签名证书和内置支持收款码。
- Windows：Release 构建成功；主程序元数据为 `Finance Compass 0.8.0+41`；安装程序由 Inno Setup 6.7.3 编译成功；便携 ZIP 包含主程序、运行库、插件、`data/` 和支持收款码。
- 发布文件：安装程序、便携 ZIP、Android APK 的 SHA-256 已生成并从 `SHA256SUMS.txt` 逐项回算通过。详细证据见 [v0.8.0 公开发布 QA](public-release-qa-v0.8.0-2026-08-04.md)。

## 2026-09-24 v0.9.1 发布准备源码检查（尚未发布）

- 格式：首次检查有 6 个文件不合规；格式化后，去除空白的内容比对确认与格式化前一致，重跑 `dart format --output=none --set-exit-if-changed lib test` 退出码 0（141 个文件，0 个需改）。
- 全量测试：131 项通过，2 项按设计跳过。
- 静态分析：`flutter analyze --no-fatal-infos --no-fatal-warnings` 退出码 0，无编译错误；保留 106 项既有问题（3 项 warning、103 项 info）。
- 未执行：Android/Windows/自托管发布构建、签名核对、SHA-256 与实体设备回归，这些仍按 [发布流程](RELEASE_WORKFLOW.md) 待办。详见 [变更记录](CHANGELOG.md)。

## 2026-09-24 v0.9.1 自托管 Web 构建交付契约验证（尚未发布）

- 复现：`build/web/.last_build_id` 指向经 junction 路径（`C:\Users\pwlaw\Documents\Codex\…`）的旧构建配置时，从 `D:\Codex\Projects\…` 直接运行 `flutter build web` 打印 `Built build\web`，文件数却由 44 降为 24，`manifest.json` 等被删；清空输出目录后仍经 junction 构建时，`main.dart.js`、`assets/`、`canvaskit/` 仍缺失（stamp 中混有 C:/D: 两种路径）。修复后两种路径均产出相同的 142 个文件。
- Windows：`tool/build_web.ps1` 分别经 junction 路径与物理路径运行，均以 `142 files, 36 precache entries and 102 fallback fonts verified` 结束；`sqlite3.wasm` 为 730,989 bytes、SHA-256 `922A76B1…52117`，与锁定一致；无 `*.symbols`、`*.map`、`*.deps`、`.last_build_id`、`drift_worker.dart`。
- Shell：Git Bash（`MSYS2_ARG_CONV_EXCL='*'`）运行 `tool/build_web.sh`，结果同为 142 个文件、36 项预缓存、102 个字体。Docker 构建未在本机执行（无 Docker），其 `RUN` 与该脚本相同。
- 负向：向 `CORE` 加入不存在的 `./not-shipped.js`、从 `SHA256SUMS` 删除一行、移除 Roboto 家族，以及伪造 Flutter 写入部分输出后退出 1，均按预期失败；失败后 `build/web` 已删除。
- 浏览器：Edge headless，按 Caddy CSP 提供 `build/web`：首次加载、重载与离线重载均由 `service-worker.js` 控制，缓存 138 项（36 项 `CORE` + 102 个字体），无 CSP/字体错误、无第三方请求，中文界面文字完整显示（离线重载亦然）。修复字体前同样环境下界面完全没有文字，并出现约 2 万次被 CSP 拒绝的 `fonts.gstatic.com` 请求。
- 打包：`package_selfhost.ps1 -SkipWebBuild` 输出到临时目录，ZIP 条目均为 `/` 分隔、无 sidecar，`webroot` 与 `build/web` 文件清单一致。
- 测试：`web_delivery_contract_test.dart` 8 项通过；全量 `flutter test` 135 项通过、2 项按设计跳过；`dart format` 无需修改；`flutter analyze` 无 error，保留 106 项既有问题（3 项 warning、103 项 info，均不在本次修改文件中）。
- 更正：2026-08-04 v0.9.0 记录中“输出不含 `gstatic.com`”并不准确——旧 PowerShell 检查对 `Get-Content -Raw` 多文件返回的数组调用 `.Contains()`，实际从未比对子字符串；`flutter.js` 始终包含 gstatic CanvasKit URL，`main.dart.js` 始终包含字体回退地址，同一检查在 shell/Docker 中会必然失败。

## 2026-09-25 v0.10.0 发布验证

- 源码：全量 `flutter test` 156 项通过、2 项按设计跳过、0 失败。`dart format --output=none --set-exit-if-changed lib test` 检查 140 个文件，0 改动。`flutter analyze --no-fatal-infos --no-fatal-warnings` 为 0 error、2 项既有 warning、65 info。
- Android：versionName `0.10.0`、versionCode `44`，含 3 个 ABI，v2 签名校验通过；证书 SHA-256 与 v0.9.1 相同。
- Windows：ProductVersion/FileVersion 为 `0.10.0+44`。Inno Setup 6.7.3 编译成功，便携 ZIP 共 23 个条目。
- 自托管 Web：构建结果为 142 个文件，验证 36 项预缓存和 102 个回退字体。三份自托管 ZIP 各有 150 个条目，均含 `webroot/index.html` 与 `compose.yml`。
- 发布文件：六项产物的 SHA-256 与 `SHA256SUMS.txt` 逐项一致；支持二维码的哈希与 v0.9.1 相同。
- GitHub 回读：PR #7 合并提交的 tree 与构建时源码 tree 相同，`v0.10.0` 标签 peel 到该提交；Release 非草稿、非预发布且为 Latest。七个附件的 size 与 SHA-256 digest 与本机一致；README 六条直链无认证 HEAD 均为 200，`Content-Length` 与本机一致。
- 未执行：Docker、浏览器离线与 CSP 回归、Windows 安装版或便携版实机打开、Android 真机安装，以及 iOS/Android 浏览器 HTTPS 安装。详见 [v0.10.0 公开发布 QA](public-release-qa-v0.10.0-2026-09-25.md)。

## 2026-09-29 信用卡当前欠款修复验证（未发布）

- 工具链：通过 Windows PowerShell 以绝对路径调用 `C:\Users\pwlaw\tools\flutter\bin\flutter.bat` / `dart.bat`，版本为 Flutter 3.44.1、Dart 3.12.1。`flutter pub get` 前后 `pubspec.lock` 的 SHA-256 相同（`9E53C573…AED7BD7EB`），`git diff` 为空；测试与分析均使用 `--no-pub`。
- 测试：新增用例与信用卡/账户截止相关的 5 个测试文件共 26 项通过；全量 `flutter test --no-pub` 160 项通过、2 项按设计跳过（`visual_qa_capture_test.dart`）、0 失败。
- 修复前对照：在 HEAD（`e1c2ed6`）的临时 worktree 中单独运行新 Widget 用例，按预期失败；该 worktree 已删除。
- 格式与分析：`dart format --output=none --set-exit-if-changed lib test` 检查 141 个文件、0 改动；`flutter analyze --no-fatal-infos --no-fatal-warnings` 退出码 0，共 67 项，均为既有问题（0 error、2 warning、65 info），与 v0.10.0 基线相同，且无一位于本次修改文件。
- 证据：日志保存在本机 `artifacts/qa/credit-debt-2026-09-29-*.log`（`artifacts/` 已被 `.gitignore` 排除，不随仓库提交）。
- 未执行：Windows/Android 实机或截图对照、发布构建。
- 后续：标题保留验证时的“未发布”状态；本修复已随 v0.10.1 公开发布，见下文“v0.10.1 公开发布验证”。

## 2026-09-29 信用卡复审跟进验证（未发布）

- 工具链：同上，通过 Windows PowerShell 以绝对路径调用 Flutter 3.44.1 / Dart 3.12.1；未运行 `pub get`，`pubspec.lock` SHA-256 仍为 `9E53C573…AED7BD7EB`，`pubspec.lock`、`pubspec.yaml`、`analysis_options.yaml` 无改动。
- 测试：相关 7 个文件（`credit_card_billing_test`、`credit_card_outstanding_test`、`account_form_credit_balance_test`、`credit_card_statement_history_test`、`transaction_scope_test`、`account_cutoff_interaction_test`、`loan_detail_screen_test`）共 47 项通过；全量 `flutter test --no-pub` 176 项通过、2 项按设计跳过、0 失败（较上一轮 160 项新增 16 项，其中 2 项为主审终轮新增）。以上为主审终轮修复后的最终结果，取代此前 45/174 的临时数量。
- 修复前对照：见上文“信用卡复审跟进回归”的失效验证；旧函数红灯日志单独保存。
- 格式与分析：`dart format --output=none --set-exit-if-changed lib test` 检查 142 个文件、0 改动；`flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` 退出码 0，67 项均为既有问题（0 error、2 warning、65 info），无一位于本次修改文件。
- 证据：本机 `artifacts/qa/credit-debt-2026-09-29-followup-{item4-old-function-red,items1235-reverted-red}.log`，以及主审终轮 `artifacts/qa/credit-debt-2026-09-29-final-{targeted,negative-control,related-tests,full-test,format,analyze}.log`（不随仓库提交）。
- 未执行：实机或截图对照、发布构建。
- 后续：标题保留验证时的“未发布”状态；本修复已随 v0.10.1 公开发布，见下文“v0.10.1 公开发布验证”。

## 2026-09-29 v0.10.1 发布准备源码检查（待构建发布）

- 范围：版本号同步为 `0.10.1+45`，并收录上面两轮信用卡修复；未改其他应用逻辑。
- 工具链：Windows PowerShell 以绝对路径调用 Flutter 3.44.1 / Dart 3.12.1；`pubspec.lock`（`9E53C573…AED7BD7EB`）与 `analysis_options.yaml` 在检查前后 SHA-256 相同。
- 格式与分析：`dart format --output=none --set-exit-if-changed lib test` 检查 142 个文件、0 改动；`flutter analyze --no-fatal-infos --no-fatal-warnings` 退出码 0，67 项均为既有问题（0 error、2 warning、65 info）。
- 测试：全量 `flutter test` 176 项通过、2 项按设计跳过、0 失败。
- 文档：相对链接检查无失效目标；`git diff --check` 无空白错误。
- 证据：本机 `artifacts/qa/release-v0.10.1-{toolchain,format,analyze,test,hashes-before,hashes-after}.log`（不随仓库提交）。
- 未执行：Android/Windows/自托管发布构建、签名与版本核对、SHA-256、实机回归与 GitHub 发布回读，待填项见 [v0.10.1 发布准备 QA](public-release-qa-v0.10.1-2026-09-29.md)。
- 后续：本节为发布准备阶段记录，标题保留当时状态；构建、发布与回读结果见下一节。

## 2026-09-29 v0.10.1 公开发布验证

- 发布状态：上面两轮信用卡修复与版本同步已随 v0.10.1 公开发布。[PR #9](https://github.com/lawpowen/finance-compass-app/pull/9) 合并提交 `4c1166b6e3f69fe6bfb4fecfbdeb7d82ed152b66` 的 tree `f59b26aafa0534a31e2280e36282c9d14d96f916` 与构建时源码 tree 相同；annotated tag `v0.10.1` peel 到该提交；Release 非草稿、非预发布且为 Latest。
- Android：`apksigner` v2 校验通过；`com.financecompass.app`、versionName `0.10.1`、versionCode `45`，含 `arm64-v8a`、`armeabi-v7a`、`x86_64`；证书 SHA-256 与 v0.10.0 相同。构建日志有既有 Kotlin Gradle Plugin 未来兼容警告，不影响本次构建。
- Windows：ProductVersion/FileVersion 为 `0.10.1+45`。Inno Setup 6.7.3 编译成功，便携 ZIP 共 23 个条目；安装器来自同一 Release 目录，未拆包检查。
- 自托管 Web：构建结果为 142 个文件，验证 36 项预缓存和 102 个回退字体；`sqlite3.wasm` 锁定校验通过。三份自托管 ZIP 各 150 个条目、无反斜杠条目，`version.json`、`CACHE_NAME` 与 Compose 镜像标签均为 0.10.1。
- 私人文件与二维码：APK 与四份 ZIP 按文件名筛查无 `key.properties`、JKS/keystore、SQLite/`.db` 或 backup 文件；包内支持二维码 SHA-256 均为 `2B2413CD…DAD8780B`，本次人工确认收款人为 `LAW PO WEN`。
- 发布文件：`SHA256SUMS.txt` 六项重新核验一致；GitHub 回读七个附件的 size 与 SHA-256 digest 与本机一致，七条公开无认证 HEAD 均返回 200 且 `Content-Length` 一致。
- 发布后文档更新：只做文档内容检查、相对链接检查与 `git diff --check`，未重新运行 Flutter 测试（源码与构建时相同）。
- 证据：本机 `artifacts/qa/release-v0.10.1-{apk,windows,installer,web}.log`、`release-v0.10.1-{source,assets,public}.json` 与 `verify-v0.10.1.ps1`（不随仓库提交）。
- 未执行：Windows 安装版或便携版交互启动与“关于与支持”页核对、Android 真机覆盖升级、Docker 构建与启动、浏览器离线与 CSP 回归、iOS/Android 浏览器 HTTPS 安装。详见 [v0.10.1 公开发布 QA](public-release-qa-v0.10.1-2026-09-29.md)。

## UI 质量

基准视口宽度为 390 逻辑像素；本次原生 Windows 对照使用精确 390 像素客户区宽度和 713 像素可见高度，长页面通过滚动覆盖参考图完整内容。预算与外观页另使用 390×844 widget 截图，分别与 `supplemental-budget-overview.png` 和 `27-appearance.png` 合成同屏比较图。检查六个底部入口、无横向/纵向 RenderFlex 溢出、预算占比口径、实色/斜纹状态、主题拖动预览、交易筛选、账户详情、表单主按钮、信用卡日期、闪电/加号浮动按钮及深色对比度。视觉对照记录见项目根目录 `design-qa.md`，页面映射见 [UI 参考基线](UI_REFERENCE.md)。Flutter widget 截图环境缺少中文字体时会显示方框字形；该限制只影响测试截图文字外观，不影响 Android 系统字体渲染或布局断言。
## Homelab 账号同步验证

- **2026-11-25 架构文档核对。** 运行 `flutter test --no-pub test/cash_transfer_balance_test.dart test/cross_currency_transfer_test.dart test/snapshot_balance_rebuild_test.dart test/ledger_sync_test.dart`，34 项通过。运行 `node --test test/web_bootstrap.test.mjs server/*.test.mjs`，22 项通过。这些测试使用合成数据，覆盖交易差额、投资快照、修订冲突、重试及 Web 启动。实际账户与银行余额的对账见[账户余额规则](DATA_DESIGN.md#账户余额的计算与保存)。
- **Web 22 币种显示与手机预算。** Widget 回归覆盖 TWD 报表、TWD 账本的美元交易与模板、信用卡原币、新账户默认币种、设置换算预览、320 像素预算详情与桌面列。隔离 Chrome 在 390×844 与 1440×940 验证各主要页面的币种和预算响应式布局，并验证 Web 21 等待用户点击「更新」后载入 Web 22。Flutter 全量 285 项通过，2 项按设计跳过。Web 启动及 Node 同步服务 22 项通过。运行 `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings lib test` 检查当前源码及测试，避免旧发布归档进入分析，结果 0 错误。浏览器截图见 [Design QA](../design-qa.md)。
- **Web 21 页内说明与三主题。** 候选 Git 树的 175 个 Dart 文件格式检查通过，静态分析 0 错误。Flutter 全量 277 项通过，默认跳过离线 AI 网关用例与手动截图入口。Web 启动及 Node 同步服务共 22 项通过。Chrome 测试覆盖三主题与 1440×900、390×844、320×844，验证六个页签、问号、Dock 悬停和触控残留、WebGL 与 `?cpu=1` 回退。浏览器截图记录见 [Design QA](../design-qa.md)。另用 Web 17 到 Web 21 的实际 PWA 更新路径确认需用户同意后重载。

- **Web 17 浮动导航。** 18 项 Flutter 定向测试通过，覆盖内容延伸、模糊裁切、底部安全区及页签交互。1440 像素 Chrome 在胶囊旁滚动时可见交易行的像素变化，最后一条记录与设置均可访问。Android 浏览器模拟验证灰阶画面和金额输入可重绘。已验证从 Web 16 更新到 Web 17，发布前检查 SQLite 备份，公网新版与健康接口正常。

- **Web 16 桌面报表与单一主题。** 全量 Flutter 253 项通过，2 项按设计跳过。Chrome 在 1440 与 960 像素检查期间趋势、排行、月末快照和黑白主题。选择全部时间后调整到 390 像素，期间保留。验证老主题设置归一、从 Web 15 点击更新载入 Web 16，以及发布前 SQLite 备份与公网健康接口。

- **Web 15 黑白极简。** 全量 Flutter 测试 255 项通过，2 项按设计跳过。末轮对齐调整后，预算和圆环的 4 项定向测试通过。Chrome 实际从外观选择黑白极简，核对四个灰阶、实时图例金额与占比，并验证重开仍显示该主题及 1440 像素桌面分栏。320 像素组件测试覆盖窄屏无溢出和打开预算编辑器。Web 14 更新提示可加载 Web 15。正式发布完成账本备份检查并回读公网健康接口。

- **Web 14 Android PWA 绘图恢复。** Chrome 以 390×844 Android 触控配置运行两份实际构建。对 Web 13 的可见渲染表面触发 `WEBGL_lose_context` 后，彩色像素从 134,524 降为 0，金额输入仍在改变。Web 14 的 Android 分支使用 CanvasKit 软件绘图。模拟图形中断后，原页面和草稿金额保留，继续输入能更新可见像素。桌面实际 WebGL 表面通过正常恢复检查。Node 启动配置 2 项和定向 Flutter 11 项通过。从 Web 13 点更新成功载入 Web 14。正式发布前验证 SQLite 备份，公网 IPv4 和 IPv6 核对新版静态资源及健康接口。图形中断验证由浏览器注入，Android 模拟器启动未完成，因此本次未覆盖 Android 系统级应用切换。

- **Web 13 旧账本分类导入。** 修复前用 0.10.1 格式数据重现 `通訊費用` 被当成上级 ID 后拒绝导入。修复后，Flutter 全量 253 项通过，2 项按设计跳过。用 Chrome 390 像素触控视口选择备份，核对唯一名称匹配、取消时修订号不变、确认后移除无效上级，以及交易、预算和真实分类 ID 在第二会话回读时仍一致。验证 Web 12 点击更新加载 Web 13。正式部署完成 SQLite 备份检查，仅更新 Web 容器。公网 IPv4 和 IPv6 的 Worker 与健康接口均通过。

- **Web 12 桌面排版与导航。** Flutter 全量 243 项通过，2 项按设计跳过。Chrome 在 1440、960 和 390 像素视口核对六个页面。验证桌面和手机触控模拟均能从总览负债打开账户并显示 Dock，详情返回与跨标签恢复编辑有效。切回记账后仍可读到 12.34 草稿，PWA 更新提示在编辑期间延后。Web 11 点击更新可加载 Web 12。通过独立同步环境确认后台上传不阻塞录入，重载队列幂等恢复，断网保存后重连补传。按 Awwwards 权重的两轮独立复评后，最终候选由 GPT‑6.2 Astra 评 88 分（36/27/16/9），GPT‑6.2 Sol 评 88 分（37/26/15/10）。正式部署完成 SQLite 备份检查，仅更新 Web 容器。公网 IPv4 和 IPv6 验证 Web 12、健康接口和账本匿名访问返回 HTTP 401。

- Web 11：Flutter 全量 242 项通过，2 项按设计跳过。隔离 Chrome 用与示意图相同的测试账本，在 390×844 和 1440×940 视口验证圆环直径 146、环宽 16%、配色、金额、图例和底部胶囊。组件测试覆盖 320 像素宽与系统安全区、缩放保留页签、减少动效、正资产和信用卡溢缴。用两个实际 Web 构建验证从 Web 10 点击“更新”后加载 Web 11。正式部署完成 SQLite 备份完整性校验，仅更新 Web 容器。公网 IPv4 和 IPv6 均返回新版 Worker、健康状态和未登录账本 HTTP 401。

- Web 10：Flutter 全量 237 项通过、2 项按设计跳过。隔离 Chrome 手机视口拦住第一笔上传时，验证两笔本机记账都即时可见且可切换页签。重开后从持久队列恢复，同一操作 ID 重试且两笔各同步一次。浏览器真正断网时第三笔仍可保存，联网后自动上传。另验证账号隔离、并行页签保护、实际冲突保留草稿、字段错误提示及键盘快捷键。正式发布前备份并仅更新 Web 容器。公网 IPv6 中继验证 Web 10 及健康接口通过，同一次 IPv4 中继检查超时。

- 桌面 Web 09：Flutter 全量 226 项通过、2 项按设计跳过。清理重复日期标签后，报表 9 项定向测试通过。Chrome 1440 像素检查双栏登录、左侧导航、总览和报表分栏，以及设置版本信息。缩至 390 像素后仍停留在设置，显示同一个发布号，版本行可打开关于页。公网确认 Web 09 Worker 和正式服务健康。

- Web 更新驗證 08：以 390×844 Chrome 触控运行两份实际构建，旧版仍使用 07 的缓存，新版准备后出现更新提示。点击“更新”后，关于页显示“更新測試 08”，旧应用缓存已切换。正式发布只重启 Web 容器，公网核对 08 Worker 和健康接口。

- PWA 更新提示：16 项 Flutter 回归通过，变更文件静态分析无问题。真实 Chrome 手机视口模拟后续版本，验证首次打开无提示、输入中的登录资料和已打开交易表单不被打断、点“稍后”仍保留旧版本、可从设置重开提示，以及点“更新”后进入新版本。独立双页测试覆盖旧版本迁移、其他标签页不强制刷新及断网重载。公网验证新版 Worker 和 AI 设施总览入口。

- 繁体字形更新：Flutter 全量 222 项通过、2 项按设计跳过，12 项针对性主题与 Web 合同测试通过。390×844 浏览器验证台港语系可加载已固定校验的繁体资源，测试账户名「滙豐觀塘邨 ⾨ 臺灣儲蓄」显示，名称及备注提交和回读保留原 Unicode。正式站点核对资源 HTTP 200、字体清单和新版 Worker。少量罕用扩展汉字超出内嵌字体和当前回退字体覆盖。

- 手机界面更新：Flutter 全量 220 项通过，2 项手动画面测试按设计跳过。390×844 Chrome 真实触控事件验证点金额标题及键盘按钮都可打开键盘，`1134` 回填为 `11.34`。浏览器确认预算的实际、预计标记正常区分；同源加载字体、离线重载和本地账本导入通过。正式发布前完成备份，仅更新 Web 容器。

- 金额键盘更新：Flutter 全量 219 项通过，2 项手动视觉测试按设计跳过。隔离 PWA 在 390×844 视口实测 `1134` 显示并同步保存为 `11.34`，验证包含加减乘除的算式及运算优先级。混合交易、还款、预算和资产金额通过相应组件回归。正式更新前已备份，发布仅更新 Web 容器。

- 界面、推送与性能更新：Flutter 全量 184 项通过、2 项按设计跳过，Node 24 后端 19 项通过。隔离浏览器验证图标、首屏脚本单次加载、设置页刷新与退出、深浅主题切换并持久化，以及后台同步只查询修订号。后端使用模拟推送服务验证本地 09:00 排程、每月 23 日、未来三天、月末钳制、已付款跳过及重试去重。正式库备份通过后上线，公网 API 匿名访问受保护。真实设备通知送达需在设备授权后验收。

- 网页注册更新：Flutter 全量 182 项通过、2 项按设计跳过。Node 24 的 7 组后端测试全部通过，覆盖重复注册、账号容量和限流、会话隔离、旧数据库迁移与失败回滚。Chrome 在隔离环境完成网页注册、自动登录、旧账本回读，并验证不同账号及过期标签页无法改写其他账本。正式库在线备份通过后发布，公网手机视口显示注册表单，非法注册数据被拒绝，未登录读账本返回 401。

- 服务端使用 `node --test server/sync.test.mjs` 验证登录与退出、请求来源检查、不同会话读取同一账本、并发修订冲突、重试幂等性、重启后的持久化及 SQLite 备份完整性。
- 上线前从两个独立浏览器会话导入或读取同一个 0.10.1 测试账本，在一端新增一笔交易并从另一端读取。验证冲突不会覆盖服务器账本、本地模式仍可独立录入，以及 Service Worker 不会缓存 API。
- 2026-11-23：Flutter 全量 180 项通过、2 项按设计跳过；静态分析无错误、67 项既有提示和警告。Homelab 上的 Node 24 容器测试 4 项通过。Docker Web 构建通过 WASM、36 个预缓存项及 102 个字体校验。独立 Chrome 桌面和手机视口已验证登录、导入 0.10.1 格式测试备份，及桌面新增支出后手机视口自动刷新交易和余额。检查了浏览器缓存中没有账本 API 响应。正式实例本机健康检查与初始 SQLite 备份验证成功。
- 断网 Chrome 会话切换离线本地模式，成功导入并打开独立账本，期间没有同步写入。使用 PROXY v2 测试连接验证 Caddy 按代理来源 IP 限流并覆盖请求自带的限流头。
- 正式部署通过专用 Funnel 节点公开 HTTPS，Caddy 仍只监听 Homelab 回环地址。通过公网 DNS 解析并直连公网中继，验证首页和健康检查成功、未登录读取账本返回 HTTP 401。正式账号尚待设置密码。
