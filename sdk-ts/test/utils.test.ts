import { describe, it, expect } from "vitest";
import { encodeAbiParameters, keccak256, type Hex } from "viem";
import {
  deriveVaultId,
  computeNav,
  sharesForDeposit,
  usdcForRedeem,
  formatUsdc,
  INCEPTION_NAV,
} from "../src/index.js";

const AGENT: Hex = "0x1234567890abcdef1234567890abcdef12345678";
const OTHER: Hex = "0x9999999999999999999999999999999999999999";

describe("deriveVaultId", () => {
  it("matches on-chain keccak256(abi.encode(agent, count, chainId))", () => {
    const expected = keccak256(
      encodeAbiParameters(
        [{ type: "address" }, { type: "uint256" }, { type: "uint256" }],
        [AGENT, 3n, 5042002n],
      ),
    );
    expect(deriveVaultId(AGENT, 3n, 5042002)).toBe(expected);
  });

  it("is deterministic", () => {
    expect(deriveVaultId(AGENT, 1n, 5042002)).toBe(deriveVaultId(AGENT, 1n, 5042002));
  });

  it("differs across agent / count / chain", () => {
    expect(deriveVaultId(AGENT, 1n, 5042002)).not.toBe(deriveVaultId(OTHER, 1n, 5042002));
    expect(deriveVaultId(AGENT, 1n, 5042002)).not.toBe(deriveVaultId(AGENT, 2n, 5042002));
    expect(deriveVaultId(AGENT, 1n, 5042002)).not.toBe(deriveVaultId(AGENT, 1n, 1));
  });

  it("accepts chainId as number or bigint", () => {
    expect(deriveVaultId(AGENT, 1n, 5042002n)).toBe(deriveVaultId(AGENT, 1n, 5042002));
  });
});

describe("computeNav", () => {
  it("returns INCEPTION_NAV when totalShares is 0", () => {
    expect(computeNav(0n, 0n, 0n, 0n)).toBe(INCEPTION_NAV);
    expect(computeNav(1000n, 500n, 100n, 0n)).toBe(INCEPTION_NAV);
  });

  it("returns 0 when underwater (totalAUM <= 0)", () => {
    expect(computeNav(1n * INCEPTION_NAV, 0n, -2n * INCEPTION_NAV, 1n * INCEPTION_NAV)).toBe(0n);
    expect(computeNav(0n, 0n, -1n, 1n * INCEPTION_NAV)).toBe(0n);
    expect(computeNav(1n * INCEPTION_NAV, 0n, -1n * INCEPTION_NAV, 1n * INCEPTION_NAV)).toBe(0n);  // exactly 0 totalAUM
  });

  it("inception NAV for fresh vault is exactly 1e18", () => {
    expect(computeNav(1n * INCEPTION_NAV, 0n, 0n, 1n * INCEPTION_NAV)).toBe(INCEPTION_NAV);
  });

  it("+50% reportedPnL on $1 AUM with 1 share doubles to 1.5 NAV", () => {
    const nav = computeNav(1n * INCEPTION_NAV, 0n, INCEPTION_NAV / 2n, 1n * INCEPTION_NAV);
    expect(nav).toBe(INCEPTION_NAV * 3n / 2n);
  });

  it("-50% reportedPnL halves NAV", () => {
    const nav = computeNav(1n * INCEPTION_NAV, 0n, -INCEPTION_NAV / 2n, 1n * INCEPTION_NAV);
    expect(nav).toBe(INCEPTION_NAV / 2n);
  });

  it("handles deployedAUM in totalAUM computation", () => {
    // inVault 0.4, deployed 0.6, pnl 0, totalShares 1 → AUM 1, NAV 1
    const nav = computeNav(
      4n * INCEPTION_NAV / 10n,
      6n * INCEPTION_NAV / 10n,
      0n,
      INCEPTION_NAV,
    );
    expect(nav).toBe(INCEPTION_NAV);
  });
});

describe("sharesForDeposit", () => {
  it("at inception NAV, $1 mints exactly 1 share", () => {
    expect(sharesForDeposit(INCEPTION_NAV, INCEPTION_NAV)).toBe(INCEPTION_NAV);
  });

  it("at NAV=2, $1 mints 0.5 shares", () => {
    expect(sharesForDeposit(INCEPTION_NAV, 2n * INCEPTION_NAV)).toBe(INCEPTION_NAV / 2n);
  });

  it("at NAV=0.5, $1 mints 2 shares", () => {
    expect(sharesForDeposit(INCEPTION_NAV, INCEPTION_NAV / 2n)).toBe(2n * INCEPTION_NAV);
  });

  it("throws when NAV is 0 (underwater)", () => {
    expect(() => sharesForDeposit(INCEPTION_NAV, 0n)).toThrow();
  });
});

describe("usdcForRedeem", () => {
  it("at inception NAV, burning 1 share returns $1", () => {
    expect(usdcForRedeem(INCEPTION_NAV, INCEPTION_NAV)).toBe(INCEPTION_NAV);
  });

  it("at NAV=1.5, burning 1 share returns $1.5", () => {
    expect(usdcForRedeem(INCEPTION_NAV, 3n * INCEPTION_NAV / 2n)).toBe(3n * INCEPTION_NAV / 2n);
  });

  it("at NAV=0.5, burning 1 share returns $0.5", () => {
    expect(usdcForRedeem(INCEPTION_NAV, INCEPTION_NAV / 2n)).toBe(INCEPTION_NAV / 2n);
  });
});

describe("formatUsdc", () => {
  it("formats whole-number wei to USDC", () => {
    expect(formatUsdc(INCEPTION_NAV)).toBe("1");
    expect(formatUsdc(5n * INCEPTION_NAV)).toBe("5");
  });

  it("formats fractional with 6 decimal default + trailing-zero strip", () => {
    expect(formatUsdc(INCEPTION_NAV / 2n)).toBe("0.5");
    expect(formatUsdc(INCEPTION_NAV / 4n)).toBe("0.25");
  });

  it("formats negative correctly", () => {
    expect(formatUsdc(-INCEPTION_NAV)).toBe("-1");
    expect(formatUsdc(-INCEPTION_NAV / 2n)).toBe("-0.5");
  });

  it("custom decimals parameter", () => {
    expect(formatUsdc(INCEPTION_NAV / 3n, 4)).toBe("0.3333");
  });
});
