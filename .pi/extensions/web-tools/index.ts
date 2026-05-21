/**
 * Web Tools Extension
 *
 * Adds two tools analogous to Claude Code's web capabilities:
 *
 *   web_fetch  — fetch a URL and return readable text (strips HTML)
 *   web_search — search the web via Brave Search API or Serper.dev
 *
 * Configuration (environment variables):
 *   BRAVE_SEARCH_API_KEY  — Brave Search API key (https://api.search.brave.com)
 *   SERPER_API_KEY        — Serper.dev API key (https://serper.dev)
 *                           Brave is preferred when both are set.
 *
 * Placement:
 *   Project-local: .pi/extensions/web-tools/index.ts   ← this file
 *   Global:        ~/.pi/agent/extensions/web-tools/index.ts
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

// ---------------------------------------------------------------------------
// HTML → plain text (no external deps needed)
// ---------------------------------------------------------------------------
function htmlToText(html: string): string {
  return html
    // Remove <script> and <style> blocks entirely
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    // Replace block elements with newlines
    .replace(/<\/(p|div|li|h[1-6]|tr|blockquote|pre|section|article)>/gi, "\n")
    .replace(/<br\s*\/?>/gi, "\n")
    // Strip remaining tags
    .replace(/<[^>]+>/g, "")
    // Decode common HTML entities
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, " ")
    .replace(/&mdash;/g, "—")
    .replace(/&ndash;/g, "–")
    // Collapse whitespace while preserving paragraph breaks
    .replace(/[ \t]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

// ---------------------------------------------------------------------------
// Truncate to a character limit with a visible marker
// ---------------------------------------------------------------------------
function truncate(text: string, maxChars: number): string {
  if (text.length <= maxChars) return text;
  return text.slice(0, maxChars) + `\n\n[… truncated at ${maxChars} chars]`;
}

// ---------------------------------------------------------------------------
// Search providers
// ---------------------------------------------------------------------------

interface SearchResult {
  title: string;
  url: string;
  snippet: string;
}

async function braveSearch(
  query: string,
  count: number,
  signal: AbortSignal,
): Promise<SearchResult[]> {
  const apiKey = process.env.BRAVE_SEARCH_API_KEY;
  if (!apiKey) throw new Error("BRAVE_SEARCH_API_KEY is not set");

  const url = new URL("https://api.search.brave.com/res/v1/web/search");
  url.searchParams.set("q", query);
  url.searchParams.set("count", String(count));

  const res = await fetch(url.toString(), {
    headers: {
      Accept: "application/json",
      "Accept-Encoding": "gzip",
      "X-Subscription-Token": apiKey,
    },
    signal,
  });

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`Brave Search API error ${res.status}: ${body}`);
  }

  const data = (await res.json()) as {
    web?: { results?: Array<{ title: string; url: string; description?: string }> };
  };

  return (data.web?.results ?? []).map((r) => ({
    title: r.title ?? "",
    url: r.url ?? "",
    snippet: r.description ?? "",
  }));
}

async function serperSearch(
  query: string,
  count: number,
  signal: AbortSignal,
): Promise<SearchResult[]> {
  const apiKey = process.env.SERPER_API_KEY;
  if (!apiKey) throw new Error("SERPER_API_KEY is not set");

  const res = await fetch("https://google.serper.dev/search", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-API-KEY": apiKey,
    },
    body: JSON.stringify({ q: query, num: count }),
    signal,
  });

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`Serper API error ${res.status}: ${body}`);
  }

  const data = (await res.json()) as {
    organic?: Array<{ title: string; link: string; snippet?: string }>;
  };

  return (data.organic ?? []).map((r) => ({
    title: r.title ?? "",
    url: r.link ?? "",
    snippet: r.snippet ?? "",
  }));
}

// ---------------------------------------------------------------------------
// Extension entry point
// ---------------------------------------------------------------------------
export default function webToolsExtension(pi: ExtensionAPI) {

  // ─── web_fetch ────────────────────────────────────────────────────────────
  pi.registerTool({
    name: "web_fetch",
    label: "Web Fetch",
    description:
      "Fetch the content of a URL and return it as readable plain text. " +
      "Strips HTML tags. Useful for reading documentation, articles, or any public web page.",
    promptSnippet: "Fetch and read a web page by URL",
    promptGuidelines: [
      "Use web_fetch to read a web page when given a URL or when you need up-to-date online content.",
    ],
    parameters: Type.Object({
      url: Type.String({
        description: "The URL to fetch (must start with http:// or https://)",
      }),
      max_chars: Type.Optional(
        Type.Number({
          description:
            "Maximum characters to return (default 20000). " +
            "Increase for long documents.",
        }),
      ),
    }),

    async execute(_toolCallId, params, signal, onUpdate) {
      const { url, max_chars = 20_000 } = params;

      if (!/^https?:\/\//i.test(url)) {
        return {
          content: [{ type: "text", text: `Error: URL must start with http:// or https://` }],
          isError: true,
          details: {},
        };
      }

      onUpdate?.({ content: [{ type: "text", text: `Fetching ${url} …` }] });

      let res: Response;
      try {
        res = await fetch(url, {
          headers: {
            "User-Agent":
              "Mozilla/5.0 (compatible; pi-web-tools/1.0; +https://github.com/earendil-works/pi)",
            Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,text/plain;q=0.8,*/*;q=0.7",
          },
          signal,
          redirect: "follow",
        });
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : String(err);
        return {
          content: [{ type: "text", text: `Fetch error: ${msg}` }],
          isError: true,
          details: {},
        };
      }

      if (!res.ok) {
        return {
          content: [{ type: "text", text: `HTTP ${res.status} ${res.statusText} — ${url}` }],
          isError: true,
          details: { status: res.status },
        };
      }

      const contentType = res.headers.get("content-type") ?? "";
      const raw = await res.text();

      let text: string;
      if (contentType.includes("text/html") || raw.trimStart().startsWith("<")) {
        text = htmlToText(raw);
      } else {
        text = raw; // JSON, plain text, markdown, etc.
      }

      const output = truncate(text, max_chars);
      const details = {
        url,
        status: res.status,
        content_type: contentType,
        chars_returned: output.length,
      };

      return {
        content: [{ type: "text", text: output }],
        details,
      };
    },
  });

  // ─── web_search ───────────────────────────────────────────────────────────
  pi.registerTool({
    name: "web_search",
    label: "Web Search",
    description:
      "Search the web and return the top results (title, URL, snippet). " +
      "Requires BRAVE_SEARCH_API_KEY or SERPER_API_KEY to be set. " +
      "Brave is used when both keys are present.",
    promptSnippet: "Search the web for current information",
    promptGuidelines: [
      "Use web_search when the user asks about recent events, news, or anything that may have changed after your training cutoff.",
      "Prefer web_search over web_fetch when you need to discover relevant URLs first.",
    ],
    parameters: Type.Object({
      query: Type.String({
        description: "The search query",
      }),
      count: Type.Optional(
        Type.Number({
          description: "Number of results to return (default 5, max 10)",
        }),
      ),
    }),

    async execute(_toolCallId, params, signal, onUpdate) {
      const { query, count = 5 } = params;
      const n = Math.min(count, 10);

      const hasBrave = Boolean(process.env.BRAVE_SEARCH_API_KEY);
      const hasSerper = Boolean(process.env.SERPER_API_KEY);

      if (!hasBrave && !hasSerper) {
        return {
          content: [
            {
              type: "text",
              text:
                "web_search is not configured. Set BRAVE_SEARCH_API_KEY " +
                "(https://api.search.brave.com) or SERPER_API_KEY (https://serper.dev) " +
                "in your environment.",
            },
          ],
          isError: true,
          details: {},
        };
      }

      onUpdate?.({ content: [{ type: "text", text: `Searching: ${query} …` }] });

      let results: SearchResult[];
      let provider: string;

      try {
        if (hasBrave) {
          results = await braveSearch(query, n, signal);
          provider = "Brave Search";
        } else {
          results = await serperSearch(query, n, signal);
          provider = "Serper (Google)";
        }
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : String(err);
        return {
          content: [{ type: "text", text: `Search error: ${msg}` }],
          isError: true,
          details: {},
        };
      }

      if (results.length === 0) {
        return {
          content: [{ type: "text", text: `No results found for: ${query}` }],
          details: { query, provider, count: 0 },
        };
      }

      const lines = results.map(
        (r, i) =>
          `[${i + 1}] ${r.title}\n    ${r.url}\n    ${r.snippet}`,
      );

      const text = `Search results for "${query}" (via ${provider}):\n\n` + lines.join("\n\n");

      return {
        content: [{ type: "text", text }],
        details: { query, provider, count: results.length, results },
      };
    },
  });
}
