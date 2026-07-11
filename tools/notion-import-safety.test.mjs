import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { EventEmitter } from "node:events";
import { PassThrough, Readable } from "node:stream";
import test from "node:test";
import { Worker } from "node:worker_threads";

import * as notion from "./notion-import.mjs";

const PUBLIC_V4 = "52.95.110.1";
const PUBLIC_V6 = "2600:9000:2000::1";
const publicLookup = async () => [{ address: PUBLIC_V4, family: 4 }];

const addressCases = [
  [false, "0.0.0.0", "unspecified"],
  [false, "0.255.255.255", "this network"],
  [false, "10.0.0.1", "private"],
  [false, "100.64.0.1", "shared address space"],
  [false, "100.127.255.254", "shared address boundary"],
  [false, "127.0.0.1", "loopback"],
  [false, "169.254.1.1", "link local"],
  [false, "172.16.0.1", "private lower boundary"],
  [false, "172.31.255.254", "private upper boundary"],
  [false, "192.0.0.0", "IETF assignment"],
  [false, "192.0.0.8", "IPv4 dummy address"],
  [true, "192.0.0.9", "PCP anycast exception"],
  [true, "192.0.0.10", "TURN anycast exception"],
  [false, "192.0.2.1", "documentation TEST-NET-1"],
  [true, "192.31.196.1", "AS112 public range"],
  [true, "192.52.193.1", "AMT public range"],
  [false, "192.88.99.1", "deprecated 6to4 relay"],
  [false, "192.88.99.2", "6a44 relay anycast"],
  [false, "192.168.1.1", "private"],
  [true, "192.175.48.1", "direct delegation public range"],
  [false, "198.18.0.1", "benchmark"],
  [false, "198.51.100.1", "documentation TEST-NET-2"],
  [false, "203.0.113.1", "documentation TEST-NET-3"],
  [false, "224.0.0.1", "multicast"],
  [false, "239.255.255.255", "multicast boundary"],
  [false, "240.0.0.1", "reserved"],
  [false, "255.255.255.255", "limited broadcast"],
  [true, "1.1.1.1", "public IPv4"],
  [true, PUBLIC_V4, "public AWS IPv4"],
  [false, "::", "IPv6 unspecified"],
  [false, "::1", "IPv6 loopback"],
  [false, "::ffff:10.0.0.1", "mapped private IPv4"],
  [false, "::ffff:192.0.2.1", "mapped documentation IPv4"],
  [true, "::ffff:52.95.110.1", "mapped public AWS IPv4"],
  [false, "::ffff:0:10.0.0.1", "translated private IPv4"],
  [true, "::ffff:0:52.95.110.1", "translated public AWS IPv4"],
  [false, "::10.0.0.1", "compatible private IPv4"],
  [true, "::52.95.110.1", "compatible public AWS IPv4"],
  [false, "64:ff9b::10.0.0.1", "well-known translation of private IPv4"],
  [true, "64:ff9b::52.95.110.1", "well-known translation of public AWS IPv4"],
  [false, "64:ff9b:1::1", "local-use translation"],
  [false, "100::1", "discard-only"],
  [false, "100:0:0:1::1", "IPv6 dummy prefix"],
  [false, "2001::1", "Teredo"],
  [true, "2001:1::1", "IPv6 PCP anycast exception"],
  [true, "2001:1::2", "IPv6 TURN anycast exception"],
  [true, "2001:1::3", "IPv6 DNS-SD anycast exception"],
  [false, "2001:2::1", "benchmark"],
  [true, "2001:3::1", "AMT public range"],
  [true, "2001:4:112::1", "AS112 public range"],
  [false, "2001:5::1", "unassigned IETF protocol space"],
  [false, "2001:10::1", "ORCHIDv1"],
  [true, "2001:20::1", "globally reachable ORCHIDv2"],
  [true, "2001:30::1", "Drone Remote ID public range"],
  [false, "2001:db8::1", "IPv6 documentation"],
  [false, "2002::1", "deprecated 6to4"],
  [false, "3fff::1", "IPv6 documentation"],
  [false, "5f00::1", "segment-routing SIDs"],
  [false, "fc00::1", "unique local"],
  [false, "fe80::1", "link local"],
  [false, "fec0::1", "deprecated site local"],
  [false, "ff02::1", "multicast"],
  [true, "2001:4860:4860::8888", "public IPv6"],
  [true, PUBLIC_V6, "public AWS IPv6"],
];

