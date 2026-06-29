#!/usr/bin/env node
// Import Notion pages into a Personal_LLM_Wiki vault's raw/ folder (markdown + images),
// so opencode can ingest them into wiki/. One command, no Xcode.
//
//   node tools/notion-import.mjs --vault ~/Projects/Personal_LLM_Wiki
//   node tools/notion-import.mjs --all                 # import every accessible page
//   node tools/notion-import.mjs --page <page-id>      # one page
//   node tools/notion-import.mjs --list                # just list accessible pages
//
// Token resolution (first hit wins): --token <t>  →  $NOTION_TOKEN  →  the token you
// already saved in the AppleNotestoX app (macOS Keychain)  →  interactive prompt.
//
// NOTE: built from stable Notion API knowledge (v2022-06-28), NOT live-fact-checked.
// The pure markdown conversion is unit-tested; verify the live fetch on first run.

import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import readline from "node:readline";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const NOTION_VERSION = "2022-06-28";
const API = "https://api.notion.com/v1";
const IMAGE_EXTS = ["png", "jpg", "jpeg", "gif", "webp", "svg", "heic"];

// ---------------- pure helpers (exported for tests) ----------------

export function slug(s) {
  return String(s).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "page";
}
export function isoDay(d) {
  const f = new Intl.DateTimeFormat("en-CA", { timeZone: "UTC", year: "numeric", month: "2-digit", day: "2-digit" });
  return f.format(d);
}
export function richTextToMd(arr) {
  return (arr || []).map((t) => {
    let s = t.plain_text != null ? t.plain_text : (t.text && t.text.content) || "";
    if (!s) return "";
    const a = t.annotations || {};
    if (a.code) s = "`" + s + "`";
    if (a.bold) s = "**" + s + "**";
    if (a.italic) s = "*" + s + "*";
    if (a.strikethrough) s = "~~" + s + "~~";
    const href = t.href || (t.text && t.text.link && t.text.link.url);
    if (href) s = "[" + s + "](" + href + ")";
    return s;
  }).join("");
}

// Convert a (recursive) Notion block tree to markdown.
// `imageName(block)` returns the inline markdown for an image block, or null to skip.
export function notionToMarkdown(blocks, imageName) {
  imageName = imageName || (() => null);
  const chunks = collectChunks(blocks, 0, imageName);
  let md = "";
  for (let i = 0; i < chunks.length; i++) {
    if (i > 0) md += chunks[i - 1].list && chunks[i].list ? "\n" : "\n\n";
    md += chunks[i].text;
  }
  return md.replace(/\n{3,}/g, "\n\n").trim() + "\n";
}

function collectChunks(blocks, depth, imageName) {
  const out = [];
  const pad = "  ".repeat(depth);
  for (const b of blocks || []) {
    const t = b.type;
    const data = b[t] || {};
    const rt = data.rich_text ? richTextToMd(data.rich_text) : "";
    switch (t) {
      case "paragraph": if (rt) out.push({ text: rt, list: false }); break;
      case "heading_1": out.push({ text: "# " + rt, list: false }); break;
      case "heading_2": out.push({ text: "## " + rt, list: false }); break;
      case "heading_3": out.push({ text: "### " + rt, list: false }); break;
      case "bulleted_list_item": out.push({ text: pad + "- " + rt, list: true }); break;
      case "numbered_list_item": out.push({ text: pad + "1. " + rt, list: true }); break;
      case "to_do": out.push({ text: pad + (data.checked ? "- [x] " : "- [ ] ") + rt, list: true }); break;
      case "quote": out.push({ text: "> " + rt, list: false }); break;
      case "callout": {
        const icon = data.icon && data.icon.emoji ? data.icon.emoji + " " : "";
        out.push({ text: "> " + icon + rt, list: false }); break;
      }
      case "toggle": out.push({ text: "**" + rt + "**", list: false }); break;
      case "code": out.push({ text: "```" + (data.language || "") + "\n" + (data.rich_text ? data.rich_text.map((x) => x.plain_text || "").join("") : "") + "\n```", list: false }); break;
      case "divider": out.push({ text: "---", list: false }); break;
      case "bookmark": case "embed": case "link_preview":
        if (data.url) out.push({ text: "[" + data.url + "](" + data.url + ")", list: false }); break;
      case "image": {
        const snippet = imageName(b);
        const cap = data.caption ? richTextToMd(data.caption) : "";
        out.push({ text: (snippet || "_(image)_") + (cap ? "\n" + cap : ""), list: false });
        break;
      }
      case "table": break; // rows come as children below
      case "table_row": {
        const cells = (data.cells || []).map((c) => richTextToMd(c).replace(/\|/g, "\\|"));
        if (cells.length) out.push({ text: "| " + cells.join(" | ") + " |", list: false });
        break;
      }
      default: if (rt) out.push({ text: rt, list: false }); break;
    }
    if (b.children && b.children.length) {
      const childDepth = (t === "bulleted_list_item" || t === "numbered_list_item" || t === "to_do" || t === "toggle") ? depth + 1 : depth;
      out.push(...collectChunks(b.children, childDepth, imageName));
    }
  }
  return out;
}

