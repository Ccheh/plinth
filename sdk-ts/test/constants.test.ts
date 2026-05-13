import { describe, it, expect } from "vitest";
import {
  ARC_TESTNET,
  PLINTH_ARC_TESTNET,
  PLINTH_ABI,
  VaultStatus,
  INCEPTION_NAV,
} from "../src/index.js";

describe("ARC_TESTNET", () => {
  it("canonical chainId + RPC + explorer", () => {
    expect(ARC_TESTNET.chainId).toBe(5042002);
    expect(ARC_TESTNET.rpc).toMatch(/^https:\/\/rpc\.testnet\.arc\.network/);
    expect(ARC_TESTNET.explorer).toMatch(/^https:\/\/testnet\.arcscan\.app/);
  });
});

describe("PLINTH_ARC_TESTNET", () => {
  it("addresses are valid hex", () => {
    expect(PLINTH_ARC_TESTNET.plinth).toMatch(/^0x[0-9a-f]{40}$/);
    expect(PLINTH_ARC_TESTNET.mockVenue1).toMatch(/^0x[0-9a-f]{40}$/);
    expect(PLINTH_ARC_TESTNET.mockVenue2).toMatch(/^0x[0-9a-f]{40}$/);
    expect(PLINTH_ARC_TESTNET.deployTx).toMatch(/^0x[0-9a-f]{64}$/);
  });
  it("plinth, mockVenue1, mockVenue2 are distinct", () => {
    expect(PLINTH_ARC_TESTNET.plinth).not.toBe(PLINTH_ARC_TESTNET.mockVenue1);
    expect(PLINTH_ARC_TESTNET.mockVenue1).not.toBe(PLINTH_ARC_TESTNET.mockVenue2);
  });
});

describe("VaultStatus", () => {
  it("enum values match Solidity (None=0, Active=1, Paused=2, Closed=3)", () => {
    expect(VaultStatus.None).toBe(0);
    expect(VaultStatus.Active).toBe(1);
    expect(VaultStatus.Paused).toBe(2);
    expect(VaultStatus.Closed).toBe(3);
  });
});

describe("INCEPTION_NAV", () => {
  it("is exactly 1e18 (matches Plinth.sol)", () => {
    expect(INCEPTION_NAV).toBe(10n ** 18n);
  });
});

describe("PLINTH_ABI surface", () => {
  it("exposes the 9 write functions", () => {
    const fns = PLINTH_ABI.filter(e => e.type === "function" && e.stateMutability !== "view").map(e => e.name);
    for (const name of [
      "createVault", "deposit", "redeem", "deployToVenue", "returnFromVenue",
      "reportPnL", "setPaused", "closeVault", "postUnderwriterReview",
    ]) {
      expect(fns).toContain(name);
    }
  });

  it("exposes view helpers", () => {
    const fns = PLINTH_ABI.filter(e => e.type === "function" && e.stateMutability === "view").map(e => e.name);
    for (const name of [
      "vaults", "totalAUM", "nav", "summary", "previewNextVaultId",
      "getApprovedVenues", "sharesOf", "vaultCount",
      "INCEPTION_NAV", "MAX_APPROVED_VENUES", "MIN_DEPOSIT",
    ]) {
      expect(fns).toContain(name);
    }
  });

  it("exposes 9 events", () => {
    const events = PLINTH_ABI.filter(e => e.type === "event").map(e => e.name);
    for (const name of [
      "VaultCreated", "Deposit", "Redeem", "DeployToVenue", "ReturnFromVenue",
      "PnLReported", "VaultPaused", "VaultClosed", "UnderwriterReviewPosted",
    ]) {
      expect(events).toContain(name);
    }
  });
});