test("public-address classifier covers IPv4 and IPv6 special-purpose ranges", async (t) => {
  for (const [expected, address, label] of addressCases) {
    await t.test(`${label}: ${address}`, () => {
      assert.equal(notion.isPublicAddress(address), expected);
    });
  }
});

test("URL policy preserves signed public HTTPS URLs and rejects mixed DNS answers", async () => {
  const signed = "https://prod-files-secure.s3.us-west-2.amazonaws.com/image?X-Amz-Signature=a%2Fb&x=1";
  const safe = await notion.assertSafeRemoteUrl(signed, publicLookup);
  assert.equal(safe.href, signed);
  await assert.rejects(
    () => notion.assertSafeRemoteUrl("https://mixed.example/image", async () => [
      { address: PUBLIC_V4, family: 4 },
      { address: "127.0.0.1", family: 4 },
    ]),
    /non-public/i,
  );
});

test("frontmatter quotes every YAML scalar and cannot inject metadata", () => {
  const yaml = notion.frontmatter({
    pageId: "id: #1",
    title: "Title: value\nadmin: true # injected",
    imported: new Date("2026-07-12T00:00:00Z"),
  });
  assert.match(yaml, /^origin: "notion"$/m);
  assert.match(yaml, /^notion_page_id: "id: #1"$/m);
  assert.match(yaml, /^title: "Title: value\\nadmin: true # injected"$/m);
  assert.equal(yaml.split("\n").filter((line) => line.startsWith("admin:")).length, 0);
});

function fakeRequestImpl({ responseBody, onRequest }) {
  return (url, options, onResponse) => {
    const request = new EventEmitter();
    request.destroyed = false;
    request.destroyError = null;
    request.destroy = (error) => {
      if (request.destroyed) return request;
      request.destroyed = true;
      request.destroyError = error || null;
      if (responseBody && !responseBody.destroyed) responseBody.destroy(error);
      if (error) queueMicrotask(() => request.emit("error", error));
      return request;
    };
    request.end = () => {
      options.lookup(url.hostname, { all: false }, (error) => {
        if (error) request.destroy(error);
        else if (responseBody) queueMicrotask(() => onResponse(responseBody));
      });
    };
    onRequest(request);
    return request;
  };
}

test("connection-time lookup blocks public-then-private DNS rebinding", async () => {
  let lookups = 0;
  let request;
  const lookup = async () => {
    lookups++;
    return [{ address: lookups === 1 ? PUBLIC_V4 : "127.0.0.1", family: 4 }];
  };
  const url = await notion.assertSafeRemoteUrl("https://signed.example/image?token=secret", lookup);
  await assert.rejects(
    () => notion.requestImage(url, {
      lookup,
      timeoutMs: 100,
      requestImpl: fakeRequestImpl({ onRequest: (value) => { request = value; } }),
    }),
    /non-public/i,
  );
  assert.equal(lookups, 2);
  assert.equal(request.destroyed, true);
});

test("request absolute deadline destroys a pending ClientRequest", async () => {
  let request;
  await assert.rejects(
    () => notion.requestImage(new URL("https://public.example/image"), {
      lookup: publicLookup,
      timeoutMs: 10,
      requestImpl: fakeRequestImpl({ onRequest: (value) => { request = value; } }),
    }),
    /timed out/i,
  );
  assert.equal(request.destroyed, true);
  assert.match(request.destroyError.message, /timed out/i);
});

