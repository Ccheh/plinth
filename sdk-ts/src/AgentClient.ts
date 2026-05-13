import {
  createPublicClient,
  createWalletClient,
  defineChain,
  http,
  decodeEventLog,
  type PublicClient,
  type WalletClient,
  type Account,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { ARC_TESTNET, PLINTH_ABI, type ArcChain } from "./constants.js";
import type { Hex, CreateVaultParams, VaultState } from "./types.js";
import { deriveVaultId } from "./utils.js";

export interface AgentClientOptions {
  privateKey: Hex;
  plinthAddress: Hex;
  chain?: ArcChain;
}

/**
 * AgentClient — for the agent that owns a vault.
 *
 * Surface: createVault, deployToVenue, returnFromVenue, reportPnL,
 * setPaused, closeVault. Plus read helpers shared with InvestorClient.
 *
 * Robustness: Arc Testnet's RPC sometimes drops waitForReceipt; createVault
 * pre-computes vaultId from `vaultCount` before sending so callers always
 * get a valid id even when the receipt confirmation lags.
 */
export class AgentClient {
  readonly account: Account;
  readonly chain: ArcChain;
  readonly plinthAddress: Hex;
  readonly publicClient: PublicClient;
  readonly walletClient: WalletClient;

  constructor(opts: AgentClientOptions) {
    this.account = privateKeyToAccount(opts.privateKey);
    this.chain = opts.chain ?? ARC_TESTNET;
    this.plinthAddress = opts.plinthAddress;
    const viemChain = defineChain({
      id: this.chain.chainId,
      name: "Arc Testnet",
      nativeCurrency: { name: "USDC", symbol: "USDC", decimals: 18 },
      rpcUrls: { default: { http: [this.chain.rpc] } },
    });
    const transport = http(this.chain.rpc, { timeout: 60_000, retryCount: 2 });
    this.publicClient = createPublicClient({ chain: viemChain, transport });
    this.walletClient = createWalletClient({ account: this.account, chain: viemChain, transport });
  }

  get address(): Hex {
    return this.account.address;
  }

  /**
   * Create a new vault. `initialDepositWei` is sent as msg.value and seeds
   * the vault's pool at inception NAV (1 USDC/share).
   */
  async createVault(p: CreateVaultParams): Promise<{ txHash: Hex; vaultId: Hex }> {
    // Pre-compute vaultId locally for receipt-timeout resilience.
    const currentCount = (await this.publicClient.readContract({
      address: this.plinthAddress, abi: PLINTH_ABI,
      functionName: "vaultCount", args: [this.account.address],
    })) as bigint;
    const expectedVaultId = deriveVaultId(this.account.address, currentCount + 1n, this.chain.chainId);

    const txHash = await this.walletClient.writeContract({
      account: this.account, chain: this.walletClient.chain!,
      address: this.plinthAddress, abi: PLINTH_ABI,
      functionName: "createVault",
      args: [p.approvedVenues, p.strategyDescriptor],
      value: p.initialDepositWei,
    });

    try {
      const receipt = await this.publicClient.waitForTransactionReceipt({
        hash: txHash, timeout: 300_000, pollingInterval: 4_000,
      });
      for (const log of receipt.logs) {
        if (log.address.toLowerCase() !== this.plinthAddress.toLowerCase()) continue;
        try {
          const decoded = decodeEventLog({ abi: PLINTH_ABI, data: log.data, topics: log.topics });
          if (decoded.eventName === "VaultCreated") {
            return { txHash, vaultId: decoded.args.vaultId as Hex };
          }
        } catch {/* not our event */}
      }
    } catch (e) {
      console.warn(`[plinth] waitForReceipt timed out for createVault tx ${txHash}; returning pre-computed vaultId.`);
    }
    return { txHash, vaultId: expectedVaultId };
  }

  async deployToVenue(vaultId: Hex, venue: Hex, amountWei: bigint): Promise<Hex> {
    const txHash = await this.walletClient.writeContract({
      account: this.account, chain: this.walletClient.chain!,
      address: this.plinthAddress, abi: PLINTH_ABI,
      functionName: "deployToVenue",
      args: [vaultId, venue, amountWei],
    });
    await this.publicClient.waitForTransactionReceipt({ hash: txHash, timeout: 300_000 });
    return txHash;
  }

  /**
   * Record USDC returning from a venue. `amountWei` MUST be sent as
   * msg.value in this call — caller must have received that value from
   * the venue or be the venue itself.
   */
  async returnFromVenue(vaultId: Hex, venue: Hex, amountWei: bigint): Promise<Hex> {
    const txHash = await this.walletClient.writeContract({
      account: this.account, chain: this.walletClient.chain!,
      address: this.plinthAddress, abi: PLINTH_ABI,
      functionName: "returnFromVenue",
      args: [vaultId, venue, amountWei],
      value: amountWei,
    });
    await this.publicClient.waitForTransactionReceipt({ hash: txHash, timeout: 300_000 });
    return txHash;
  }

  async reportPnL(vaultId: Hex, newPnL: bigint): Promise<Hex> {
    const txHash = await this.walletClient.writeContract({
      account: this.account, chain: this.walletClient.chain!,
      address: this.plinthAddress, abi: PLINTH_ABI,
      functionName: "reportPnL",
      args: [vaultId, newPnL],
    });
    await this.publicClient.waitForTransactionReceipt({ hash: txHash, timeout: 300_000 });
    return txHash;
  }

  async setPaused(vaultId: Hex, paused: boolean): Promise<Hex> {
    const txHash = await this.walletClient.writeContract({
      account: this.account, chain: this.walletClient.chain!,
      address: this.plinthAddress, abi: PLINTH_ABI,
      functionName: "setPaused",
      args: [vaultId, paused],
    });
    await this.publicClient.waitForTransactionReceipt({ hash: txHash, timeout: 300_000 });
    return txHash;
  }

  async closeVault(vaultId: Hex): Promise<Hex> {
    const txHash = await this.walletClient.writeContract({
      account: this.account, chain: this.walletClient.chain!,
      address: this.plinthAddress, abi: PLINTH_ABI,
      functionName: "closeVault",
      args: [vaultId],
    });
    await this.publicClient.waitForTransactionReceipt({ hash: txHash, timeout: 300_000 });
    return txHash;
  }

  /** Shared read helper. */
  async getVault(vaultId: Hex): Promise<VaultState> {
    const r = (await this.publicClient.readContract({
      address: this.plinthAddress, abi: PLINTH_ABI,
      functionName: "vaults", args: [vaultId],
    })) as readonly [Hex, bigint, number, bigint, bigint, bigint, bigint, string];
    return {
      agent: r[0], createdAt: r[1], status: r[2],
      totalShares: r[3], inVault: r[4], deployedAUM: r[5],
      reportedPnL: r[6], strategyDescriptor: r[7],
    };
  }
}
