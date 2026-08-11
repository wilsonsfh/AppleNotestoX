#!/usr/bin/env node
// Generates review/study-data.js (window.STUDY_DATA) from a wiki vault's wiki/ folder.
//
//   node review/generate.mjs --vault ~/Projects/Personal_LLM_Wiki [--out review/study-data.js]
//
// No dependencies. Emits a classic <script> global so the static app can load it
// from file:// (a fetch('*.json') would be CORS-blocked there).

import fs from "node:fs";
import path from "node:path";
import os from "node:os";

// ---- args ---------------------------------------------------------------
function parseArgs(argv) {
  const out = {};
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--vault") out.vault = argv[++i];
    else if (a === "--out") out.out = argv[++i];
    else if (a === "--help" || a === "-h") out.help = true;
  }
  return out;
}

const scriptDir = path.dirname(new URL(import.meta.url).pathname);
const args = parseArgs(process.argv);
if (args.help) {
  console.log("usage: node review/generate.mjs --vault <vault-path> [--out <file>]");
  process.exit(0);
}
// No personal default: a wrong-but-plausible path fails confusingly on someone
// else's machine. Take --vault, else $APPLENOTESTOX_VAULT, else explain and stop.
const vaultArg = args.vault || process.env.APPLENOTESTOX_VAULT;
if (!vaultArg) {
  console.error(
    "error: no vault specified.\n" +
    "  pass --vault <path-to-your-wiki>, or set APPLENOTESTOX_VAULT.\n" +
    "  example: node review/generate.mjs --vault ~/Projects/Personal_LLM_Wiki",
  );
  process.exit(1);
}
const vault = expandHome(vaultArg);
const outFile = expandHome(args.out || path.join(scriptDir, "study-data.js"));
const wikiDir = path.join(vault, "wiki");

if (!fs.existsSync(wikiDir)) {
  console.error(`error: no wiki/ folder at ${wikiDir}`);
  process.exit(1);
}

// ---- helpers ------------------------------------------------------------
function expandHome(p) {
  return p.startsWith("~") ? path.join(os.homedir(), p.slice(1)) : p;
}

function walk(dir) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walk(full));
    else if (entry.isFile() && entry.name.endsWith(".md")) out.push(full);
  }
  return out;
}

function slug(s) {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "page";
}