export function frontmatter({ pageId, title, imported }) {
  return [
    "---",
    "origin: notion",
    "source_type: note",
    "source_app: notion",
    "notion_page_id: " + pageId,
    "title: " + title,
    "imported: " + isoDay(imported),
    "---",
    "> Provenance: imported from Notion via tools/notion-import.mjs.",
    "> Synthesize into wiki/, don't edit here.",
    "",
    "",
  ].join("\n");
}

function imageExt(url) {
  const clean = (url.split("?")[0] || "").toLowerCase();
  const m = clean.match(/\.([a-z0-9]+)$/);
  return m && IMAGE_EXTS.includes(m[1]) ? m[1] : "png";
}

// ---------------- Notion API client (runtime; not fact-checked) ----------------

function makeClient(token) {
  const headers = { Authorization: "Bearer " + token, "Notion-Version": NOTION_VERSION, "Content-Type": "application/json" };
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  async function call(method, route, body) {
    const res = await fetch(API + route, { method, headers, body: body ? JSON.stringify(body) : undefined });
    if (!res.ok) throw new Error("Notion API " + res.status + " on " + route + ": " + (await res.text()).slice(0, 300));
    await sleep(350); // stay well under ~3 req/s
    return res.json();
  }
  return {
    async searchPages() {
      const pages = []; let cursor;
      do {
        const r = await call("POST", "/search", { filter: { property: "object", value: "page" }, page_size: 100, start_cursor: cursor });
        pages.push(...r.results);
        cursor = r.has_more ? r.next_cursor : null;
      } while (cursor);
      return pages;
    },
    async children(blockId) {
      const all = []; let cursor;
      do {
        const r = await call("GET", "/blocks/" + blockId + "/children?page_size=100" + (cursor ? "&start_cursor=" + cursor : ""));
        for (const b of r.results) {
          if (b.has_children) b.children = await this.children(b.id);
          all.push(b);
        }
        cursor = r.has_more ? r.next_cursor : null;
      } while (cursor);
      return all;
    },
    download: async (url) => Buffer.from(await (await fetch(url)).arrayBuffer()),
  };
}

export function pageTitle(page) {
  const props = page.properties || {};
  for (const k of Object.keys(props)) {
    const p = props[k];
    if (p && p.type === "title" && Array.isArray(p.title)) {
      const s = p.title.map((x) => x.plain_text || "").join("").trim();
      if (s) return s;
    }
  }
  return "Untitled";
}

// collect image blocks (depth-first) so we can download + map id -> filename
function collectImages(blocks, acc = []) {
  for (const b of blocks || []) {
    if (b.type === "image") {
      const d = b.image || {};
      const url = d.type === "external" ? (d.external && d.external.url) : (d.file && d.file.url);
      if (url) acc.push({ id: b.id, url, external: d.type === "external" });
    }
    if (b.children) collectImages(b.children, acc);
  }
  return acc;
}

// ---------------- token + args ----------------

function expandHome(p) { return p && p.startsWith("~") ? path.join(os.homedir(), p.slice(1)) : p; }

function resolveToken(flagToken) {
  if (flagToken) return flagToken;
  if (process.env.NOTION_TOKEN) return process.env.NOTION_TOKEN;
  try {
    const t = execFileSync("security", ["find-generic-password", "-s", "com.applenotestox.app", "-a", "notion_token", "-w"], { stdio: ["ignore", "pipe", "ignore"] }).toString().trim();
    if (t) { console.log("  (using the Notion token from your AppleNotestoX app keychain)"); return t; }
  } catch (e) { /* not found */ }
  return null;
}

function parseArgs(argv) {
  const o = {};
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--vault") o.vault = argv[++i];
    else if (a === "--token") o.token = argv[++i];
    else if (a === "--page") o.page = argv[++i];
    else if (a === "--all") o.all = true;
    else if (a === "--list") o.list = true;
    else if (a === "--subdir") o.subdir = argv[++i];
    else if (a === "--help" || a === "-h") o.help = true;
  }
  return o;
}

