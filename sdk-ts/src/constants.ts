import type { Hex } from "./types.js";

export interface ArcChain {
  chainId: number;
  rpc: string;
  explorer: string;
}

export const ARC_TESTNET: ArcChain = {
  chainId: 5042002,
  rpc: "https://rpc.testnet.arc.network",
  explorer: "https://testnet.arcscan.app",
};

/** Plinth v0 deployment on Arc Testnet.
 *  Historical / demo artifact. Lifecycle reference, 6 vaults, 6 underwriter
 *  reviews. For new vaults, prefer PLINTH_V05_ARC_TESTNET (security-hardened). */
export const PLINTH_ARC_TESTNET = {
  plinth: "0xc2994ce3df612ebd2f898244a992a0bbfef86627" as Hex,
  mockVenue1: "0x50bf887e4957261e7ca0c6b4eeb61ab83ad6ddcd" as Hex,
  mockVenue2: "0xc0f8d26cbf7123b0f5148b9feae6c3234cccda35" as Hex,
  deployTx: "0xe10e704a6b7240095b74518da5e94ae3086237dd71ff05f2fbc52cfd615fe583" as Hex,
} as const;

/** Plinth v0.5 — security-hardened deployment on Arc Testnet.
 *  Closes 6 audit findings vs v0:
 *    #1 sandwich-on-reportPnL → deposit cooldown
 *    #2 returnFromVenue griefing → access control
 *    #3 reportPnL inflation rug → rate limit
 *    #4 reportPnL on Closed vault → rejected
 *    #6 reportPnL magnitude overflow → bounded
 *    #8 strategyDescriptor length → capped
 *  See docs/security-audit.md for the full audit report. */
export const PLINTH_V05_ARC_TESTNET = {
  plinth: "0xba1b087b0ac77b398c250a9fd7e298f3f96addc7" as Hex,
  mockVenue1: "0x50bf887e4957261e7ca0c6b4eeb61ab83ad6ddcd" as Hex,
  mockVenue2: "0xc0f8d26cbf7123b0f5148b9feae6c3234cccda35" as Hex,
  /** Testnet mock for USYC-style T-bill cash-sweep strategy (5% APR).
   *  In production this slot would be the real USYC token on Base, with
   *  Arc Testnet capital bridged via CCTP. */
  mockYieldVenue: "0xe5cceca53ccb15affc58016e1757e1a138ef3144" as Hex,
  yieldVenueDeployTx: "0x8714eb2d72daf7e7d49a1db95a80a78f94f6214669448c841817ca432cb837b9" as Hex,
  /** Bridge wiring PlinthV05 to Mandate v0 (sibling protocol composition).
   *  Enables institutional issuers to authorize agent-mediated deposits
   *  via capability-bound Mandate.execute → Plinth.deposit atomic flow. */
  mandatePlinthBridge: "0x0b92b6e4fa26e6c2b10a5c668d8313a1bf8c3f50" as Hex,
  mandateContract: "0xfBBDAeC05E0061ADeb955896DFF183fdd412E6E4" as Hex,
  bridgeDeployTx: "0x9a7c9f97ef67167d9c2114002da220ec548cb18b524fbe9af221122a48a32057" as Hex,
  deployTx: "0x55bd1dced631429fa86357d54030004feafc91e687863cddd0cddbb489f2a91d" as Hex,
  DEPOSIT_COOLDOWN_SECONDS: 3600,
  MAX_PNL_MULTIPLE: 10n,
  PNL_RATE_PCT: 25n,
  PNL_RATE_WINDOW_SECONDS: 3600,
  MAX_STRATEGY_LEN: 1024,
} as const;

/** Vault lifecycle states; mirrors Plinth.sol's enum. */
export const VaultStatus = { None: 0, Active: 1, Paused: 2, Closed: 3 } as const;
export type VaultStatusName = keyof typeof VaultStatus;

/** NAV inception: 1e18 wei = 1 USDC/share. */
export const INCEPTION_NAV = 10n ** 18n;

