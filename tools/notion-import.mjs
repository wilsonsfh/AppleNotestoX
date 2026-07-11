#!/usr/bin/env node
// Import Notion pages into a Personal_LLM_Wiki vault's raw/ folder (markdown + images),
// so opencode can ingest them into wiki/. One command, no Xcode.
//
//   node tools/notion-import.mjs --vault ~/Projects/Personal_LLM_Wiki
//   node tools/notion-import.mjs --all                 # import every accessible page
//   export NOTION_PAGE_ID="your-page-id"
//   node tools/notion-import.mjs --page "$NOTION_PAGE_ID"  # one page
//   node tools/notion-import.mjs --list                # just list accessible pages
//
// Token resolution (first hit wins): --token <t>  →  $NOTION_TOKEN  →  the token saved
// by AppleNotestoX in macOS Keychain. If none is available, the command exits with guidance.
// Prefer Keychain so the token does not enter shell history.
//
// NOTE: built from stable Notion API knowledge (v2022-06-28), NOT live-fact-checked.
// A separate 12-check harness covers block/rich-text/page conversion; verify the live fetch on first run.

import fs from "node:fs";
import dns from "node:dns";
import http from "node:http";
import https from "node:https";
import net from "node:net";
import path from "node:path";
import os from "node:os";
import readline from "node:readline";
import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { fileURLToPath } from "node:url";

const NOTION_VERSION = "2022-06-28";
const API = "https://api.notion.com/v1";
const IMAGE_DOWNLOAD_TIMEOUT_MS = 15_000;
const MAX_IMAGE_BYTES = 25 * 1024 * 1024;
const MAX_IMAGE_REDIRECTS = 5;
const MAX_FTYP_BOX_BYTES = 4096;

// ---------------- pure helpers (exported for tests) ----------------

export function slug(s) {
  return String(s).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "page";
}
export function isoDay(d) {
  const f = new Intl.DateTimeFormat("en-CA", { timeZone: "UTC", year: "numeric", month: "2-digit", day: "2-digit" });
  return f.format(d);
}

function yamlScalar(value) {
  return JSON.stringify(String(value));
}

export function writeUniqueFile(dir, preferredName, data, io = fs) {
  if (path.basename(preferredName) !== preferredName) throw new Error("Unsafe output filename");
  const ext = path.extname(preferredName);
  const stem = preferredName.slice(0, preferredName.length - ext.length);
  let fd;
  let tempPath;
  try {
    for (;;) {
      tempPath = path.join(dir, `.${stem}-${process.pid}-${randomUUID()}.tmp`);
      try {
        fd = io.openSync(tempPath, "wx", 0o666);
        break;
      } catch (error) {
        if (error.code !== "EEXIST") throw error;
      }
    }
    io.writeFileSync(fd, data);
    io.fsyncSync(fd);
    io.closeSync(fd);
    fd = undefined;

    for (let n = 1; ; n++) {
      const name = n === 1 ? preferredName : `${stem}-${n}${ext}`;
      try {
        io.linkSync(tempPath, path.join(dir, name));
        return name;
      } catch (error) {
        if (error.code !== "EEXIST") throw error;
      }
    }
  } finally {
    if (fd !== undefined) {
      try { io.closeSync(fd); } catch { /* preserve the original write error */ }
    }
    if (tempPath) {
      try {
        io.unlinkSync(tempPath);
      } catch (error) {
        if (error.code !== "ENOENT") throw error;
      }
    }
  }
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
    "origin: " + yamlScalar("notion"),
    "source_type: " + yamlScalar("note"),
    "source_app: " + yamlScalar("notion"),
    "notion_page_id: " + yamlScalar(pageId),
    "title: " + yamlScalar(title),
    "imported: " + yamlScalar(isoDay(imported)),
    "---",
    "> Provenance: imported from Notion via tools/notion-import.mjs.",
    "> Synthesize into wiki/, don't edit here.",
    "",
    "",
  ].join("\n");
}

