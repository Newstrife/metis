// 企业微信智能机器人 ↔ Metis 桥接 daemon。
//
// 入站：企微消息 --WSS--> 本进程 --HTTP POST--> Metis /api/wecom/messages
// 出站：轮询 Metis 直到 assistant 消息落定 --WSS replyStream--> 企微
// 推送：POST 本机 /notify（Routine/agent 用）--> sendMessage 主动发企微
//
// 环境变量（见 .env）：
//   WECOM_BOT_ID / WECOM_BOT_SECRET  智能机器人凭证（企微管理后台）
//   WECOM_BRIDGE_TOKEN               与 Metis 共享的 bearer token
//   METIS_URL                        默认 http://127.0.0.1:3002
//   WECOM_BRIDGE_PORT                /notify 监听端口，默认 3201（仅回环）

const http = require("node:http");
const AiBot = require("@wecom/aibot-node-sdk");
const { generateReqId } = AiBot;

const METIS_URL = process.env.METIS_URL || "http://127.0.0.1:3002";
const TOKEN = process.env.WECOM_BRIDGE_TOKEN;
const PORT = Number(process.env.WECOM_BRIDGE_PORT || 3201);
const POLL_INTERVAL_MS = 3000;
const POLL_TIMEOUT_MS = 5 * 60 * 1000;
// 企微 markdown 单条上限约 4KB，留余量截断
const MAX_REPLY_CHARS = 3800;

if (!process.env.WECOM_BOT_ID || !process.env.WECOM_BOT_SECRET || !TOKEN) {
  console.error("缺少 WECOM_BOT_ID / WECOM_BOT_SECRET / WECOM_BRIDGE_TOKEN，请检查 .env");
  process.exit(1);
}

const client = new AiBot.WSClient({
  botId: process.env.WECOM_BOT_ID,
  secret: process.env.WECOM_BOT_SECRET,
});

// ---- 工具 ---------------------------------------------------------------

// 不同版本 SDK 的帧结构略有差异，防御性取值
const body = (frame) => frame.body || frame;
const msgidOf = (frame) => body(frame).msgid || (frame.head && frame.head.req_id) || JSON.stringify(body(frame)).slice(0, 64);
const senderOf = (frame) => {
  const b = body(frame);
  return (b.from && (b.from.userid || b.from.id)) || b.from_userid || b.userid || "unknown";
};
const chatidOf = (frame) => {
  const b = body(frame);
  return b.chatid || b.chat_id || (b.conversation && b.conversation.id) || null;
};

const seen = new Set();
function dedupe(id) {
  if (seen.has(id)) return true;
  seen.add(id);
  if (seen.size > 5000) seen.delete(seen.values().next().value);
  return false;
}

// 每个发送者最近的 chatid，供 /notify 主动推送寻址
const lastChatByUser = new Map();

async function metisPost(pathname, payload) {
  const res = await fetch(`${METIS_URL}${pathname}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    const err = new Error(`Metis POST ${pathname} -> ${res.status}`);
    err.status = res.status;
    throw err;
  }
  return res.json();
}

async function metisGet(pathname) {
  const res = await fetch(`${METIS_URL}${pathname}`, {
    headers: { Authorization: `Bearer ${TOKEN}` },
  });
  if (!res.ok) throw new Error(`Metis GET ${pathname} -> ${res.status}`);
  return res.json();
}

async function pollReply(messageId) {
  const deadline = Date.now() + POLL_TIMEOUT_MS;
  while (Date.now() < deadline) {
    const { status, content } = await metisGet(`/api/wecom/messages/${messageId}`);
    if (status === "done" && content) return { ok: true, content };
    if (status === "errored" || status === "canceled") return { ok: false, status };
    await new Promise((r) => setTimeout(r, POLL_INTERVAL_MS));
  }
  return { ok: false, status: "timeout" };
}

function truncate(text) {
  if (text.length <= MAX_REPLY_CHARS) return text;
  return `${text.slice(0, MAX_REPLY_CHARS)}\n\n…（回复过长已截断，完整内容请到小百同学查看）`;
}

// ---- 入站消息 ------------------------------------------------------------

client.on("message.text", async (frame) => {
  const id = msgidOf(frame);
  if (dedupe(id)) return;

  const from = senderOf(frame);
  const chatid = chatidOf(frame);
  if (chatid) lastChatByUser.set(from, chatid);

  const content = (body(frame).text && body(frame).text.content || "").trim();
  if (!content) return;
  console.log(`[msg] ${from}: ${content.slice(0, 60)}`);

  const streamId = generateReqId("stream");
  try {
    await client.replyStream(frame, streamId, "正在思考…", false);
    const { message_id } = await metisPost("/api/wecom/messages", { from_userid: from, content, chatid });
    const reply = await pollReply(message_id);
    const text = reply.ok
      ? truncate(reply.content)
      : `这次处理没有成功（${reply.status}），请打开小百同学查看详情，或换个说法再试一次。`;
    await client.replyStream(frame, streamId, text, true);
  } catch (err) {
    console.error("[msg] 处理失败:", err.message);
    const note = err.status === 409
      ? "上一条消息还在处理中，等它回复完再发下一条哦。"
      : "小百同学暂时不可用，请稍后再试。";
    try {
      await client.replyStream(frame, streamId, note, true);
    } catch { /* 连接已断，等重连 */ }
  }
});

client.on("event.enter_chat", (frame) => {
  client.replyWelcome(frame, {
    msgtype: "text",
    text: { content: "你好，我是小百同学。直接说事就行——查设备、问文档、跑分析都可以。" },
  }).catch((e) => console.error("[welcome]", e.message));
});

client.on("authenticated", () => console.log("🔐 企微 WebSocket 已认证"));
client.on("disconnected", () => console.log("⚠️ 连接断开，等待自动重连…"));
client.on("error", (e) => console.error("[ws]", e && e.message ? e.message : e));

// ---- 主动推送出口（Routine / agent 用） -----------------------------------
// POST http://127.0.0.1:3201/notify  { "to_userid": "...", "content": "..." }
// 寻址依赖该用户先给机器人发过消息（chatid 缓存在内存里）。

const server = http.createServer((req, res) => {
  if (req.method !== "POST" || req.url !== "/notify") {
    res.writeHead(404).end();
    return;
  }
  if (req.headers.authorization !== `Bearer ${TOKEN}`) {
    res.writeHead(401).end();
    return;
  }
  let raw = "";
  req.on("data", (c) => { raw += c; });
  req.on("end", async () => {
    try {
      const { to_userid, content } = JSON.parse(raw);
      const chatid = lastChatByUser.get(to_userid);
      if (!chatid) throw new Error(`没有 ${to_userid} 的会话记录（对方需先给机器人发过消息）`);
      await client.sendMessage(chatid, { msgtype: "markdown", markdown: { content: truncate(String(content)) } });
      res.writeHead(200, { "Content-Type": "application/json" }).end(JSON.stringify({ ok: true }));
    } catch (err) {
      res.writeHead(422, { "Content-Type": "application/json" }).end(JSON.stringify({ ok: false, error: err.message }));
    }
  });
});

server.listen(PORT, "127.0.0.1", () => console.log(`📮 /notify 监听 127.0.0.1:${PORT}`));

process.on("SIGINT", () => {
  client.disconnect();
  server.close();
  process.exit(0);
});

client.connect();
console.log("🚀 wecom-bridge 启动，连接企业微信…");