function ask(q) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    rl.question(q, (ans) => { rl.close(); resolve(ans.trim()); });
  });
}

// ---------------- import one page ----------------

async function importPage(client, page, opts) {
  const title = pageTitle(page);
  const s = slug(title);
  const journalDir = path.join(opts.vault, opts.subdir || "raw/journal");
  const assetsDir = path.join(opts.vault, "raw/assets");
  fs.mkdirSync(journalDir, { recursive: true });
  fs.mkdirSync(assetsDir, { recursive: true });

  const blocks = await client.children(page.id);

  // download images, build id -> inline markdown
  const images = collectImages(blocks);
  const inlineById = {};
  let idx = 0;
  for (const img of images) {
    idx++;
    try {
      const buf = await client.download(img.url);
      const name = `${s}-${String(idx).padStart(2, "0")}.${imageExt(img.url)}`;
      fs.writeFileSync(path.join(assetsDir, name), buf);
      inlineById[img.id] = `![[${name}]]`;
    } catch (e) {
      inlineById[img.id] = `_(image failed to download)_`;
    }
  }

  const body = frontmatter({ pageId: page.id, title, imported: new Date() })
    + notionToMarkdown(blocks, (b) => inlineById[b.id] || null);

  // collision-safe filename
  const existing = new Set(fs.existsSync(journalDir) ? fs.readdirSync(journalDir) : []);
  let name = `${isoDay(new Date())}-${s}.md`;
  if (existing.has(name)) { let n = 2; while (existing.has(`${isoDay(new Date())}-${s}-${n}.md`)) n++; name = `${isoDay(new Date())}-${s}-${n}.md`; }
  const outPath = path.join(journalDir, name);
  fs.writeFileSync(outPath, body);
  return { title, outPath, images: images.length };
}

// ---------------- main ----------------

async function main() {
  const opts = parseArgs(process.argv);
  if (opts.help) {
    console.log("usage: node tools/notion-import.mjs --vault <path> [--all | --page <id> | --list] [--token <t>] [--subdir raw/journal]");
    return;
  }
  opts.vault = expandHome(opts.vault) || path.join(os.homedir(), "Projects", "Personal_LLM_Wiki");
  if (!fs.existsSync(opts.vault)) { console.error("error: vault not found: " + opts.vault); process.exit(1); }

  const token = resolveToken(opts.token);
  if (!token) {
    console.error("No Notion token. Pass --token, set NOTION_TOKEN, or save one in the AppleNotestoX app.\n" +
      "Create one at https://www.notion.so/my-integrations and share your pages with it (page → ••• → Connections).");
    process.exit(1);
  }
  const client = makeClient(token);

  console.log("Fetching pages your integration can access…");
  const pages = await client.searchPages();
  if (!pages.length) {
    console.error("No pages found. In Notion, open a page → ••• → Connections → add your integration, then retry.");
    process.exit(1);
  }
  const titled = pages.map((p) => ({ page: p, title: pageTitle(p) }));

  if (opts.list) { titled.forEach((t, i) => console.log(`  [${i + 1}] ${t.title}  (${t.page.id})`)); return; }

  let chosen;
  if (opts.page) chosen = titled.filter((t) => t.page.id === opts.page || t.page.id.replace(/-/g, "") === opts.page.replace(/-/g, ""));
  else if (opts.all) chosen = titled;
  else {
    titled.forEach((t, i) => console.log(`  [${i + 1}] ${t.title}`));
    const ans = await ask("\nWhich to import? (e.g. 1,3  or  'all'): ");
    if (ans.toLowerCase() === "all") chosen = titled;
    else chosen = ans.split(",").map((x) => titled[parseInt(x.trim(), 10) - 1]).filter(Boolean);
  }
  if (!chosen.length) { console.error("Nothing selected."); process.exit(1); }

  console.log(`\nImporting ${chosen.length} page(s) into ${opts.vault}/raw/journal …`);
  for (const t of chosen) {
    try {
      const r = await importPage(client, t.page, opts);
      console.log(`  ✓ ${r.title}  →  ${path.relative(opts.vault, r.outPath)}  (${r.images} image${r.images === 1 ? "" : "s"})`);
    } catch (e) {
      console.log(`  ✗ ${t.title}  —  ${e.message}`);
    }
  }
  console.log("\nDone. Now open opencode in the vault and say: \"ingest the new files in raw/journal\".");
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((e) => { console.error(e); process.exit(1); });
}