export function sniffImageType(data) {
  if (!Buffer.isBuffer(data)) return null;
  if (data.length >= 8 && data.subarray(0, 8).equals(Buffer.from("89504e470d0a1a0a", "hex"))) {
    return { extension: "png", mimeType: "image/png" };
  }
  if (data.length >= 3 && data[0] === 0xff && data[1] === 0xd8 && data[2] === 0xff) {
    return { extension: "jpg", mimeType: "image/jpeg" };
  }
  if (data.length >= 6 && ["GIF87a", "GIF89a"].includes(data.subarray(0, 6).toString("ascii"))) {
    return { extension: "gif", mimeType: "image/gif" };
  }
  if (data.length >= 12 && data.subarray(0, 4).toString("ascii") === "RIFF" && data.subarray(8, 12).toString("ascii") === "WEBP") {
    return { extension: "webp", mimeType: "image/webp" };
  }
  if (data.length >= 16 && data.readUInt32BE(4) === 0x66747970) { // ftyp
    const boxSize = data.readUInt32BE(0);
    if (boxSize < 16 || boxSize > MAX_FTYP_BOX_BYTES || boxSize > data.length || (boxSize - 16) % 4 !== 0) return null;
    let foundHeic = false;
    let foundHeif = false;
    for (let offset = 8; offset < boxSize; offset = offset === 8 ? 16 : offset + 4) {
      const brand = data.readUInt32BE(offset);
      foundHeic ||= brand === 0x68656963 || brand === 0x68656978 || brand === 0x68657663 || brand === 0x68657678;
      foundHeif ||= brand === 0x68656966 || brand === 0x6d696631 || brand === 0x6d736631;
    }
    if (foundHeic) return { extension: "heic", mimeType: "image/heic" };
    if (foundHeif) return { extension: "heif", mimeType: "image/heif" };
  }
  return null;
}

function ipv4Number(address) {
  const parts = address.split(".").map(Number);
  if (parts.length !== 4 || parts.some((part) => !Number.isInteger(part) || part < 0 || part > 255)) return null;
  return parts.reduce((value, part) => (value << 8n) + BigInt(part), 0n);
}

function ipv6Number(address) {
  let normalized = address.toLowerCase().split("%")[0];
  if (normalized.includes(".")) {
    const lastColon = normalized.lastIndexOf(":");
    const ipv4 = normalized.slice(lastColon + 1);
    const parts = ipv4.split(".").map(Number);
    if (parts.length !== 4 || parts.some((part) => !Number.isInteger(part) || part < 0 || part > 255)) return null;
    normalized = normalized.slice(0, lastColon) + ":" + ((parts[0] << 8) | parts[1]).toString(16)
      + ":" + ((parts[2] << 8) | parts[3]).toString(16);
  }
  const halves = normalized.split("::");
  if (halves.length > 2) return null;
  const left = halves[0] ? halves[0].split(":") : [];
  const right = halves.length === 2 && halves[1] ? halves[1].split(":") : [];
  const zeros = halves.length === 2 ? 8 - left.length - right.length : 0;
  const groups = [...left, ...Array(zeros).fill("0"), ...right];
  if (groups.length !== 8 || groups.some((group) => !/^[0-9a-f]{1,4}$/.test(group))) return null;
  return groups.reduce((value, group) => (value << 16n) + BigInt("0x" + group), 0n);
}

function inCidr(value, network, prefix, bits) {
  const shift = BigInt(bits - prefix);
  return (value >> shift) === (network >> shift);
}

const IPV4_PUBLIC_EXCEPTIONS = ["192.0.0.9", "192.0.0.10"].map(ipv4Number);
const IPV4_NON_PUBLIC = [
  ["0.0.0.0", 8],
  ["10.0.0.0", 8],
  ["100.64.0.0", 10],
  ["127.0.0.0", 8],
  ["169.254.0.0", 16],
  ["172.16.0.0", 12],
  ["192.0.0.0", 24],
  ["192.0.2.0", 24],
  ["192.88.99.0", 24],
  ["192.168.0.0", 16],
  ["198.18.0.0", 15],
  ["198.51.100.0", 24],
  ["203.0.113.0", 24],
  ["224.0.0.0", 4],
  ["240.0.0.0", 4],
].map(([network, prefix]) => [ipv4Number(network), prefix]);

const IPV6_NON_PUBLIC = [
  ["64:ff9b:1::", 48],
  ["100::", 64],
  ["100:0:0:1::", 64],
  ["2001::", 23],
  ["2001:db8::", 32],
  ["2002::", 16],
  ["3fff::", 20],
  ["5f00::", 16],
  ["fc00::", 7],
  ["fe80::", 10],
  ["fec0::", 10],
  ["ff00::", 8],
].map(([network, prefix]) => [ipv6Number(network), prefix]);

