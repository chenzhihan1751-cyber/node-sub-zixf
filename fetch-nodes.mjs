#!/usr/bin/env node
/**
 * fetch-nodes.mjs —— 免费节点订阅聚合器（零第三方依赖，Node 18+）
 *
 * 流程：读 sources.txt → 并发抓取 → 自动识别 base64/明文 → 清洗广告节点
 *      → 按 (协议+服务器+端口+凭据) 去重 → 可选 TCP 连通性检测 → 输出订阅文件
 *
 * 产出：
 *   sub/v2ray.txt    明文节点列表
 *   sub/base64.txt   base64 订阅（v2rayN 导入这个）
 *   sub/stats.json   本次抓取统计
 *
 * 可选：同时设置 GIST_ID 与 GH_TOKEN 环境变量时，顺手把订阅同步到该 gist。
 * 环境变量开关：TCP_CHECK=0 关连通性检测；MIN_NODES=20 低于此数认为抓取异常。
 */
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import net from 'node:net';
import path from 'node:path';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT_DIR = path.join(HERE, 'sub');
const SOURCES_FILE = path.join(HERE, 'sources.txt');

const TCP_CHECK = process.env.TCP_CHECK !== '0';
const TCP_TIMEOUT_MS = Number(process.env.TCP_TIMEOUT_MS || 3000);
const TCP_CONCURRENCY = Number(process.env.TCP_CONCURRENCY || 128);
const FETCH_TIMEOUT_MS = Number(process.env.FETCH_TIMEOUT_MS || 20000);
const PER_HOSTPORT_MAX = Number(process.env.PER_HOSTPORT_MAX || 2);
const MIN_NODES = Number(process.env.MIN_NODES || 20);

const UA = 'Mozilla/5.0 (compatible; node-sub-aggregator/1.0; +https://github.com)';
const SCHEME_RE = /^(vmess|vless|trojan|ss|ssr|hysteria2?|hy2|tuic):\/\//i;

// 广告 / 通知 / 到期提醒类假节点（这类 remark 的"节点"连不上，属于机场引流信息）
const JUNK_RE = new RegExp(
  [
    '剩余流量', '流量', '到期', '过期', '官网', '订阅', '购买', '续费', '机场', '邀请',
    '注册', '试用', '广告', '加群', '客服', '通知', '禁止', '贩卖', '跑路', '白嫖',
    '优惠', '折扣', '套餐', '付费', '重置', '过期时间', 'tg频道', 'telegram', 't\\.me',
  ].join('|'),
  'i',
);

const stats = {
  updated: new Date().toISOString(),
  sources: [],
  raw: 0,
  junk: 0,
  badHost: 0,
  duplicate: 0,
  hostCap: 0,
  dead: 0,
  total: 0,
  byProtocol: {},
};

// ---------- 工具 ----------

function b64decode(input) {
  const t = String(input).replace(/-/g, '+').replace(/_/g, '/').replace(/\s+/g, '');
  if (!t) return '';
  const pad = t + '='.repeat((4 - (t.length % 4)) % 4);
  return Buffer.from(pad, 'base64').toString('utf8');
}

