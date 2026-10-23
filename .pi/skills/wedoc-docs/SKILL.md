---
name: wedoc-docs
description: 读取企业微信文档分享链接（doc.weixin.qq.com）。当对话中出现企业微信文档/表格/智能表格/智能文档链接并被要求读取、查看、分析、总结内容时使用。优先走 wecom_doc MCP（能读能写），MCP 不可用才退回本地导出脚本（只读、仅表格）。
---

# 读取企业微信文档

## 首选：`wecom_doc` MCP 服务

每轮的 `.mcp.json` 里如果挂着 `wecom_doc` server，就**优先用它**——免 Cookie、支持文档/表格/智能表格/智能文档，还能按要求新建和续写文档。

用 `mcp({ search: "文档" })` 或 `mcp({ search: "doc" })` 找工具，按链接类型选：

| 链接里的内容 | 读取工具 |
|---|---|
| 文字文档 /doc/ | `doc_contents_get` |
| 表格 /sheet/ | `sheet_ranges_get`、`sheet_cells_get`、`sheet_workbook_info` |
| 智能表格 | `smartsheet_records_list`、`smartsheet_records_query` |
| 智能文档 | `smartpage_pages_get` |
| 演示 PPT | `slide_get`、`slide_pages_get` |
| 只知道关键词/没给链接 | `doc_search` |

工具大多同时接受 docid 或完整 URL，直接把用户给的链接传进去即可。

读取大表格先读 `sheet_workbook_info` / 元信息看结构，再按需拉范围，别一次拉全表。

**写操作**（新建/追加/覆盖、加成员、改样式等）是授权人身份的正式变更，动手前跟用户确认目标和内容；删除、覆盖、清理类工具本身也会要求显式确认参数，如实照做。

## 兜底：本地导出脚本（仅表格、只读）

只有 `wecom_doc` 不可用（mcp 搜索里没有这个 server）或文档对授权人不可见时，才退回脚本：

```bash
node .pi/skills/wedoc-docs/wedoc-read.js <文档链接>
```

输出为纯文本：每个工作表一段（`===== 表名 =====`），行内单元格以 ` | ` 分隔。
表格很大时加 `--max-rows 100` 截断，先看结构再决定要不要全量。

### 认证（仅兜底路径需要）

- 脚本从 `~/.wedoc-cookie`（单行）读取浏览器 Cookie 访问文档，权限等同于徐斌本人。
- **退出码 2 = Cookie 失效**。此时不要再重试，直接告诉用户："企微文档的 Cookie 过期了，请在浏览器打开 doc.weixin.qq.com，F12 → Network → 任意请求的 `cookie:` 整行复制给我"，拿到后写入 `~/.wedoc-cookie` 再跑。
- 没有查看权限的文档会报"导出失败 ret≠0"，如实转述并建议用户在文档里给链接开"任何人可查看"权限。

## 边界

- 兜底脚本**只读**：要产出文件，写到工作区本地（xlsx/csv/md）即可；写回在线文档用 `wecom_doc`。
- 兜底脚本目前只验证过**表格**；文字文档链接会报导出失败——遇到这类链接务必确认 `wecom_doc` 真的不在，再告诉用户读不了。
- Cookie 是敏感凭据：不要把它的内容打印到回复里，也不要写进任何产出文件。
