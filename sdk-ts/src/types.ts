export type Hex = `0x${string}`;

/** Snapshot of an on-chain Vault. */
export interface VaultState {
  agent: Hex;
  createdAt: bigint;
  status: number;               // 0 None / 1 Active / 2 Paused / 3 Closed
  totalShares: bigint;
  inVault: bigint;
  deployedAUM: bigint;
  reportedPnL: bigint;           // signed
  strategyDescriptor: string;
}

export interface VaultSummary {
  totalShares: bigint;
  inVault: bigint;
  deployedAUM: bigint;
  reportedPnL: bigint;
}

export interface CreateVaultParams {
  approvedVenues: Hex[];
  strategyDescriptor: string;
  initialDepositWei: bigint;
}
