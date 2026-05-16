/**
 * Portable .env loader for sdk-ts/examples/*.ts
 *
 * Searches for a `.env` file in (in order):
 *   1. The directory you ran `tsx` from (CWD)
 *   2. sdk-ts/ (one level up from examples/)
 *   3. Repo root (two levels up from examples/)
 *
 * Falls through silently if no .env is found — assume env vars are set in
 * the shell (CI pipelines, secrets managers, etc.).
 *
 * Why this exists: examples used to hardcode `process.loadEnvFile("D:\\桌面\\arc\\.env")`
 * which broke for everyone except the original author. Anyone cloning the
 * repo and running `npm run demo` would crash with ENOENT. This helper
 * is platform-portable and CWD-agnostic.
 *
 * Usage in any example file (must be the FIRST import):
 *
 *   import "./_load-env.js";
 *   const AGENT_PK = process.env.PRIVATE_KEY as `0x${string}`;
 *
 * To use: copy `.env.example` at the repo root to `.env` and fill in keys.
 */
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));

const candidates = [
  resolve(process.cwd(), ".env"),
  resolve(here, "..", ".env"),         // sdk-ts/.env
  resolve(here, "..", "..", ".env"),   // <repo-root>/.env
];

let loadedFrom: string | null = null;
for (const path of candidates) {
  try {
    process.loadEnvFile(path);
    loadedFrom = path;
    break;
  } catch {
    // try next candidate
  }
}

if (process.env.PLINTH_VERBOSE_ENV === "1") {
  if (loadedFrom) {
    console.log(`[env] loaded from ${loadedFrom}`);
  } else {
    console.log(`[env] no .env file found in any of: ${candidates.join(", ")} — relying on shell env`);
  }
}
