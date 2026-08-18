#!/usr/bin/env node
/**
 * wedoc-read — 读取企业微信/腾讯文档分享链接（表格），导出全部工作表为文本。
 *
 * 用法:
 *   node wedoc-read.js <doc-url> [--max-rows N]
 *
 * 认证:
 *   从 ~/.wedoc-cookie 第一行读取浏览器 Cookie（徐斌提供，过期需换新）。
 *   失效时退出码 2 并提示换 Cookie —— agent 应向徐斌索取新 Cookie。
 *
 * 链路: export_office → query_progress 轮询 → COS 下载 xlsx → 解包转文本。
 * 零依赖（Node 18+）。
 */
const fs = require("fs");
const os = require("os");
const path = require("path");
const { execSync } = require("child_process");

const COOKIE_FILE = path.join(os.homedir(), ".wedoc-cookie");

function fail(msg, code = 1) {
  console.error(`ERROR: ${msg}`);
  process.exit(code);
}

function cookie() {
  if (!fs.existsSync(COOKIE_FILE)) {
    fail(`未找到 ${COOKIE_FILE}。需要徐斌从浏览器复制 doc.weixin.qq.com 的 Cookie 写入该文件（单行）。`, 2);
  }
  const line = fs.readFileSync(COOKIE_FILE, "utf8").split("\n").map((s) => s.trim()).find(Boolean);
  if (!line) fail(`${COOKIE_FILE} 为空，需要新的 Cookie。`, 2);
  return line;
}

async function api(url, { method = "GET", form, referer } = {}) {
  const res = await fetch(url, {
    method,
    headers: {
      Cookie: cookie(),
      ...(referer ? { Referer: referer } : {}),
      ...(form ? { "Content-Type": "application/x-www-form-urlencoded" } : {}),
    },
    body: form ? new URLSearchParams(form).toString() : undefined,
  });
  const text = await res.text();
  if (text.includes("登录") && text.includes("<html")) fail("Cookie 已失效（被重定向到登录页），需要徐斌换新。", 2);
  try { return JSON.parse(text); } catch { fail(`接口返回非 JSON（可能是登录态失效）: ${text.slice(0, 120)}`, 2); }
}

const unesc = (s) => s.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, "&");

function dumpXlsx(xlsxPath, maxRows) {
  const zipPath = xlsxPath + ".zip";
  const outDir = xlsxPath + ".unzipped";
  fs.copyFileSync(xlsxPath, zipPath);
  execSync(`powershell -NoProfile -Command "Expand-Archive -Force -LiteralPath '${zipPath}' -DestinationPath '${outDir}'"`, { stdio: "pipe" });

  const read = (p) => (fs.existsSync(p) ? fs.readFileSync(p, "utf8") : "");
  const strings = [];
  for (const m of read(`${outDir}/xl/sharedStrings.xml`).matchAll(/<si>([\s\S]*?)<\/si>/g)) {
    strings.push(unesc([...m[1].matchAll(/<t[^>]*>([\s\S]*?)<\/t>/g)].map((t) => t[1]).join("")));
  }
  const sheets = [];
  for (const m of read(`${outDir}/xl/workbook.xml`).matchAll(/<sheet[^>]*name="([^"]*)"[^>]*r:id="rId(\d+)"/g)) {
    sheets.push({ name: unesc(m[1]), rid: Number(m[2]) });
  }
  const colNum = (ref) => ref.replace(/\d+$/, "").split("").reduce((a, c) => a * 26 + c.charCodeAt(0) - 64, 0);
  const lines = [];
  sheets.forEach((sheet, idx) => {
    const xml = read(`${outDir}/xl/worksheets/sheet${sheet.rid}.xml`) || read(`${outDir}/xl/worksheets/sheet${idx + 1}.xml`);
    if (!xml) return;
    lines.push(`===== ${sheet.name} =====`);
    let rows = 0;
    for (const row of xml.matchAll(/<row[^>]*r="(\d+)"[^>]*>([\s\S]*?)<\/row>/g)) {
      if (maxRows && rows >= maxRows) { lines.push(`…（超过 ${maxRows} 行已截断）`); break; }
      const cells = [];
      for (const c of row[2].matchAll(/<c[^>]*r="([A-Z]+\d+)"[^>]*?(?:\s+t="([^"]*)")?[^>]*>([\s\S]*?)<\/c>/g)) {
        const [, ref, t, body] = c;
        const v = (body.match(/<v>([\s\S]*?)<\/v>/) || body.match(/<t[^>]*>([\s\S]*?)<\/t>/))?.[1] ?? "";
        const val = t === "s" ? strings[Number(v)] ?? "" : t === "inlineStr" ? unesc(v) : v;
        cells.push([colNum(ref), unesc(String(val))]);
      }
      if (cells.length) {
        const line = [];
        let col = 1;
        for (const [n, v] of cells.sort((a, b) => a[0] - b[0])) {
          while (col++ < n) line.push("");
          line.push(v);
        }
        lines.push(line.join(" | "));
        rows++;
      }
    }
  });
  return lines.join("\n");
}

(async () => {
  const url = process.argv[2];
  if (!url) fail("用法: node wedoc-read.js <doc-url> [--max-rows N]");
  const maxRowsArg = process.argv.indexOf("--max-rows");
  const maxRows = maxRowsArg > 0 ? Number(process.argv[maxRowsArg + 1]) : 0;

  const padId = (url.match(/\/(?:sheet|doc|smartsheet)\/([A-Za-z0-9_-]+)/) || [])[1];
  if (!padId) fail(`无法从链接解析文档 id: ${url}`);

  // 1. 发起导出
  const exp = await api("https://doc.weixin.qq.com/v1/export/export_office", {
    method: "POST", form: { docId: padId }, referer: url,
  });
  if (exp.ret !== 0 || !exp.operationId) {
    fail(`导出失败 ret=${exp.ret}（Cookie 失效或没有查看权限）: ${JSON.stringify(exp).slice(0, 200)}`, 2);
  }

  // 2. 轮询进度
  let fileUrl = null;
  for (let i = 0; i < 30; i++) {
    const p = await api(`https://doc.weixin.qq.com/v1/export/query_progress?operationId=${encodeURIComponent(exp.operationId)}`);
    if (p.status === "Done" && p.file_url) { fileUrl = p.file_url; break; }
    await new Promise((r) => setTimeout(r, 2000));
  }
  if (!fileUrl) fail("导出超时（60 秒未完成）。");

  // 3. 下载 + 转文本
  const tmp = path.join(os.tmpdir(), `wedoc-${padId}.xlsx`);
  const buf = Buffer.from(await (await fetch(fileUrl)).arrayBuffer());
  fs.writeFileSync(tmp, buf);
  console.log(dumpXlsx(tmp, maxRows));
  fs.rmSync(tmp, { force: true });
  fs.rmSync(tmp + ".zip", { force: true });
  fs.rmSync(tmp + ".unzipped", { recursive: true, force: true });
})().catch((e) => fail(e.message));