export const PLINTH_ABI = [
  // ---- write surface ----
  {
    type: "function", name: "createVault", stateMutability: "payable",
    inputs: [
      { name: "approvedVenues", type: "address[]" },
      { name: "strategyDescriptor", type: "string" },
    ],
    outputs: [{ name: "vaultId", type: "bytes32" }],
  },
  {
    type: "function", name: "deposit", stateMutability: "payable",
    inputs: [{ name: "vaultId", type: "bytes32" }],
    outputs: [{ name: "sharesMinted", type: "uint256" }],
  },
  {
    type: "function", name: "redeem", stateMutability: "nonpayable",
    inputs: [
      { name: "vaultId", type: "bytes32" },
      { name: "shareAmount", type: "uint256" },
    ],
    outputs: [{ name: "usdcOut", type: "uint256" }],
  },
  {
    type: "function", name: "deployToVenue", stateMutability: "nonpayable",
    inputs: [
      { name: "vaultId", type: "bytes32" },
      { name: "venue", type: "address" },
      { name: "amount", type: "uint256" },
    ], outputs: [],
  },
  {
    type: "function", name: "returnFromVenue", stateMutability: "payable",
    inputs: [
      { name: "vaultId", type: "bytes32" },
      { name: "venue", type: "address" },
      { name: "amount", type: "uint256" },
    ], outputs: [],
  },
  {
    type: "function", name: "reportPnL", stateMutability: "nonpayable",
    inputs: [
      { name: "vaultId", type: "bytes32" },
      { name: "newPnL", type: "int256" },
    ], outputs: [],
  },
  {
    type: "function", name: "setPaused", stateMutability: "nonpayable",
    inputs: [
      { name: "vaultId", type: "bytes32" },
      { name: "paused", type: "bool" },
    ], outputs: [],
  },
  {
    type: "function", name: "closeVault", stateMutability: "nonpayable",
    inputs: [{ name: "vaultId", type: "bytes32" }], outputs: [],
  },
  {
    type: "function", name: "postUnderwriterReview", stateMutability: "nonpayable",
    inputs: [
      { name: "vaultId", type: "bytes32" },
      { name: "reviewHash", type: "bytes32" },
      { name: "reviewUri", type: "string" },
    ], outputs: [],
  },

  // ---- views ----
  {
    type: "function", name: "vaults", stateMutability: "view",
    inputs: [{ type: "bytes32" }],
    outputs: [
      { name: "agent", type: "address" },
      { name: "createdAt", type: "uint64" },
      { name: "status", type: "uint8" },
      { name: "totalShares", type: "uint256" },
      { name: "inVault", type: "uint256" },
      { name: "deployedAUM", type: "uint256" },
      { name: "reportedPnL", type: "int256" },
      { name: "strategyDescriptor", type: "string" },
    ],
  },
  {
    type: "function", name: "totalAUM", stateMutability: "view",
    inputs: [{ type: "bytes32" }], outputs: [{ type: "int256" }],
  },
  {
    type: "function", name: "nav", stateMutability: "view",
    inputs: [{ type: "bytes32" }], outputs: [{ type: "uint256" }],
  },
  {
    type: "function", name: "summary", stateMutability: "view",
    inputs: [{ type: "bytes32" }],
    outputs: [
      { name: "totalShares", type: "uint256" },
      { name: "inVault", type: "uint256" },
      { name: "deployedAUM", type: "uint256" },
      { name: "reportedPnL", type: "int256" },
    ],
  },
  {
    type: "function", name: "previewNextVaultId", stateMutability: "view",
    inputs: [{ name: "agent", type: "address" }], outputs: [{ type: "bytes32" }],
  },
  {
    type: "function", name: "getApprovedVenues", stateMutability: "view",
    inputs: [{ type: "bytes32" }], outputs: [{ type: "address[]" }],
  },
  {
    type: "function", name: "sharesOf", stateMutability: "view",
    inputs: [
      { type: "bytes32" }, { type: "address" },
    ], outputs: [{ type: "uint256" }],
  },
  {
    type: "function", name: "vaultCount", stateMutability: "view",
    inputs: [{ type: "address" }], outputs: [{ type: "uint256" }],
  },
  { type: "function", name: "INCEPTION_NAV", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "MAX_APPROVED_VENUES", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "MIN_DEPOSIT", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },

  // ---- events ----
  {
    type: "event", name: "VaultCreated",
    inputs: [
      { indexed: true, name: "vaultId", type: "bytes32" },
      { indexed: true, name: "agent", type: "address" },
      { indexed: false, name: "approvedVenues", type: "address[]" },
      { indexed: false, name: "strategyDescriptor", type: "string" },
      { indexed: false, name: "initialDeposit", type: "uint256" },
    ],
  },
  {
    type: "event", name: "Deposit",
    inputs: [
      { indexed: true, name: "vaultId", type: "bytes32" },
      { indexed: true, name: "investor", type: "address" },
      { indexed: false, name: "usdcIn", type: "uint256" },
      { indexed: false, name: "sharesMinted", type: "uint256" },
      { indexed: false, name: "navAtDeposit", type: "uint256" },
    ],
  },
  {
    type: "event", name: "Redeem",
    inputs: [
      { indexed: true, name: "vaultId", type: "bytes32" },
      { indexed: true, name: "investor", type: "address" },
      { indexed: false, name: "sharesBurned", type: "uint256" },
      { indexed: false, name: "usdcOut", type: "uint256" },
      { indexed: false, name: "navAtRedeem", type: "uint256" },
    ],
  },
  {
    type: "event", name: "DeployToVenue",
    inputs: [
      { indexed: true, name: "vaultId", type: "bytes32" },
      { indexed: true, name: "venue", type: "address" },
      { indexed: false, name: "amount", type: "uint256" },
      { indexed: false, name: "newInVault", type: "uint256" },
      { indexed: false, name: "newDeployedAUM", type: "uint256" },
    ],
  },
  {
    type: "event", name: "ReturnFromVenue",
    inputs: [
      { indexed: true, name: "vaultId", type: "bytes32" },
      { indexed: true, name: "venue", type: "address" },
      { indexed: false, name: "amount", type: "uint256" },
      { indexed: false, name: "newInVault", type: "uint256" },
      { indexed: false, name: "newDeployedAUM", type: "uint256" },
    ],
  },
  {
    type: "event", name: "PnLReported",
    inputs: [
      { indexed: true, name: "vaultId", type: "bytes32" },
      { indexed: false, name: "oldPnL", type: "int256" },
      { indexed: false, name: "newPnL", type: "int256" },
      { indexed: false, name: "totalAUMNow", type: "int256" },
    ],
  },
  {
    type: "event", name: "VaultPaused",
    inputs: [
      { indexed: true, name: "vaultId", type: "bytes32" },
      { indexed: false, name: "paused", type: "bool" },
    ],
  },
  {
    type: "event", name: "VaultClosed",
    inputs: [{ indexed: true, name: "vaultId", type: "bytes32" }],
  },
  {
    type: "event", name: "UnderwriterReviewPosted",
    inputs: [
      { indexed: true, name: "vaultId", type: "bytes32" },
      { indexed: true, name: "underwriter", type: "address" },
      { indexed: false, name: "reviewHash", type: "bytes32" },
      { indexed: false, name: "reviewUri", type: "string" },
    ],
  },
] as const;