test("one request deadline remains active through response consumption", async () => {
  let request;
  const body = new PassThrough();
  body.statusCode = 200;
  body.headers = { "content-type": "image/png" };
  body.on("error", () => {});
  const hop = await notion.requestImage(new URL("https://public.example/image"), {
    lookup: publicLookup,
    timeoutMs: 10,
    requestImpl: fakeRequestImpl({ responseBody: body, onRequest: (value) => { request = value; } }),
  });
  await new Promise((resolve) => setTimeout(resolve, 25));
  assert.equal(request.destroyed, true);
  assert.equal(body.destroyed, true);
  assert.match(hop.deadlineError.message, /timed out/i);
});

test("redirect and rejected response bodies are destroyed rather than drained", async () => {
  const redirected = new PassThrough();
  const rejected = new PassThrough();
  let calls = 0;
  const transport = async () => {
    calls++;
    return calls === 1
      ? { statusCode: 302, headers: { location: "https://public.example/final?signature=a%2Fb" }, body: redirected }
      : { statusCode: 403, headers: {}, body: rejected };
  };
  await assert.rejects(
    () => notion.downloadRemoteImage("https://public.example/start?signature=one", {
      lookup: publicLookup,
      transport,
      timeoutMs: 100,
    }),
    /403|status/i,
  );
  assert.equal(calls, 2);
  assert.equal(redirected.destroyed, true);
  assert.equal(rejected.destroyed, true);
});

function tempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "notion-import-safety-"));
}

