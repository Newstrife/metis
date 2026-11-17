# Spec: EHS 法规监测——每日采集 → 版本差异 → 公司文件影响分析 → EHS 待核准

> **2026-11-17 集成修订（优先于下文旧方案）**：监测结果不再只写入 `E:\pi\ehs` 或直接推送企微，而是经 `node E:\pi\ehs-monitor\ehs-api.js submit --input <submission.json>` 写入 `E:\EHS` 的“监测核准”暂存区，服务端固定 `PENDING`。授权人员在 EHS 核准/驳回；核准不自动发布法规或修改体系文件。法规差异及修改建议只引用 EHS Linker 法规与标准库，体系文件只引用 EHS Linker 体系文件；下文提到的 `laws-knowledge`、`knowledge`、`E:\enterprise_data\EHS制度` 检索链路均由 `ehs-api.js context` 取代。企微只发送待核准提醒，不再自动推送未核准附件。

## 当前集成接口

1. **上下文**：`node E:\pi\ehs-monitor\ehs-api.js context --output E:\pi\ehs\workspace_tmp\ehs-context.json`，使用具有 `regulations:read`、`documents:read` 的 EHS API Key 分页读取两个正式库。
2. **提交**：submission JSON 包含 `externalId/title/period/summary/overview/regulationAnalyses/documentSuggestions`；修改建议必须携带 EHS `regulationId` 与 `documentId`。先 `--dry-run` 校验再正式提交；metis 使用 `monitoring:write`，无核准或发布权限。
3. **幂等**：组织 + 来源 + `externalId` 唯一；同内容重试返回原记录，不同内容返回 409。
4. **摘要与核准**：EHS「监测摘要」只读展示 submission 的 `summary`（原检测文件摘要）；「监测核准」查看完整解析、法规条款引用、体系文件原文/建议文本/理由/优先级，驳回需填写意见，全程审计。
5. **配置**：`EHS_API_BASE_URL`（默认 `http://127.0.0.1:3000/api/v1`）与 `EHS_API_KEY` 仅放本地环境或 `.env`，不得入库。

实际例程快照：`E:\pi\ehs-monitor\EHS-例程prompt.md`；实际工作流快照：`E:\pi\ehs-monitor\EHS-工作流steps.json`；完整执行约束：`E:\pi\ehs-monitor\EHS-执行版SOP.md`。

---

# 原方案存档（路径与审批规则以上方修订为准）

# Spec: EHS 法规监测——每日采集 → 版本差异 → 公司文件影响分析 → 审批后推送企微

**Repo**: `Newstrife/metis`（Rails 8.1 + pi agent harness，约定见 CLAUDE.md / understanding-metis 技能）；配套本地脚本目录 `E:\pi\ehs-monitor`（新建，仿 `E:\pi\knowledge` 的 Node 脚本形态）。

## Goal

让公司 EHS 管理从"被动等通知"变成"每日自动盯梢"：

1. 每天自动检查官方渠道是否新发布了涉及中国 EHS（安全、环保、职业健康）的法律法规/部门规章/标准题录；
2. 对判定为"修订/替代旧法"的新法规，自动产出新旧版本差异；
3. 将差异逐条与公司现行 EHS 文件（知识库 `EHS制度` 目录）比对，定位公司文件中需要修改的章节；
4. 生成文件修改意见报告（读者为 **EHS 工程师**，技术详细版），**经人审批后**推送到指定的企业微信群。

**报告格式要求**：每条差异给出三段式对照——修改前原文 / 修改后原文 / 修改理由（官方立法说明优先，否则标注"分析推断"）；每条公司文件修改建议给出：现行条款原文 → 建议修改为 → 依据的法规条款+修改理由。征求意见稿阶段的法规列入报告但单独标注（提前准备，不等正式发布）。

全程无人值守的部分必须是确定性的（脚本）；需要判断力的部分交给 agent 步骤；对外推送必须有人工门禁。

## Context & decisions

已确认的架构事实（实现者无需再调研）：