const IPV6_PUBLIC_EXCEPTIONS = [
  ["2001:1::1", 128],
  ["2001:1::2", 128],
  ["2001:1::3", 128],
  ["2001:3::", 32],
  ["2001:4:112::", 48],
  ["2001:20::", 28],
  ["2001:30::", 28],
].map(([network, prefix]) => [ipv6Number(network), prefix]);

function isPublicIpv4Number(value) {
  if (value == null) return false;
  if (IPV4_PUBLIC_EXCEPTIONS.includes(value)) return true;
  return !IPV4_NON_PUBLIC.some(([network, prefix]) => inCidr(value, network, prefix, 32));
}

export function isPublicAddress(address) {
  const normalized = String(address).split("%")[0];
  const family = net.isIP(normalized);
  if (family === 4) return isPublicIpv4Number(ipv4Number(normalized));
  if (family !== 6) return false;
  const value = ipv6Number(normalized);
  if (value == null) return false;

  const upper96 = value >> 32n;
  if (upper96 === 0n || upper96 === 0xffffn || upper96 === 0xffff0000n) {
    return isPublicIpv4Number(value & 0xffffffffn);
  }
  if (inCidr(value, ipv6Number("64:ff9b::"), 96, 128)) {
    return isPublicIpv4Number(value & 0xffffffffn);
  }
  if (IPV6_PUBLIC_EXCEPTIONS.some(([network, prefix]) => inCidr(value, network, prefix, 128))) return true;
  return !IPV6_NON_PUBLIC.some(([network, prefix]) => inCidr(value, network, prefix, 128));
}

const lookupAll = (hostname) => dns.promises.lookup(hostname, { all: true, verbatim: true });

async function checkedAddresses(hostname, lookup) {
  const bareHostname = hostname.replace(/^\[|\]$/g, "");
  if (bareHostname.toLowerCase() === "localhost" || bareHostname.toLowerCase().endsWith(".localhost")) {
    throw new Error("Image URL host must be public, not localhost");
  }
  const literalFamily = net.isIP(bareHostname.split("%")[0]);
  const addresses = literalFamily ? [{ address: bareHostname, family: literalFamily }] : await lookup(bareHostname);
  if (!Array.isArray(addresses) || addresses.length === 0) throw new Error("Image URL host did not resolve");
  for (const entry of addresses) {
    const address = typeof entry === "string" ? entry : entry && entry.address;
    if (!address || !isPublicAddress(address)) throw new Error(`Image URL resolved to a non-public address (${address || "unknown"})`);
  }
  return addresses;
}

export async function assertSafeRemoteUrl(value, lookup = lookupAll) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new Error("Image URL is invalid");
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") throw new Error("Image URL must use HTTP(S)");
  if (url.username || url.password) throw new Error("Image URL must not contain credentials");
  await checkedAddresses(url.hostname, lookup);
  return url;
}

function guardedLookup(lookup) {
  return (hostname, options, callback) => {
    checkedAddresses(hostname, lookup).then((addresses) => {
      const normalized = addresses.map((entry) => typeof entry === "string"
        ? { address: entry, family: net.isIP(entry) }
        : { address: entry.address, family: entry.family || net.isIP(entry.address) });
      if (options && options.all) callback(null, normalized);
      else callback(null, normalized[0].address, normalized[0].family);
    }, callback);
  };
}

