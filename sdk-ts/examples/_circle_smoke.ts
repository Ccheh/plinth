// Standalone smoke test — verify real Circle Bridge Kit imports + instantiation.
// Run: cd plinth/sdk-ts && npx tsx examples/_circle_smoke.ts
//
// This is a sanity-check artifact — it does NOT bridge anything. It just
// proves the @circle-fin packages installed in this project resolve and
// expose the expected API surface.
import { createRequire } from "node:module";
import { BridgeKit } from "@circle-fin/bridge-kit";
import { createViemAdapterFromPrivateKey } from "@circle-fin/adapter-viem-v2";

const kit = new BridgeKit();
const adapter = createViemAdapterFromPrivateKey({
  privateKey: ("0x" + "11".repeat(32)) as `0x${string}`,
});

// Report the versions actually resolved on disk rather than hardcoded strings,
// so this output can never drift out of date after a dependency bump.
const require = createRequire(import.meta.url);
const version = (pkg: string): string => {
  try { return "v" + require(`${pkg}/package.json`).version; }
  catch { return "(not resolvable)"; }
};

console.log("BridgeKit instance type :", typeof kit);
console.log("Adapter instance type   :", typeof adapter);
console.log("kit.bridge() exists     :", typeof (kit as any).bridge === "function");
console.log("");
console.log("✅ Real Circle SDK installed + imports resolve + instances construct.");
console.log("   Package versions (resolved at runtime):");
console.log("     @circle-fin/bridge-kit       ", version("@circle-fin/bridge-kit"));
console.log("     @circle-fin/adapter-viem-v2  ", version("@circle-fin/adapter-viem-v2"));
console.log("     @circle-fin/provider-cctp-v2 ", version("@circle-fin/provider-cctp-v2"), "(transitive, via bridge-kit)");