- **定时触发**用 Metis 的 `Routine`（cron，fugit 解析，IANA 时区内嵌）；例程提示词作为普通 turn 执行。
- **多步流程**用 Metis 的 `Workflow`（jsonb steps，`gate: approval` 的步骤停在 `awaiting_approval` 等人审批）。**重要约束**：agent 通过 `metis_start_workflow` 启动的工作流是 **queued 状态，需要人在 Run 面板点"启动"**（`WorkflowRun#launch!`）——这是平台"向外动作必须经人"的既有设计，本期接受：例程发现新法规后排队工作流，操作员早上在面板一键启动，步骤①②自动跑完，步骤③再等审批。人工触点共两次（启动 + 审批），对合规场景是特性不是缺陷。
- **企微推送**优先走**群机器人 webhook**（`WECOM_EHS_WEBHOOK_URL`，HTTPS POST，`{"msgtype":"markdown",...}`，errcode=0 为成功，实测已连通）；本地网桥守护进程 `/notify` 作为回退通道（`WECOM_BRIDGE_TOKEN` + `WECOM_EHS_CHATID`）。两种通道都由 `push.js` 封装，agent 不直接拼请求。
- **法规库**已有：`E:\pi\laws-knowledge\`（159 部法律法规，12,310 条款，SQLite 向量库），自带 `compare-versions.js`（某部法律新旧版本条款增删改对比，逐条输出修改前/后原文对照；`--summary` 只输出数量；`--json` 机器可读）、`search.js`（`--law` `--version` 限定）、`ingest.js`（增量摄取）。**已知限制**：①该库原为通用法律库，EHS 领域法规已专项补采（见 R11）；②compare-versions 用词重叠做相似度，只改个别关键词的修订可能漏检——本期接受，报告措辞用"疑似差异清单"而非"权威对比"。
- **法规文件命名约定**：法规库 `parser.js` 按文件名识别法律名与版本，新法规文本必须存为 `法律全称(版本标注).扩展名`，如 `中华人民共和国安全生产法(2026修正).txt`；版本标注形如 `2026修订` / `2026修正`。命名不合规 → 版本识别为 null → 无法对比。
- **公司文件库**已有：`E:\enterprise_data\`（向量检索 `E:\pi\knowledge\search.js`，支持 `KNOWLEDGE_COLLECTIONS` 目录级过滤）。本期新增子目录 `EHS制度\`，登记为 `DataDirectory` 并授权。
- **法律原文目录**：`E:\knowledge base\Company laws and regulations`。

关键决策（已拍板，不要重开讨论）：

1. **采集层是纯 Node 脚本，不消耗 LLM**。每日只有脚本产出"新增候选项"时才花模型调用费——安静的日子成本 ≈ 0。
2. **监测源用"官网列表页抓取 + 关键词过滤"，不用搜索引擎 API 兜底作为首选**（确定性优先）。单个源解析失败只记日志并在日报中标注，不阻断其他源。已知风险：部分官网列表页可能是 JS 渲染（fetch 拿到空壳），验收时必须逐源冒烟（见 Acceptance）；确认为 JS 渲染的源在 sources.json 标记 `js_rendered: true`，该源当日列入"监测异常"并提示人工查看，不引入无头浏览器。
3. **差异分析按法规类型分支**：法律/行政法规/部门规章（公开全文可得）→ 入库 + compare-versions；国标/标准类 → 只跟踪题录+链接+变更提示，不做条款级对比（本期不建标准全文库）。
4. **推送前必须人工审批**（workflow gate）——EHS 修改意见属专业判断，AI 起草、人签发。
5. 暂不接北大法宝等付费库。

## Requirements

R1. 新建 `E:\pi\ehs-monitor\monitor.js`：每日抓取配置的官方源列表页，提取新发布条目（标题/日期/URL/来源），EHS 关键词过滤，去重（SQLite seen 库），输出当日新增摘要（JSON + Markdown）。
R2. 监测源可配置：`sources.json` 声明每个源的 名称/列表页 URL/条目正则/日期正则/关键词集合/`js_rendered` 标记；新增源只改配置不改代码。
R3. 默认内置源分两级——**国家级**：应急管理部、生态环境部、国家卫健委、市场监管总局（标准委）、中国政府网政策文件库；**地方级**：常州人大法规栏目（rd.changzhou.gov.cn/class/OQQQJQEM，公司所在地常州的地方性法规发布口）、江苏省生态环境厅、江苏省应急管理厅。EHS 关键词默认：安全生产、应急管理、消防、职业病、职业健康、危险化学品、生态环境、排污、环境影响、特种设备等（配置文件可改）。地方源同样走关键词过滤。
R4. 新建 Metis `Workflow`「ehs-法规监测」（团队共享），步骤：①差异分析(auto) ②影响分析(auto) ③修改意见+推送(gate: approval)。绑定 Project「EHS 合规」。
R5. 步骤①（差异分析）按以下明确序列处理每个新增条目：
   a. 判定类型：国标/标准类 → 走题录分支（记录"标准更新提示+链接"，不做条款对比，进入步骤②的输入）；
   b. 法律/法规/规章类 → 用 laws-regulations-search 检索法规库是否已有同名旧版；
   c. 获取全文（monitor 已抓的正文或 agent `web_fetch` 详情页；附件为扫描件/反爬失败 → 标注"全文获取失败"，该条目跳过对比但列入报告，提醒人工跟进）；
   d. 全文按命名约定存为 `法律全称(版本标注).txt` 放入法规目录；
   e. 跑 `node E:/pi/laws-knowledge/ingest.js` 增量摄取（耗时数分钟，等待完成）；
   f. 有旧版 → `node E:/pi/laws-knowledge/compare-versions.js "法律全称"` 产出条款级增删改清单；无旧版（首次入库）→ 标注"新版本已入库，旧版不在库中，无法自动对比"，附全文链接，并提示可将旧版文本放入法规目录重新摄取后重试；
   g. 全新立法（无同名法律）→ 标注"新增立法，无旧版对比"，条款要点从全文摘要提取。
R6. 步骤②（影响分析）：对每条差异/题录变更，用 `KNOWLEDGE_COLLECTIONS=EHS制度 node E:/pi/knowledge/search.js "<差异要点>" 8` 检索公司 EHS 文件。**相关度 <0.6 的结果一律不采信**，该差异列入"暂未发现影响"清单；命中的给出：差异摘要 → 命中公司文件/章节 → 修改建议（含法条出处：法律名+版本+条款号）。
R7. 新建 `E:\pi\ehs-monitor\push.js`：封装企微推送——通道 A（优先）：从 `.env` 读 `WECOM_EHS_WEBHOOK_URL` 直接 POST 群机器人 webhook；通道 B（回退）：读 `WECOM_BRIDGE_TOKEN`/`WECOM_BRIDGE_PORT`/`WECOM_EHS_CHATID` POST 网桥 `/notify`。接收 markdown 文件路径参数；webhook 模式按 ≤1200 字符分段（企微 markdown 限 4096 字节），网桥模式 ≤1800 字符；均在段落边界切分（单段超限无断点时硬切）；任一分片失败则重试一次，仍失败非零退出并打印原因。步骤③（审批+推送）：汇总完整报告存为文件，停在 `awaiting_approval`；审批通过后 agent 运行 `node E:/pi/ehs-monitor/push.js <报告文件>`，推送结果（成功/失败及原因）必须在回复中明确回报。
R8. 新建 Metis `Routine`「EHS 法规日报」（cron 每日 07:30 Asia/Shanghai）：运行 `monitor.js`；无新增 → 一句话结束；有新增 → 以摘要为 input 调用 `metis_start_workflow` 启动「ehs-法规监测」，并在回复中明确说明"工作流已排队，请到 Run 面板启动"。
R9. 公司侧准备：`E:\enterprise_data\EHS制度\` 目录建立（公司 EHS 文件放入并重新摄取），`DataDirectory` 登记 `EHS制度` 并授权给 EHS 相关角色。
R10. 全流程失败兜底：任一源抓取失败、全文获取失败、摄取失败、检索无命中、推送失败，都写入当日报告对应章节，不得静默。
R11. **EHS 法规库专项建设**（一次性）：依据《公司概况（EHS 合规底稿）》的风险点表格，从官方渠道（国家法律法规数据库/中国政府网/部委官网/江苏与常州地方人大政府）采集 30~40 部现行有效 EHS 相关法律法规全文（法律/行政法规/部门规章/江苏省与常州市地方性法规分层），按命名约定入库并增量摄取；此后新修订才有旧版可比，差异能力随之完整。

## Approach

**`E:\pi\ehs-monitor\`（新建，stdlib + node:sqlite，零 npm 依赖，仿 E:\pi\knowledge 结构）**

- `monitor.js` — 入口：`fetch` 各源列表页 → `sources.json` 正则解析条目 → 关键词过滤 → 与 `seen.db`（node:sqlite，表 `seen(url PRIMARY KEY, title, source, published_at, first_seen_at)`）比对 → 新条目写入 seen 库并输出 `digest-{date}.json/.md` 到 `E:\pi\ehs-monitor\out\`；`--fetch-body` 时顺带抓详情页正文（HTML 去标签）存 `out/bodies/` 供步骤①入库使用；stdout 打印 Markdown 摘要。`js_rendered: true` 的源直接记入"监测异常"。
- `push.js` — 见 R7。复用 `dotenv` 式读取（手写解析 `.env`，不引依赖）。
- `sources.json` — 源配置。列表页结构变化时只调正则。
- 测试：每个内置源手工冒烟一次（见 Acceptance），不做 CI。

**Metis 侧（不改 Rails 代码，全部走既有扩展点）**

- `Project`「EHS 合规」、`Workflow`「ehs-法规监测」、`Routine`「EHS 法规日报」均通过 UI 或 metis 管理工具创建；Routine 创建后默认 disabled，人工启用。
- `.env` 新增 `WECOM_EHS_CHATID=wr…`（目标群 chatid）。
- `DataDirectory` 登记 `EHS制度`，授权给 EHS 相关角色；公司 EHS 文件放入后跑 `node E:/pi/knowledge/ingest.js`。

**知识库技能（SKILL.md 微调）**

- `.pi/skills/laws-regulations-search/SKILL.md`：补"新法规文本按 `法律全称(版本标注)` 命名放入法规目录后跑 ingest.js，再用 compare-versions.js 对比；无旧版时会明确提示无法对比"。
- `.pi/skills/knowledge-search/SKILL.md`：目录清单加 `EHS制度/`。

## Interfaces & data

**monitor.js 输出（stdout + out/digest-YYYY-MM-DD.md）**

```markdown
# EHS 法规监测 2026-08-18
## 新增 2 项
1. 【应急管理部】危险化学品企业安全风险隐患排查治理导则（2026-08-17）
   https://www.mem.gov.cn/…/t20260817_xxx.shtml
