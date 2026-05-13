import { encodeAbiParameters, keccak256, type Hex } from "viem";
import { INCEPTION_NAV } from "./constants.js";

/**
 * Match on-chain `vaultId = keccak256(abi.encode(agent, vaultCount, chainId))`
 * exactly. Useful for pre-computing the vaultId of a not-yet-submitted
 * createVault tx — caller passes `currentVaultCount + 1`.
 */
export function deriveVaultId(agent: Hex, vaultCount: bigint, chainId: number | bigint): Hex {
  return keccak256(
    encodeAbiParameters(
      [{ type: "address" }, { type: "uint256" }, { type: "uint256" }],
      [agent, vaultCount, BigInt(chainId)],
    ),
  );
}

/**
 * Compute NAV from raw vault accounting state.
 *  totalAUM = inVault + deployedAUM + reportedPnL  (signed)
 *  NAV      = totalShares == 0 ? 1e18 : (totalAUM * 1e18) / totalShares
 *  underwater (totalAUM <= 0) returns 0n
 */
export function computeNav(
  inVault: bigint,
  deployedAUM: bigint,
  reportedPnL: bigint,
  totalShares: bigint,
): bigint {
  if (totalShares === 0n) return INCEPTION_NAV;
  const totalAUM = inVault + deployedAUM + reportedPnL;
  if (totalAUM <= 0n) return 0n;
  return (totalAUM * INCEPTION_NAV) / totalShares;
}

/**
 * USDC → shares at a given NAV (matches `Plinth.deposit`).
 */
export function sharesForDeposit(usdcWei: bigint, navWei: bigint): bigint {
  if (navWei === 0n) throw new Error("NAV is zero — vault is underwater, deposit would mint infinite shares");
  return (usdcWei * INCEPTION_NAV) / navWei;
}

/**
 * shares → USDC at a given NAV (matches `Plinth.redeem`).
 */
export function usdcForRedeem(shares: bigint, navWei: bigint): bigint {
  return (shares * navWei) / INCEPTION_NAV;
}

/** Format a USDC wei amount (18 decimals) to a fixed-decimal string. */
export function formatUsdc(wei: bigint, decimals: number = 6): string {
  const negative = wei < 0n;
  const abs = negative ? -wei : wei;
  const whole = abs / (10n ** 18n);
  const frac = abs % (10n ** 18n);
  let fracStr = frac.toString().padStart(18, "0").slice(0, decimals);
  // strip trailing zeros for readability
  fracStr = fracStr.replace(/0+$/, "");
  return `${negative ? "-" : ""}${whole}${fracStr ? "." + fracStr : ""}`;
}