test("unique writes sync a same-directory temp file before no-clobber publish", () => {
  const dir = tempDir();
  let synced = false;
  let publishedSource;
  const io = Object.create(fs);
  io.fsyncSync = (fd) => {
    synced = true;
    return fs.fsyncSync(fd);
  };
  io.linkSync = (source, destination) => {
    publishedSource = source;
    return fs.linkSync(source, destination);
  };
  try {
    const name = notion.writeUniqueFile(dir, "page.png", Buffer.from("image"), io);
    assert.equal(name, "page.png");
    assert.equal(synced, true);
    assert.equal(path.dirname(publishedSource), dir);
    assert.notEqual(publishedSource, path.join(dir, name));
    assert.equal(fs.readFileSync(path.join(dir, name), "utf8"), "image");
    assert.equal(fs.statSync(path.join(dir, name)).mode & 0o777, 0o666 & ~process.umask());
    assert.deepEqual(fs.readdirSync(dir), ["page.png"]);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("unique writes suffix collisions without changing unrelated files", () => {
  const dir = tempDir();
  try {
    fs.writeFileSync(path.join(dir, "page.png"), "unrelated");
    fs.writeFileSync(path.join(dir, "page-2.png"), "also unrelated");
    const name = notion.writeUniqueFile(dir, "page.png", Buffer.from("new image"));
    assert.equal(name, "page-3.png");
    assert.equal(fs.readFileSync(path.join(dir, "page.png"), "utf8"), "unrelated");
    assert.equal(fs.readFileSync(path.join(dir, "page-2.png"), "utf8"), "also unrelated");
    assert.equal(fs.readFileSync(path.join(dir, name), "utf8"), "new image");
    assert.equal(fs.readdirSync(dir).some((entry) => entry.includes(".tmp")), false);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("unique writes remove temporary files when publish fails", () => {
  const dir = tempDir();
  const io = Object.create(fs);
  io.linkSync = () => {
    const error = new Error("publish failed");
    error.code = "EIO";
    throw error;
  };
  try {
    assert.throws(() => notion.writeUniqueFile(dir, "page.png", Buffer.from("image"), io), /publish failed/);
    assert.deepEqual(fs.readdirSync(dir), []);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("concurrent unique writes publish distinct complete files", async () => {
  const dir = tempDir();
  const moduleUrl = new URL("./notion-import.mjs", import.meta.url).href;
  const workerSource = `
    import { parentPort, workerData } from "node:worker_threads";
    const { writeUniqueFile } = await import(workerData.moduleUrl);
    const name = writeUniqueFile(workerData.dir, "asset.png", Buffer.from(workerData.content));
    parentPort.postMessage(name);
  `;
  try {
    const names = await Promise.all(Array.from({ length: 8 }, (_, index) => new Promise((resolve, reject) => {
      const worker = new Worker(workerSource, {
        eval: true,
        type: "module",
        workerData: { moduleUrl, dir, content: `content-${index}` },
      });
      worker.once("message", resolve);
      worker.once("error", reject);
    })));
    assert.equal(new Set(names).size, 8);
    const contents = names.map((name) => fs.readFileSync(path.join(dir, name), "utf8")).sort();
    assert.deepEqual(contents, Array.from({ length: 8 }, (_, index) => `content-${index}`).sort());
    assert.equal(fs.readdirSync(dir).some((entry) => entry.includes(".tmp")), false);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

function notionPage(title = "Import Test") {
  return {
    id: "page-id",
    properties: {
      Name: { type: "title", title: [{ plain_text: title }] },
    },
  };
}

function imageBlock(id, url) {
  return { id, type: "image", image: { type: "file", file: { url } } };
}

function imageClient(blocks, download) {
  return { children: async () => blocks, download };
}

function journalFailureIo(beforeFailure) {
  const io = Object.create(fs);
  io.linkSync = (source, destination) => {
    if (destination.endsWith(".md")) {
      beforeFailure?.();
      const error = new Error("journal publish failed");
      error.code = "EIO";
      throw error;
    }
    return fs.linkSync(source, destination);
  };
  return io;
}

test("journal publication failure rolls back assets created by the import attempt", async () => {
  const vault = tempDir();
  const client = imageClient([imageBlock("one", "https://public.example/one.png")], async () => ({ data: PNG, extension: "png" }));
  try {
    await assert.rejects(() => notion.importPage(client, notionPage(), { vault, io: journalFailureIo() }), /journal publish failed/);
    assert.deepEqual(fs.readdirSync(path.join(vault, "raw/assets")), []);
    assert.deepEqual(fs.readdirSync(path.join(vault, "raw/journal")), []);
  } finally {
    fs.rmSync(vault, { recursive: true, force: true });
  }
});

test("rollback preserves an asset path replaced after provisional publication", async () => {
  const vault = tempDir();
  const assetsDir = path.join(vault, "raw/assets");
  const client = imageClient([imageBlock("one", "https://public.example/one.png")], async () => ({ data: PNG, extension: "png" }));
  let assetPath;
  const io = journalFailureIo(() => {
    assetPath = path.join(assetsDir, fs.readdirSync(assetsDir)[0]);
    const replacement = path.join(assetsDir, ".replacement");
    fs.writeFileSync(replacement, "replacement asset");
    fs.renameSync(replacement, assetPath);
  });
  try {
    await assert.rejects(() => notion.importPage(client, notionPage(), { vault, io }), /journal publish failed/);
    assert.equal(fs.readFileSync(assetPath, "utf8"), "replacement asset");
    assert.deepEqual(fs.readdirSync(assetsDir), [path.basename(assetPath)]);
  } finally {
    fs.rmSync(vault, { recursive: true, force: true });
  }
});

test("successful journal publication commits provisional assets", async () => {
  const vault = tempDir();
  const client = imageClient([imageBlock("one", "https://public.example/one.png")], async () => ({ data: PNG, extension: "png" }));
  try {
    const result = await notion.importPage(client, notionPage(), { vault });
    assert.equal(result.successfulImages, 1);
    assert.equal(result.failedImages, 0);
    assert.equal(fs.readdirSync(path.join(vault, "raw/assets")).length, 1);
    assert.equal(fs.existsSync(result.outPath), true);
  } finally {
    fs.rmSync(vault, { recursive: true, force: true });
  }
});

test("mixed image results return accurate counts and retain warning placeholders", async () => {
  const vault = tempDir();
  const blocks = [
    imageBlock("good", "https://public.example/good.png"),
    imageBlock("bad", "https://public.example/bad.png"),
  ];
  const client = imageClient(blocks, async (url) => {
    if (url.includes("bad")) throw new Error("download rejected");
    return { data: PNG, extension: "png" };
  });
  const originalWarn = console.warn;
  const warnings = [];
  console.warn = (message) => warnings.push(message);
  try {
    const result = await notion.importPage(client, notionPage("Mixed Images"), { vault });
    const markdown = fs.readFileSync(result.outPath, "utf8");
    assert.equal(result.successfulImages, 1);
    assert.equal(result.failedImages, 1);
    assert.match(markdown, /!\[\[mixed-images-01\.png\]\]/);
    assert.match(markdown, /_\(image failed to download\)_/);
    assert.equal(warnings.length, 1);
  } finally {
    console.warn = originalWarn;
    fs.rmSync(vault, { recursive: true, force: true });
  }
});

const PNG = Buffer.from("89504e470d0a1a0a", "hex");
const JPEG = Buffer.from("ffd8ffe000104a464946", "hex");
const GIF = Buffer.from("GIF89a", "ascii");
const WEBP = Buffer.concat([Buffer.from("RIFF", "ascii"), Buffer.alloc(4), Buffer.from("WEBP", "ascii")]);
const HEIC = Buffer.concat([Buffer.from("0000001466747970", "hex"), Buffer.from("heic", "ascii"), Buffer.alloc(8)]);
const HEIF = Buffer.concat([Buffer.from("0000001466747970", "hex"), Buffer.from("mif1", "ascii"), Buffer.alloc(8)]);

const imageCases = [
  [PNG, "png", "image/png"],
  [JPEG, "jpg", "image/jpeg"],
  [GIF, "gif", "image/gif"],
  [WEBP, "webp", "image/webp"],
  [HEIC, "heic", "image/heic"],
  [HEIF, "heif", "image/heif"],
];

test("image signature classifier recognizes only supported raster formats", async (t) => {
  for (const [data, extension, mimeType] of imageCases) {
    await t.test(extension, () => {
      assert.deepEqual(notion.sniffImageType(data), { extension, mimeType });
    });
  }
  assert.equal(notion.sniffImageType(Buffer.from("<svg xmlns='http://www.w3.org/2000/svg'/>")), null);
  assert.equal(notion.sniffImageType(Buffer.from("<html>not an image</html>")), null);
  assert.equal(notion.sniffImageType(Buffer.from("arbitrary bytes")), null);
});

function ftypBox({ declaredSize, actualSize, major = "zzzz", minor = 0, compatible = [], trailing = [] }) {
  const size = actualSize ?? declaredSize ?? (16 + compatible.length * 4);
  const data = Buffer.alloc(size);
  if (size >= 4) data.writeUInt32BE(declaredSize ?? size, 0);
  if (size >= 8) data.write("ftyp", 4, "ascii");
  if (size >= 12) data.write(major, 8, 4, "ascii");
  if (size >= 16) data.writeUInt32BE(minor, 12);
  for (let index = 0; index < compatible.length && 16 + index * 4 + 4 <= size; index++) {
    data.write(compatible[index], 16 + index * 4, 4, "ascii");
  }
  return Buffer.concat([data, ...trailing.map((value) => Buffer.from(value, "ascii"))]);
}

test("HEIF ftyp parsing is bounded by a valid declared box", async (t) => {
  const cases = [
    ["undersized box", ftypBox({ declaredSize: 12, actualSize: 12, major: "heic" }), null],
    ["declared size exceeds body", ftypBox({ declaredSize: 24, actualSize: 16, major: "heic" }), null],
    ["misaligned box size", ftypBox({ declaredSize: 18, actualSize: 18, major: "heic" }), null],
    ["oversized parser box", ftypBox({ declaredSize: 4100, actualSize: 4100, major: "heic" }), null],
    ["minor version is not a brand", ftypBox({ declaredSize: 16, major: "zzzz", minor: 0x68656963 }), null],
    ["compatible brand inside box", ftypBox({ major: "zzzz", compatible: ["heic"] }), { extension: "heic", mimeType: "image/heic" }],
    ["brand outside box is ignored", ftypBox({ declaredSize: 16, major: "zzzz", trailing: ["heic"] }), null],
  ];
  for (const [label, data, expected] of cases) {
    await t.test(label, () => assert.deepEqual(notion.sniffImageType(data), expected));
  }
});

function streamResponse(statusCode, headers, chunks) {
  return { statusCode, headers, body: Readable.from(chunks) };
}

test("signed redirect and octet-stream download preserve query and derive extension from bytes", async () => {
  const seen = [];
  const transport = async (url) => {
    seen.push(url.href);
    if (seen.length === 1) {
      return streamResponse(302, { location: "/final?X-Amz-Signature=a%2Fb&part=2" }, []);
    }
    return streamResponse(200, { "content-type": "application/octet-stream" }, [PNG.subarray(0, 3), PNG.subarray(3)]);
  };
  const result = await notion.downloadRemoteImage("https://prod-files-secure.s3.us-west-2.amazonaws.com/start?token=one", {
    lookup: publicLookup,
    transport,
    timeoutMs: 100,
  });
  assert.equal(seen[1], "https://prod-files-secure.s3.us-west-2.amazonaws.com/final?X-Amz-Signature=a%2Fb&part=2");
  assert.equal(result.extension, "png");
  assert.deepEqual(result.data, PNG);
});

test("download rejects MIME/signature mismatch and destroys the body", async () => {
  const body = Readable.from([JPEG]);
  await assert.rejects(
    () => notion.downloadRemoteImage("https://public.example/image.png", {
      lookup: publicLookup,
      transport: async () => ({ statusCode: 200, headers: { "content-type": "image/png" }, body }),
    }),
    /content type|signature|match/i,
  );
  assert.equal(body.destroyed, true);
});

test("download rejects SVG and arbitrary bytes even when MIME claims an image", async (t) => {
  for (const [label, contentType, data] of [
    ["SVG", "image/svg+xml", Buffer.from("<svg/>")],
    ["SVG octet-stream", "application/octet-stream", Buffer.from("<svg/>")],
    ["HTML as PNG", "image/png", Buffer.from("<html></html>")],
    ["arbitrary as JPEG", "image/jpeg", Buffer.from("not jpeg")],
  ]) {
    await t.test(label, async () => {
      await assert.rejects(
        () => notion.downloadRemoteImage("https://public.example/image", {
          lookup: publicLookup,
          transport: async () => streamResponse(200, { "content-type": contentType }, [data]),
        }),
        /unsupported|content type|signature|image/i,
      );
    });
  }
});

test("streamed oversize image aborts the response", async () => {
  const body = Readable.from([PNG, Buffer.alloc(8)]);
  await assert.rejects(
    () => notion.downloadRemoteImage("https://public.example/image", {
      lookup: publicLookup,
      maxBytes: PNG.length,
      transport: async () => ({ statusCode: 200, headers: { "content-type": "image/png" }, body }),
    }),
    /exceeded|large|bytes/i,
  );
  assert.equal(body.destroyed, true);
});

test("25 MiB image limit accepts the boundary and rejects one additional byte", async () => {
  const maxBytes = 25 * 1024 * 1024;
  const largePng = Buffer.alloc(maxBytes);
  PNG.copy(largePng);
  const accepted = await notion.downloadRemoteImage("https://public.example/large", {
    lookup: publicLookup,
    transport: async () => streamResponse(200, { "content-type": "image/png" }, [largePng]),
  });
  assert.equal(accepted.data.length, maxBytes);
  const oversizedBody = Readable.from([largePng, Buffer.from([0])]);
  await assert.rejects(
    () => notion.downloadRemoteImage("https://public.example/too-large", {
      lookup: publicLookup,
      transport: async () => ({ statusCode: 200, headers: { "content-type": "image/png" }, body: oversizedBody }),
    }),
    /exceeded|large|bytes/i,
  );
  assert.equal(oversizedBody.destroyed, true);
});