2. 【市场监管总局】GB/T xxxx-2026 作业场所空气中粉尘测定（2026-08-15）[标准题录]
   https://std.samr.gov.cn/…
## 监测异常
- 国家卫健委：列表页解析失败（结构可能已变更），请人工检查 sources.json
```

无新增时输出：`# EHS 法规监测 {date}：无新增`。

**Workflow「ehs-法规监测」steps（要点，创建时展开为完整提示词）**

1. `差异分析`（auto）— 按 R5 序列处理，输出结构化差异清单（含降级标注）。
2. `影响分析`（auto）— 按 R6 逐条检索，<0.6 不采信，输出修改建议 + "暂未发现影响"清单。
3. `修改意见+推送`（approval）— 汇总报告写文件，审批通过后 `node E:/pi/ehs-monitor/push.js <报告文件>`，回报推送结果。

**Routine「EHS 法规日报」**：trigger schedule；cron `30 7 * * *`；timezone `Asia/Shanghai`；visibility team；提示词见 R8。

**`.env` 新增**：`WECOM_EHS_WEBHOOK_URL=https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=…`（群机器人 webhook，通道 A；用网桥通道 B 时则配 `WECOM_EHS_CHATID=wr…`）

## Edge cases

- **某日无新增** —— 例程一句话结束，不排队工作流、零推送（R8）。
- **工作流排队未被启动** —— 设计如此（人启动）；次日例程若又有新增，独立排队新 run，面板"Needs you"会置顶所有待办，互不覆盖。审批积压同理，属已知行为。
- **源页面结构变更 / JS 渲染** —— 该源记"监测异常"进摘要，其他源不受影响（R2/R10）。
- **源域名解析/连接失败** —— 实测发现：地方政务站点可能被本地网络策略或 WAF 拦截——常州人大站（rd.changzhou.gov.cn）实测返回 WAF JS 挑战页（plain fetch 拿不到真实列表），应按 `js_rendered` 源处理：记入"监测异常"并提示人工查看；根治需调整监测机 DNS/网络策略或人工定期核对，写入部署检查清单。
- **全文获取失败**（反爬/扫描件附件）—— 步骤①标注并跳过对比，报告列出提醒人工跟进（R5c）。
- **首次入库无旧版可对比** —— 降级分支：标注 + 全文链接 + 补救提示（R5f）；该法律下次修订时即可自动对比。
- **短期多次修订** —— seen 库按 URL 去重；同一法律多次修订各自独立成项，始终与库内最新旧版对比。
- **公司 EHS 目录为空/未授权** —— 步骤②明确写"公司 EHS 文件库为空或不可访问"，不编造影响分析。
- **公司文件被 DLP 透明加密** —— 实测发现：公司 EHS 文件（.doc/.docx/部分 .pdf）被企业数据防泄漏软件加密（文件头为非标 `877d1c..`，全文密文），直接读取/摄取得到的是乱码。需 IT 将摄取/检索进程（node.exe 等）加入 DLP 白名单，或经解密审批导出明文副本后放入 `EHS制度\`。部署检查清单必须包含"抽查文件可明文读取"。
- **推送失败**（网桥未运行）—— push.js 非零退出，agent 回报失败；报告保留在 run 中可人工转发（R7）。
- **节假日/凌晨发布** —— 以"首次见到"为准，不按发布日期过滤，避免漏掉深夜挂网条目。
- **报告超长** —— push.js 按 1800 字符分段（企微消息长度限制），段落边界切分，单段无断点时硬切（R7）。

## Out of scope

- 不改任何 Rails 代码（全部走 Routine/Workflow/Skill/env 既有扩展点）；不做新的 Rails 模型；**验收时 `git status` 应确认 Rails 侧零改动**。
- 不接付费法律数据库（北大法宝/威科）；不建标准全文库（国标只题录）。
- 不引入无头浏览器（JS 渲染源标记异常，人工跟进）。
- 不做自动修改公司文件——只产出修改意见，改文件永远是人做的事。
- 不做邮件/钉钉等其他推送渠道；不做英文法规。
- compare-versions 相似度算法优化（漏检只改关键词的修订属已知限制）。

## Acceptance

1. `node E:/pi/ehs-monitor/monitor.js` 手工运行：输出当日摘要；再跑一次输出"无新增"（去重生效）；`out/` 下生成 digest 文件。
2. **逐源冒烟**：对 sources.json 每个内置源，确认至少提取到 1 条历史条目；确认是否为 JS 渲染并正确标记。
3. 临时往 sources.json 加测试关键词制造一次命中，走完整链路：摘要 → 手工执行例程提示词 → 工作流排队 → 面板启动 → 步骤①②自动完成 → 步骤③停在 awaiting_approval → 审批 → 指定群收到分段推送的报告。
4. **端到端核心路径**：拿一部已在库中的 EHS 法律（如《安全生产法》2021修正），手工造一份 `中华人民共和国安全生产法(2026修正).txt`（改动 2-3 个条款）放入法规目录 → 摄取 → compare-versions 输出差异 → 影响分析命中公司 EHS 文件 → 报告含修改建议。验证后删除测试文件并重新摄取。
5. 降级分支验证：对一部库中无旧版的"新法规"（任意新命名文件），步骤①输出"无法自动对比"标注而非报错。
5.1. 地方源验证：sources.json 中常州市/江苏省源至少一个能提取到条目；re.changzhou.gov.cn 若因 DNS 不可达，确认其正确落入"监测异常"而非崩溃。
6. 从 sources.json 删掉一个源的 `item_pattern` 模拟解析失败：摘要出现"监测异常"，其他源正常。
7. 推送验证：审批后目标群收到报告（超长报告正确分段）；停掉网桥守护进程再审批一次，push.js 非零退出且 agent 回报失败。
8. 影响分析阈值验证：故意用一条与公司文件无关的差异跑检索，确认其进入"暂未发现影响"清单而非强行生成建议。
9. `git status` 确认未修改任何 Rails 文件；`E:\pi\ehs-monitor` 无 node_modules（零依赖）。
