# wecom-bridge — 企业微信智能机器人 ↔ Metis 桥接

把企微里的对话接入 Metis：员工在企业微信里直接和机器人聊天，消息经
WebSocket 长连接进入本进程，POST 给 Metis 开一轮正常会话（完整走 pi +
Kimi + 连接器 + skills），回复再经 WebSocket 推回企微。

不需要公网 IP / 域名 / 回调配置——WebSocket 是出站长连接。

## 一次性配置

1. 企业微信管理后台创建**智能机器人**，记录 Bot ID 和 Secret
   （管理后台 → 管理工具 → 智能机器人 → 创建 → API 模式）
2. 把凭证填入项目根目录 `.env`：
   ```
   WECOM_BOT_ID=...
   WECOM_BOT_SECRET=...
   ```
   `WECOM_BRIDGE_TOKEN` 已在配置时随机生成，daemon 和 Metis 都从 .env 读。
3. 安装依赖：`cd clients/wecom-bridge && npm install`

## 运行

```bash
node index.js        # 或 npm start
```

`start-dev.ps1` 会在 `WECOM_BOT_ID` 已配置且依赖已安装时自动拉起本进程。

## 行为

- 每个企微发送者对应 Metis 里一个长会话（上下文连续）
- v1 所有发送者映射到单一 Metis 账号（`.env` 的 `WECOM_BRIDGE_USER_EMAIL`）
- 仅文本消息；回复超过 ~4KB 自动截断并提示去 Metis 看全文
- 主动推送：`POST http://127.0.0.1:3201/notify`
  `{ "to_userid": "...", "content": "..." }`（Bearer 同 token；对方需先
  给机器人发过消息以建立寻址缓存）——Routine 定时提醒走这里