function withDeadline(promise, deadline, timeoutMs) {
  let timer;
  const timeout = new Promise((resolve, reject) => {
    timer = setTimeout(() => reject(new Error(`Image download timed out after ${timeoutMs} ms`)), Math.max(0, deadline - Date.now()));
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

export function requestImage(url, { timeoutMs, lookup = lookupAll, requestImpl, deadline = Date.now() + timeoutMs }) {
  return new Promise((resolve, reject) => {
    let body;
    let request;
    let settled = false;
    let timer;
    const hop = {
      statusCode: 0,
      headers: {},
      body: null,
      deadlineError: null,
      finish() { clearTimeout(timer); },
      destroy(error) {
        clearTimeout(timer);
        if (body && !body.destroyed) body.destroy(error);
        if (request && !request.destroyed) request.destroy(error);
      },
    };
    const fail = (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      reject(error);
    };
    const expire = () => {
      const error = new Error(`Image download timed out after ${timeoutMs} ms`);
      hop.deadlineError = error;
      if (!settled) {
        settled = true;
        reject(error);
      }
      hop.destroy(error);
    };

    timer = setTimeout(expire, Math.max(0, deadline - Date.now()));
    try {
      const createRequest = requestImpl || (url.protocol === "https:" ? https.request : http.request);
      request = createRequest(url, { lookup: guardedLookup(lookup) }, (response) => {
        body = response;
        if (settled) {
          if (!body.destroyed) body.destroy(hop.deadlineError || undefined);
          return;
        }
        settled = true;
        hop.statusCode = body.statusCode;
        hop.headers = body.headers;
        hop.body = body;
        resolve(hop);
      });
      request.on("error", fail);
      request.end();
    } catch (error) {
      fail(error);
    }
  });
}

function transportImage(url, transport, deadline, timeoutMs) {
  return new Promise((resolve, reject) => {
    let response;
    let settled = false;
    let timer;
    const expire = () => {
      const error = new Error(`Image download timed out after ${timeoutMs} ms`);
      if (response && response.body && !response.body.destroyed) response.body.destroy(error);
      if (!settled) reject(error);
      settled = true;
    };
    timer = setTimeout(expire, Math.max(0, deadline - Date.now()));
    Promise.resolve().then(() => transport(url)).then((value) => {
      if (settled) {
        if (value.body && !value.body.destroyed) value.body.destroy();
        return;
      }
      settled = true;
      response = value;
      resolve({
        ...response,
        deadlineError: null,
        finish() { clearTimeout(timer); },
        destroy(error) {
          clearTimeout(timer);
          if (response.body && !response.body.destroyed) response.body.destroy(error);
        },
      });
    }, (error) => {
      clearTimeout(timer);
      if (!settled) reject(error);
      settled = true;
    });
  });
}

function headerValue(headers, name) {
  const value = headers && headers[name];
  return Array.isArray(value) ? value[0] : value;
}

async function boundedBody(body, maxBytes) {
  const chunks = [];
  let bytes = 0;
  try {
    for await (const chunk of body) {
      const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
      bytes += buffer.length;
      if (bytes > maxBytes) throw new Error(`Image download exceeded ${maxBytes} bytes`);
      chunks.push(buffer);
    }
  } catch (error) {
    if (typeof body.destroy === "function") body.destroy();
    throw error;
  }
  return Buffer.concat(chunks, bytes);
}

export async function downloadRemoteImage(value, options = {}) {
  const lookup = options.lookup || lookupAll;
  const timeoutMs = options.timeoutMs ?? IMAGE_DOWNLOAD_TIMEOUT_MS;
  const maxBytes = options.maxBytes ?? MAX_IMAGE_BYTES;
  const maxRedirects = options.maxRedirects ?? MAX_IMAGE_REDIRECTS;
  let current = new URL(value);
  let redirects = 0;

  for (;;) {
    const deadline = Date.now() + timeoutMs;
    current = await withDeadline(assertSafeRemoteUrl(current.href, lookup), deadline, timeoutMs);
    const response = options.transport
      ? await transportImage(current, options.transport, deadline, timeoutMs)
      : await requestImage(current, { timeoutMs, lookup, requestImpl: options.requestImpl, deadline });
    const status = response.statusCode || 0;
    const location = headerValue(response.headers, "location");
    if ([301, 302, 303, 307, 308].includes(status) && location) {
      response.destroy();
      if (redirects >= maxRedirects) throw new Error(`Image download exceeded ${maxRedirects} redirects`);
      current = new URL(location, current);
      redirects++;
      continue;
    }
    if (status < 200 || status >= 300) {
      response.destroy();
      throw new Error(`Image download returned HTTP status ${status}`);
    }
    const contentType = String(headerValue(response.headers, "content-type") || "").split(";", 1)[0].trim().toLowerCase();
    const genericContentType = !contentType || contentType === "application/octet-stream" || contentType === "binary/octet-stream";
    const supportedContentTypes = new Set([
      "image/png", "image/jpeg", "image/jpg", "image/gif", "image/webp",
      "image/heic", "image/heic-sequence", "image/heif", "image/heif-sequence",
    ]);
    if (!genericContentType && !supportedContentTypes.has(contentType)) {
      response.destroy();
      throw new Error(`Image download returned unexpected content type ${contentType}`);
    }
    const contentLength = Number(headerValue(response.headers, "content-length"));
    if (Number.isFinite(contentLength) && contentLength > maxBytes) {
      response.destroy();
      throw new Error(`Image download is too large (${contentLength} bytes; limit ${maxBytes})`);
    }
    try {
      const data = await boundedBody(response.body, maxBytes);
      const imageType = sniffImageType(data);
      if (!imageType) throw new Error("Image download has an unsupported or invalid image signature");
      const matchingContentTypes = {
        png: ["image/png"],
        jpg: ["image/jpeg", "image/jpg"],
        gif: ["image/gif"],
        webp: ["image/webp"],
        heic: ["image/heic", "image/heic-sequence"],
        heif: ["image/heif", "image/heif-sequence"],
      };
      if (!genericContentType && !matchingContentTypes[imageType.extension].includes(contentType)) {
        throw new Error(`Image content type ${contentType} does not match its ${imageType.extension} signature`);
      }
      response.finish();
      return { data, ...imageType };
    } catch (error) {
      response.destroy();
      throw error;
    }
  }
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
    download: downloadRemoteImage,
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

function rollbackAssets(assets, io) {
  for (let index = assets.length - 1; index >= 0; index--) {
    const asset = assets[index];
    try {
      const current = io.statSync(asset.path, { bigint: true });
      if (current.dev === asset.dev && current.ino === asset.ino) io.unlinkSync(asset.path);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
}

export async function importPage(client, page, opts) {
  const title = pageTitle(page);
  const s = slug(title);
  const io = opts.io || fs;
  const journalDir = path.join(opts.vault, opts.subdir || "raw/journal");
  const assetsDir = path.join(opts.vault, "raw/assets");
  fs.mkdirSync(journalDir, { recursive: true });
  fs.mkdirSync(assetsDir, { recursive: true });

  const blocks = await client.children(page.id);

  // download images, build id -> inline markdown
  const images = collectImages(blocks);
  const inlineById = {};
  const publishedAssets = [];
  let successfulImages = 0;
  let failedImages = 0;
  let idx = 0;
  for (const img of images) {
    idx++;
    try {
      const image = await client.download(img.url);
      const name = writeUniqueFile(assetsDir, `${s}-${String(idx).padStart(2, "0")}.${image.extension}`, image.data, io);
      const assetPath = path.join(assetsDir, name);
      const identity = io.statSync(assetPath, { bigint: true });
      publishedAssets.push({ path: assetPath, dev: identity.dev, ino: identity.ino });
      inlineById[img.id] = `![[${name}]]`;
      successfulImages++;
    } catch (e) {
      inlineById[img.id] = `_(image failed to download)_`;
      failedImages++;
      console.warn(`  warning: skipped image ${idx} for "${title}": ${e.message}`);
    }
  }

  try {
    const body = frontmatter({ pageId: page.id, title, imported: new Date() })
      + notionToMarkdown(blocks, (b) => inlineById[b.id] || null);
    const name = writeUniqueFile(journalDir, `${isoDay(new Date())}-${s}.md`, body, io);
    const outPath = path.join(journalDir, name);
    return { title, outPath, successfulImages, failedImages };
  } catch (error) {
    rollbackAssets(publishedAssets, io);
    throw error;
  }
}

// ---------------- main ----------------

async function main() {
  const opts = parseArgs(process.argv);
  if (opts.help) {
    console.log("usage: node tools/notion-import.mjs --vault <path> [--all | --page <id> | --list] [--token <t>] [--subdir raw/journal]\n" +
      "token: --token, then NOTION_TOKEN, then the AppleNotestoX macOS Keychain entry.\n" +
      "Prefer Keychain to keep the token out of shell history; if none is available, the command exits with setup guidance.");
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
      console.log(`  ✓ ${r.title}  →  ${path.relative(opts.vault, r.outPath)}  (${r.successfulImages} image${r.successfulImages === 1 ? "" : "s"} downloaded, ${r.failedImages} failed)`);
    } catch (e) {
      console.log(`  ✗ ${t.title}  —  ${e.message}`);
    }
  }
  console.log("\nDone. Now open opencode in the vault and say: \"ingest the new files in raw/journal\".");
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((e) => { console.error(e); process.exit(1); });
}
