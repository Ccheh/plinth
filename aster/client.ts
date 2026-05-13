/**
 * Aster Pro V3 signed-request client for Plinth.
 *
 * Aster v3 is built on Aster L1 (chainId 1666). Authentication is EIP-712
 * typed-data signing by an "API wallet" (a.k.a. signer / agent / proxy
 * wallet) that the master account has on-chain delegated trading rights to.
 *
 *   1. Build params + add { nonce: microseconds, signer: <api wallet> }
 *   2. URL-encode the resulting dict
 *   3. Sign that string as the `msg` field of an EIP-712 typed payload
 *      under domain { name: "AsterSignTransaction", version: "1",
 *      chainId: 1666, verifyingContract: 0x0 }
 *   4. Append `signature` to the dict
 *   5. GET → send as query string; POST → send as form-encoded body
 *
 * NOTE: `user` (master account address) is NOT sent — the signer alone is
 * sufficient because Aster L1 stores the delegation on-chain. The docs claim
 * `user` is part of the payload, but the working reference implementation
 * (D:\桌面\aster策略\v17_futures.py) confirms it isn't.
 */
import { privateKeyToAccount } from "viem/accounts";
import { spawn } from "node:child_process";
import type { Hex } from "viem";

/**
 * HTTP transport via system `curl`. Aster's mainnet edge rejects Node 24's
 * default TLS handshake (ECONNRESET on otherwise valid requests), but accepts
 * curl/Schannel. Spawning curl is uglier than fetch() but matches what works
 * in the reference Python client.
 */
function curlRequest(
  url: string,
  opts: { method: string; headers: Record<string, string>; body?: string },
): Promise<{ status: number; body: string }> {
  return new Promise((resolve, reject) => {
    const args = ["-sS", "--max-time", "20", "-X", opts.method];
    for (const [k, v] of Object.entries(opts.headers)) {
      args.push("-H", `${k}: ${v}`);
    }
    if (opts.body !== undefined) {
      args.push("--data-binary", opts.body);
    }
    // Write status code separately so we can distinguish HTTP errors from body
    args.push("-w", "\n__STATUS__%{http_code}");
    args.push(url);

    const child = spawn("curl", args, { windowsHide: true });
    let out = "";
    let err = "";
    child.stdout.on("data", (c) => (out += c));
    child.stderr.on("data", (c) => (err += c));
    child.on("error", reject);
    child.on("close", (code) => {
      if (code !== 0) return reject(new Error(`curl exited ${code}: ${err}`));
      const marker = out.lastIndexOf("\n__STATUS__");
      const status = marker >= 0 ? parseInt(out.slice(marker + "\n__STATUS__".length), 10) : 0;
      const body = marker >= 0 ? out.slice(0, marker) : out;
      resolve({ status, body });
    });
  });
}

export type AsterConfig = {
  baseUrl: string;       // https://fapi.asterdex.com (mainnet) — Aster L1 endpoint
  signer: Hex;           // API wallet address (a.k.a. agent / proxy)
  privateKey: Hex;       // API wallet private key
  user?: Hex;            // OPTIONAL: master account address; not used in API calls
                         //   but kept for Underwriter-side trade verification
};

const DOMAIN = {
  name: "AsterSignTransaction",
  version: "1",
  chainId: 1666,         // Aster L1, NOT 714 (docs are wrong)
  verifyingContract: "0x0000000000000000000000000000000000000000" as Hex,
} as const;

const TYPES = {
  Message: [{ name: "msg", type: "string" }],
} as const;

let _lastSec = 0;
let _i = 0;
function nonceMicros(): bigint {
  // Mirror the Python reference: seconds * 1_000_000 + monotonic counter
  // (per-second nonce uniqueness; server enforces ±10s server-time delta).
  const nowSec = Math.floor(Date.now() / 1000);
  if (nowSec === _lastSec) {
    _i += 1;
  } else {
    _lastSec = nowSec;
    _i = 0;
  }
  return BigInt(nowSec) * 1_000_000n + BigInt(_i);
}

function urlEncode(params: Record<string, string | number>): string {
  // Preserve insertion order — Python's urlencode default and Aster's
  // server-side signature recomputation both rely on this.
  const parts: string[] = [];
  for (const [k, v] of Object.entries(params)) {
    parts.push(`${encodeURIComponent(k)}=${encodeURIComponent(String(v))}`);
  }
  return parts.join("&");
}

export class AsterClient {
  private cfg: AsterConfig;
  private account: ReturnType<typeof privateKeyToAccount>;

