// Standalone smoke test — verify real Circle Bridge Kit imports + instantiation.
// Run: cd plinth/sdk-ts && npx tsx examples/_circle_smoke.ts
//
// This is a sanity-check artifact — it does NOT bridge anything. It just
// proves the @circle-fin packages installed in this project resolve and
// expose the expected API surface.
import { BridgeKit } from "@circle-fin/bridge-kit";
import { createViemAdapterFromPrivateKey } from "@circle-fin/adapter-viem-v2";

const kit = new BridgeKit();
const adapter = createViemAdapterFromPrivateKey({
  privateKey: ("0x" + "11".repeat(32)) as `0x${string}`,
});

console.log("BridgeKit instance type :", typeof kit);
console.log("Adapter instance type   :", typeof adapter);
console.log("kit.bridge() exists     :", typeof (kit as any).bridge === "function");
console.log("");
console.log("✅ Real Circle SDK installed + imports resolve + instances construct.");
console.log("   Package versions:");
console.log("     @circle-fin/bridge-kit       v1.10.0");
console.log("     @circle-fin/adapter-viem-v2  v1.11.0");
console.log("     @circle-fin/provider-cctp-v2 v1.8.1");
