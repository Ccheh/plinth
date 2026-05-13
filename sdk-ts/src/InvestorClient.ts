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
import type { Hex, VaultState } from "./types.js";
import { computeNav, sharesForDeposit, usdcForRedeem } from "./utils.js";

export interface InvestorClientOptions {
  privateKey: Hex;
  plinthAddress: Hex;
  chain?: ArcChain;
}

/**
 * InvestorClient — for users buying / selling vault shares.
 *
 * Surface: deposit, redeem, sharesOf, vault snapshots, NAV calcs.
 */
export class InvestorClient {
  readonly account: Account;
  readonly chain: ArcChain;
  readonly plinthAddress: Hex;
  readonly publicClient: PublicClient;
  readonly walletClient: WalletClient;

  constructor(opts: InvestorClientOptions) {
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
   * Deposit USDC into a vault at current NAV.
   *
   * Returns the actual shares minted (decoded from the on-chain event),
   * plus the predicted shares from the off-chain NAV calculation — they
   * should agree unless an oracle / agent state update interleaved.
   */
  async deposit(vaultId: Hex, usdcWei: bigint): Promise<{
    txHash: Hex; sharesMinted: bigint; predictedShares: bigint; navAtDeposit: bigint;
  }> {
    const preNav = await this.getNAV(vaultId);
    const predictedShares = sharesForDeposit(usdcWei, preNav);

    const txHash = await this.walletClient.writeContract({
      account: this.account, chain: this.walletClient.chain!,
      address: this.plinthAddress, abi: PLINTH_ABI,
      functionName: "deposit", args: [vaultId],
      value: usdcWei,
    });
    const receipt = await this.publicClient.waitForTransactionReceipt({ hash: txHash, timeout: 300_000 });

    let actualShares = 0n;
    let navAtDeposit = preNav;
    for (const log of receipt.logs) {
      if (log.address.toLowerCase() !== this.plinthAddress.toLowerCase()) continue;
      try {
        const decoded = decodeEventLog({ abi: PLINTH_ABI, data: log.data, topics: log.topics });
        if (decoded.eventName === "Deposit") {
          actualShares = decoded.args.sharesMinted as bigint;
          navAtDeposit = decoded.args.navAtDeposit as bigint;
        }
      } catch {/* not our event */}
    }
    return { txHash, sharesMinted: actualShares, predictedShares, navAtDeposit };
  }

  async redeem(vaultId: Hex, shareAmount: bigint): Promise<{
    txHash: Hex; usdcOut: bigint; predictedUsdcOut: bigint; navAtRedeem: bigint;
  }> {
    const preNav = await this.getNAV(vaultId);
    const predictedUsdcOut = usdcForRedeem(shareAmount, preNav);

    const txHash = await this.walletClient.writeContract({
      account: this.account, chain: this.walletClient.chain!,
      address: this.plinthAddress, abi: PLINTH_ABI,
      functionName: "redeem", args: [vaultId, shareAmount],
    });
    const receipt = await this.publicClient.waitForTransactionReceipt({ hash: txHash, timeout: 300_000 });

    let usdcOut = 0n;
    let navAtRedeem = preNav;
    for (const log of receipt.logs) {
      if (log.address.toLowerCase() !== this.plinthAddress.toLowerCase()) continue;
      try {
        const decoded = decodeEventLog({ abi: PLINTH_ABI, data: log.data, topics: log.topics });
        if (decoded.eventName === "Redeem") {
          usdcOut = decoded.args.usdcOut as bigint;
          navAtRedeem = decoded.args.navAtRedeem as bigint;
        }
      } catch {/* not our event */}
    }
    return { txHash, usdcOut, predictedUsdcOut, navAtRedeem };
  }

  /**
   * Post a 3rd-party underwriter review. Anyone can call. The on-chain
   * footprint is just the event — the review body lives at `reviewUri`
   * (IPFS / HTTPS). Hash binds the URI content immutably.
   */
  async postUnderwriterReview(vaultId: Hex, reviewHash: Hex, reviewUri: string): Promise<Hex> {
    const txHash = await this.walletClient.writeContract({
      account: this.account, chain: this.walletClient.chain!,
      address: this.plinthAddress, abi: PLINTH_ABI,
      functionName: "postUnderwriterReview",
      args: [vaultId, reviewHash, reviewUri],
    });
    await this.publicClient.waitForTransactionReceipt({ hash: txHash, timeout: 300_000 });
    return txHash;
  }

  /* ---------- reads ---------- */

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

  /** Read current NAV from chain. */
  async getNAV(vaultId: Hex): Promise<bigint> {
    return (await this.publicClient.readContract({
      address: this.plinthAddress, abi: PLINTH_ABI,
      functionName: "nav", args: [vaultId],
    })) as bigint;
  }

  /** Read NAV by recomputing from raw vault state — verifies the on-chain
   *  view function's output against the same formula in TypeScript. */
  async getNAVRecomputed(vaultId: Hex): Promise<bigint> {
    const v = await this.getVault(vaultId);
    return computeNav(v.inVault, v.deployedAUM, v.reportedPnL, v.totalShares);
  }

  async sharesOf(vaultId: Hex, user?: Hex): Promise<bigint> {
    const target = user ?? this.account.address;
    return (await this.publicClient.readContract({
      address: this.plinthAddress, abi: PLINTH_ABI,
      functionName: "sharesOf", args: [vaultId, target],
    })) as bigint;
  }

  async getApprovedVenues(vaultId: Hex): Promise<Hex[]> {
    return (await this.publicClient.readContract({
      address: this.plinthAddress, abi: PLINTH_ABI,
      functionName: "getApprovedVenues", args: [vaultId],
    })) as Hex[];
  }
}