  constructor(cfg: AsterConfig) {
    this.cfg = cfg;
    this.account = privateKeyToAccount(cfg.privateKey);
    if (this.account.address.toLowerCase() !== cfg.signer.toLowerCase()) {
      throw new Error(
        `Signer mismatch: privateKey derives ${this.account.address}, but cfg.signer is ${cfg.signer}`,
      );
    }
  }

  async signedRequest<T = any>(
    path: string,
    method: "GET" | "POST" | "DELETE",
    params: Record<string, string | number> = {},
  ): Promise<T> {
    // Build signed payload — only nonce + signer + business params get signed
    const enriched: Record<string, string | number> = {
      ...params,
      nonce: String(nonceMicros()),
      signer: this.cfg.signer,
    };
    const paramString = urlEncode(enriched);

    const signature = await this.account.signTypedData({
      domain: DOMAIN,
      types: TYPES,
      primaryType: "Message",
      message: { msg: paramString },
    });

    const headers = {
      "Content-Type": "application/x-www-form-urlencoded",
      "User-Agent": "PlinthAsterBridge/0.0.1",
    };

    let url: string;
    let body: string | undefined;
    if (method === "GET" || method === "DELETE") {
      url = `${this.cfg.baseUrl}${path}?${paramString}&signature=${signature}`;
      body = undefined;
    } else {
      url = `${this.cfg.baseUrl}${path}`;
      body = `${paramString}&signature=${signature}`;
    }

    const res = await curlRequest(url, { method, headers, body });
    if (res.status < 200 || res.status >= 300) {
      throw new Error(`Aster ${method} ${path} → HTTP ${res.status}: ${res.body}`);
    }
    try {
      return JSON.parse(res.body) as T;
    } catch {
      return res.body as unknown as T;
    }
  }

  // ---- public market data (no signature) ----

  async serverTime(): Promise<{ serverTime: number }> {
    const r = await curlRequest(`${this.cfg.baseUrl}/fapi/v3/time`, { method: "GET", headers: {} });
    if (r.status !== 200) throw new Error(`/fapi/v3/time HTTP ${r.status}: ${r.body}`);
    return JSON.parse(r.body);
  }

  async price(symbol: string): Promise<{ symbol: string; price: string }> {
    const r = await curlRequest(`${this.cfg.baseUrl}/fapi/v3/ticker/price?symbol=${symbol}`, {
      method: "GET",
      headers: {},
    });
    if (r.status !== 200) throw new Error(`/fapi/v3/ticker/price HTTP ${r.status}: ${r.body}`);
    return JSON.parse(r.body);
  }

  async premiumIndex(symbol: string): Promise<any> {
    const r = await curlRequest(`${this.cfg.baseUrl}/fapi/v3/premiumIndex?symbol=${symbol}`, {
      method: "GET",
      headers: {},
    });
    if (r.status !== 200) throw new Error(`/fapi/v3/premiumIndex HTTP ${r.status}: ${r.body}`);
    return JSON.parse(r.body);
  }

  // ---- authenticated reads ----

  async getBalance(): Promise<
    Array<{ asset: string; balance: string; availableBalance: string; crossUnPnl: string }>
  > {
    return this.signedRequest("/fapi/v3/balance", "GET");
  }

  async getAccountWithPositions(): Promise<any> {
    return this.signedRequest("/fapi/v3/accountWithJoinMargin", "GET");
  }

  async getUserTrades(symbol: string, limit = 50): Promise<any[]> {
    return this.signedRequest("/fapi/v3/userTrades", "GET", { symbol, limit });
  }

  // ---- writes (used in demo-trade) ----

  async setLeverage(symbol: string, leverage: number): Promise<any> {
    return this.signedRequest("/fapi/v3/leverage", "POST", { symbol, leverage });
  }

  async setMarginType(symbol: string, marginType: "ISOLATED" | "CROSSED"): Promise<any> {
    return this.signedRequest("/fapi/v3/marginType", "POST", { symbol, marginType });
  }

  async placeMarketOrder(args: {
    symbol: string;
    side: "BUY" | "SELL";
    quantity: string;
    reduceOnly?: boolean;
    positionSide?: "LONG" | "SHORT" | "BOTH";  // required if account is in hedge mode
  }): Promise<any> {
    return this.signedRequest("/fapi/v3/order", "POST", {
      symbol: args.symbol,
      side: args.side,
      type: "MARKET",
      quantity: args.quantity,
      ...(args.positionSide ? { positionSide: args.positionSide } : {}),
      // Note: with positionSide=LONG/SHORT in hedge mode, reduceOnly is implicit
      // (closing happens via opposite side on same positionSide). Aster rejects
      // reduceOnly when positionSide is set, so omit it in hedge mode.
      ...(args.reduceOnly && !args.positionSide ? { reduceOnly: "true" } : {}),
    });
  }
}