function humanize(base) {
  return base.replace(/[-_]+/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}

function parseFrontmatter(md) {
  const m = md.match(/^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/);
  if (!m) return { data: {}, body: md };
  const data = {};
  let key = null;
  for (const line of m[1].split(/\r?\n/)) {
    const kv = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    const li = line.match(/^\s*-\s+(.*)$/);
    if (kv) {
      key = kv[1];
      const v = kv[2].trim();
      if (v === "") data[key] = [];
      else if (v.startsWith("[") && v.endsWith("]")) {
        data[key] = v.slice(1, -1).split(",").map((x) => unquote(x.trim())).filter(Boolean);
      } else data[key] = unquote(v);
    } else if (li && key) {
      if (!Array.isArray(data[key])) data[key] = [];
      data[key].push(unquote(li[1].trim()));
    }
  }
  return { data, body: md.slice(m[0].length) };
}

function unquote(s) {
  return s.replace(/^['"]|['"]$/g, "");
}

function stripCode(body) {
  return body.replace(/```[\s\S]*?```/g, "").replace(/`[^`\n]*`/g, "");
}

function cleanInline(s) {
  return s
    .replace(/!\[\[[^\]]*\]\]/g, "")                       // image embeds
    .replace(/\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|([^\]]+))?\]\]/g, (_, p, alias) => alias || p) // wikilinks
    .replace(/!\[[^\]]*\]\([^)]*\)/g, "")                  // md images
    .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")               // md links
    .replace(/[*_~`]+/g, "")                                // emphasis marks
    .replace(/\s+/g, " ")
    .trim();
}

function firstParagraph(body) {
  const lines = body.split(/\r?\n/);
  let i = 0;
  while (i < lines.length && !lines[i].startsWith("# ")) i++;   // find H1
  if (i < lines.length) i++;                                     // skip H1
  while (i < lines.length && lines[i].trim() === "") i++;        // skip blanks
  const buf = [];
  for (; i < lines.length; i++) {
    const l = lines[i].trim();
    if (l === "") break;
    if (/^(#{1,6}\s|[-*>|]|\d+\.)/.test(l)) { if (buf.length) break; else continue; }
    buf.push(l);
  }
  return cleanInline(buf.join(" "));
}

function firstSentence(text) {
  const m = text.match(/^(.*?[.!?])(\s|$)/);
  return (m ? m[1] : text).trim();
}

function extractTitle(body, base) {
  const m = body.match(/^#\s+(.+)$/m);
  return m ? cleanInline(m[1].trim()) : humanize(base);
}

function extractWikilinks(body) {
  const text = stripCode(body);
  const links = new Set();
  for (const m of text.matchAll(/(?<!\!)\[\[([^\]\n]+)\]\]/g)) {
    const target = m[1].split("|")[0].split("#")[0].trim();
    if (target) links.add(target);
  }
  return [...links];
}

// Explicit Obsidian-SR cards: single-line A::B / A:::B, multiline ?/??.
function extractCards(body) {
  const cards = [];
  const text = stripCode(body);
  const lines = text.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const tri = line.match(/^(.+?):::(.+)$/);
    const dbl = line.match(/^(.+?)::(.+)$/);
    if (tri) {
      const q = cleanInline(tri[1]); const a = cleanInline(tri[2]);
      if (q && a) { cards.push({ front: q, back: a }); cards.push({ front: a, back: q }); }
    } else if (dbl) {
      const q = cleanInline(dbl[1]); const a = cleanInline(dbl[2]);
      if (q && a) cards.push({ front: q, back: a });
    }
  }
  // multi-line ? / ??
  const blocks = text.split(/\n\s*\n/);
  for (const block of blocks) {
    const bl = block.split(/\r?\n/);
    const sep = bl.findIndex((l) => l.trim() === "?" || l.trim() === "??");
    if (sep > 0 && sep < bl.length - 1) {
      const q = cleanInline(bl.slice(0, sep).join(" "));
      const a = cleanInline(bl.slice(sep + 1).join(" "));
      const reversed = bl[sep].trim() === "??";
      if (q && a) {
        cards.push({ front: q, back: a });
        if (reversed) cards.push({ front: a, back: q });
      }
    }
  }
  return cards;
}

// ---- build --------------------------------------------------------------
const SKIP = new Set(["index", "log"]);
const files = walk(wikiDir);

const pages = [];           // {id, base, title, type, summary, tags, linkNames}
const idByName = new Map(); // basename + aliases -> id

for (const file of files) {
  const base = path.basename(file, ".md");
  if (SKIP.has(base)) continue;
  const md = fs.readFileSync(file, "utf8");
  const { data, body } = parseFrontmatter(md);
  const id = slug(base);
  const title = extractTitle(body, base);
  const type = (Array.isArray(data.type) ? data.type[0] : data.type) || "concept";
  const tags = Array.isArray(data.tags) ? data.tags : [];
  const summary = firstParagraph(body);
  const linkNames = extractWikilinks(body);
  const explicitCards = extractCards(body);
  pages.push({ id, base, title, type, summary, tags, linkNames, explicitCards });

  idByName.set(base.toLowerCase(), id);
  idByName.set(slug(base), id);
  const aliases = Array.isArray(data.aliases) ? data.aliases : [];
  for (const al of aliases) { idByName.set(al.toLowerCase(), id); idByName.set(slug(al), id); }
}

const knownIds = new Set(pages.map((p) => p.id));

// concepts + edges
const concepts = pages.map((p) => {
  const links = [...new Set(
    p.linkNames
      .map((n) => idByName.get(n.toLowerCase()) || (knownIds.has(slug(n)) ? slug(n) : null))
      .filter((id) => id && id !== p.id)
  )];
  return { id: p.id, title: p.title, type: p.type, summary: p.summary, tags: p.tags, links };
});

const edgeSet = new Set();
const edges = [];
for (const c of concepts) {
  for (const t of c.links) {
    const key = [c.id, t].sort().join("|");
    if (!edgeSet.has(key) && knownIds.has(t)) {
      edgeSet.add(key);
      edges.push({ source: c.id, target: t });
    }
  }
}

// cards: explicit first, else one heuristic definition card per concept
const cards = [];
for (const p of pages) {
  const deck = p.type;
  if (p.explicitCards.length) {
    p.explicitCards.forEach((c, i) =>
      cards.push({ id: `${p.id}::${i}`, deck, front: c.front, back: c.back, source: p.id })
    );
  } else if (p.summary) {
    cards.push({
      id: `${p.id}::def`,
      deck,
      front: `What is ${p.title}?`,
      back: firstSentence(p.summary),
      source: p.id,
    });
  }
}

const data = {
  generatedAt: new Date().toISOString(),
  vault: path.basename(vault),
  concepts,
  cards,
  edges,
};

const banner = `// GENERATED by review/generate.mjs from ${path.basename(vault)} — do not edit by hand.\n`;
fs.writeFileSync(outFile, banner + "window.STUDY_DATA = " + JSON.stringify(data, null, 2) + ";\n");

console.log(`wrote ${outFile}`);
console.log(`  concepts: ${concepts.length}`);
console.log(`  cards:    ${cards.length}`);
console.log(`  edges:    ${edges.length}`);
const orphans = concepts.filter((c) => !edges.some((e) => e.source === c.id || e.target === c.id));
console.log(`  orphans:  ${orphans.length}${orphans.length ? " (" + orphans.map((o) => o.id).join(", ") + ")" : ""}`);