/** 内容看起来是 base64 订阅就解码，否则原样返回 */
function maybeDecode(text) {
  const trimmed = text.trim();
  if (SCHEME_RE.test(trimmed)) return trimmed;
  if (/:\/\//.test(trimmed.slice(0, 300))) return trimmed; // 已经是明文列表
  if (!/^[A-Za-z0-9+/=_\s-]+$/.test(trimmed.slice(0, 2000))) return trimmed;
  const decoded = b64decode(trimmed);
  return decoded.includes('://') ? decoded : trimmed;
}

function remarkOf(uri, hash) {
  const raw = hash ? decodeURIComponent(hash.slice(1)) : '';
  return raw.trim();
}

function badHost(host) {
  if (!host) return false;
  const h = String(host).toLowerCase().replace(/^\[|\]$/g, '');
  if (!h) return true;
  if (['localhost', 'example.com', '0.0.0.0', '::1', '1.1.1.1', '8.8.8.8', '::'].includes(h)) return true;
  if (/^(127|10)\./.test(h)) return true;
  if (/^192\.168\./.test(h)) return true;
  if (/^172\.(1[6-9]|2\d|3[01])\./.test(h)) return true;
  if (/^169\.254\./.test(h)) return true;
  if (/^0\./.test(h)) return true;
  if (/\.(local|localhost|internal|test|invalid|example)$/i.test(h)) return true;
  return false;
}

/** 解析出 {key, host, port, remark}，解析失败则 key 用整条 uri */
function parseNode(uri) {
  const scheme = (uri.split('://')[0] || '').toLowerCase();
  const noHash = uri.split('#')[0];
  const result = { protocol: scheme, host: '', port: 0, remark: '', key: noHash };

  try {
    if (scheme === 'vmess') {
      const obj = JSON.parse(b64decode(uri.slice('vmess://'.length)));
      result.host = String(obj.add || '').trim();
      result.port = Number(obj.port) || 0;
      result.remark = String(obj.ps || '').trim();
      result.key = `vmess|${result.host}|${result.port}|${obj.id || ''}`;
      return result;
    }
    if (scheme === 'ssr') {
      const decoded = b64decode(uri.slice('ssr://'.length));
      const parts = decoded.split(':');
      result.host = parts[0] || '';
      result.port = Number(parts[1]) || 0;
      const q = decoded.split('/?')[1] || '';
      const m = /remarks=([^&]+)/.exec(q);
      if (m) result.remark = b64decode(m[1]);
      result.key = `ssr|${result.host}|${result.port}|${(parts.slice(2, 6).join(':') || '')}`;
      return result;
    }
    // vless / trojan / hysteria2 / hy2 / tuic / ss(SIP002)
    const url = new URL(uri);
    if (url.hostname) {
      result.host = url.hostname;
      result.port = Number(url.port || (url.protocol === 'https:' ? 443 : 0));
      result.remark = remarkOf(uri, url.hash);
      const id = url.searchParams.get('id') || url.searchParams.get('auth') || url.username || '';
      result.key = `${scheme}|${result.host}|${result.port}|${id}`;
      return result;
    }
  } catch {
    /* 继续走兜底 */
  }

  // 兜底：从字符串里抠 host:port
  const text = scheme === 'ss' || scheme === 'vmess' ? uri.replace(/^[a-z0-9]+:\/\//i, '') : uri;
  const m = /@?([A-Za-z0-9._-]+):(\d{2,5})/.exec(text);
  if (m) {
    result.host = m[1];
    result.port = Number(m[2]) || 0;
  }
  result.remark = remarkOf(uri, uri.includes('#') ? uri.slice(uri.indexOf('#')) : '');
  result.key = noHash;
  return result;
}

function fetchWithTimeout(url, ms) {
  return fetch(url, {
    headers: { 'User-Agent': UA, Accept: '*/*' },
    signal: AbortSignal.timeout(ms),
    redirect: 'follow',
  });
}

/** 直连失败时的镜像候选（GitHub Actions 在美国，基本用不到；本机在国内很有用） */
function mirrorUrls(url) {
  const list = [url];
  const m = /^https:\/\/raw\.githubusercontent\.com\/([^/]+)\/([^/]+)\/([^/]+)\/(.+)$/.exec(url);
  if (m) {
    const [, owner, repo, branch, file] = m;
    const raw = `${owner}/${repo}/${branch}/${file}`;
    list.push(`https://raw.gitmirror.com/${raw}`);
    list.push(`https://ghproxy.net/https://raw.githubusercontent.com/${raw}`);
    list.push(`https://gh-proxy.com/https://raw.githubusercontent.com/${raw}`);
    list.push(`https://cdn.jsdelivr.net/gh/${owner}/${repo}@${branch}/${file}`);
  }
  return list;
}

function describeError(err) {
  return err?.cause?.code || err?.cause?.message || err?.message || String(err);
}

async function fetchSource(url, attempts = 3) {
  const candidates = mirrorUrls(url);
  const errors = [];
  for (const candidate of candidates) {
    for (let i = 1; i <= attempts; i++) {
      try {
        const res = await fetchWithTimeout(candidate, FETCH_TIMEOUT_MS);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const text = await res.text();
        if (!text.trim()) throw new Error('空响应');
        return { text: maybeDecode(text), bytes: text.length, via: candidate };
      } catch (err) {
        const msg = describeError(err);
        errors.push(`${candidate === url ? '' : '[镜像] '}${candidate} → ${msg}`);
        if (i < attempts) await new Promise((r) => setTimeout(r, 800 * i));
      }
    }
  }
  throw new Error([...new Set(errors)].slice(0, 4).join(' ; '));
}

function tcpCheck(host, port) {
  return new Promise((resolve) => {
    let done = false;
    const finish = (ok) => {
      if (done) return;
      done = true;
      try { socket.destroy(); } catch { /* ignore */ }
      resolve(ok);
    };
    const socket = net.connect({ host, port });
    socket.setTimeout(TCP_TIMEOUT_MS);
    socket.once('connect', () => finish(true));
    socket.once('timeout', () => finish(false));
    socket.once('error', () => finish(false));
  });
}

async function filterAlive(nodes, concurrency) {
  const alive = [];
  let index = 0;
  const workers = Array.from({ length: Math.min(concurrency, nodes.length || 1) }, async () => {
    while (index < nodes.length) {
      const node = nodes[index++];
      if (!node.host || !node.port || node.port < 1 || node.port > 65535) {
        alive.push(node);
        continue;
      }
      if (await tcpCheck(node.host, node.port)) alive.push(node);
    }
  });
  await Promise.all(workers);
  return alive;
}

// ---------- 主流程 ----------

function readSources() {
  if (!existsSync(SOURCES_FILE)) throw new Error(`找不到 ${SOURCES_FILE}`);
  return readFileSync(SOURCES_FILE, 'utf8')
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('#'));
}

async function main() {
  const sources = readSources();
  const seen = new Set();
  const perHostPort = new Map();
  const collected = [];

  for (const url of sources) {
    try {
      const { text, bytes, via } = await fetchSource(url);
      const lines = text.split(/\r?\n/).map((l) => l.trim()).filter((l) => SCHEME_RE.test(l));
      let kept = 0;
      for (const uri of lines) {
        stats.raw++;
        const node = parseNode(uri);
        node.uri = uri;
        if (node.remark && JUNK_RE.test(node.remark)) { stats.junk++; continue; }
        if (badHost(node.host)) { stats.badHost++; continue; }
        if (seen.has(node.key)) { stats.duplicate++; continue; }
        seen.add(node.key);
        const hp = `${node.host}:${node.port}`;
        const n = (perHostPort.get(hp) || 0) + 1;
        if (n > PER_HOSTPORT_MAX) { stats.hostCap++; continue; }
        perHostPort.set(hp, n);
        collected.push(node);
        kept++;
      }
      stats.sources.push({ url, ok: true, bytes, lines: lines.length, kept, via });
      console.log(`[ok]   ${kept.toString().padStart(5)} / ${lines.length.toString().padStart(5)}  ${url}${via === url ? '' : `  (via ${new URL(via).host})`}`);
    } catch (err) {
      stats.sources.push({ url, ok: false, error: String(err?.message || err) });
      console.log(`[FAIL] ${url}\n        ${err?.message || err}`);
    }
  }

  let nodes = collected;
  if (TCP_CHECK) {
    const before = nodes.length;
    nodes = await filterAlive(nodes, TCP_CONCURRENCY);
    stats.dead = before - nodes.length;
    console.log(`\nTCP 检测：${before} → ${nodes.length}（剔除 ${stats.dead}）`);
  }

  // 兜底：检测后太少就退回未检测的结果，避免把订阅清空
  if (nodes.length < MIN_NODES && collected.length >= MIN_NODES) {
    console.log(`存活数 ${nodes.length} 低于 ${MIN_NODES}，退回未检测结果 ${collected.length}`);
    stats.dead = 0;
    nodes = collected;
  }
  if (nodes.length < MIN_NODES) {
    throw new Error(`有效节点只有 ${nodes.length} 个，低于 ${MIN_NODES}，判定为抓取异常（保留上一版）`);
  }

  for (const node of nodes) {
    stats.byProtocol[node.protocol] = (stats.byProtocol[node.protocol] || 0) + 1;
  }
  stats.total = nodes.length;

  const lines = nodes.map((n) => n.uri);
  const plain = lines.join('\n') + '\n';
  const base64 = Buffer.from(plain, 'utf8').toString('base64');

  mkdirSync(OUT_DIR, { recursive: true });
  writeFileSync(path.join(OUT_DIR, 'v2ray.txt'), plain, 'utf8');
  writeFileSync(path.join(OUT_DIR, 'base64.txt'), base64 + '\n', 'utf8');
  writeFileSync(path.join(OUT_DIR, 'stats.json'), JSON.stringify(stats, null, 2) + '\n', 'utf8');

  // 可选：同步到 gist（v2rayN 需要公开可读的订阅地址时用）
  const gistId = process.env.GIST_ID;
  const ghToken = process.env.GH_TOKEN;
  if (gistId && ghToken) {
    const file = process.env.GIST_FILE || 'v2ray-base64.txt';
    const res = await fetch(`https://api.github.com/gists/${gistId}`, {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${ghToken}`,
        Accept: 'application/vnd.github+json',
        'Content-Type': 'application/json',
        'User-Agent': UA,
      },
      body: JSON.stringify({ files: { [file]: { content: base64 } } }),
    });
    if (!res.ok) {
      console.log(`[warn] gist 同步失败：HTTP ${res.status} ${(await res.text()).slice(0, 200)}`);
    } else {
      console.log(`[ok]   已同步到 gist ${gistId} (${file})`);
    }
  }

  console.log(`\n总计 ${stats.total} 个节点：`);
  for (const [k, v] of Object.entries(stats.byProtocol).sort((a, b) => b[1] - a[1])) {
    console.log(`  ${k.padEnd(10)} ${v}`);
  }
  console.log(`\n输出目录 ${OUT_DIR}`);
}

main().catch((err) => {
  console.error(`\n[ERROR] ${err?.message || err}`);
  process.exit(1);
});
