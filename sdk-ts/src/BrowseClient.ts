import {
  createPublicClient,
  defineChain,
  http,
  decodeEventLog,
  parseAbiItem,
  type PublicClient,
  type Log,
} from "viem";
import { ARC_TESTNET, PLINTH_ABI, type ArcChain } from "./constants.js";
import type { Hex, VaultState } from "./types.js";

export interface BrowseClientOptions {
  plinthAddress: Hex;
  chain?: ArcChain;
}

export interface VaultListing {
  vaultId: Hex;
  agent: Hex;
  strategyDescriptor: string;
  approvedVenues: Hex[];
  initialDeposit: bigint;
  createdAtBlock: bigint;
  createdAtTxHash: Hex;
  // current state (re-read on each listAllVaults call):
  state?: VaultState;
  nav?: bigint;
}

export interface UnderwriterReview {
  vaultId: Hex;
  underwriter: Hex;
  reviewHash: Hex;
  reviewUri: string;
  blockNumber: bigint;
  txHash: Hex;
}

/**
 * BrowseClient — read-only client for vault discovery + auditor / UI use.
 * No private key required.
 *
 * Scans VaultCreated events to enumerate all vaults; then optionally reads
 * current state for each. For underwriter reviews, scans
 * UnderwriterReviewPosted events.
 */
export class BrowseClient {
  readonly chain: ArcChain;
  readonly plinthAddress: Hex;
  readonly publicClient: PublicClient;

  constructor(opts: BrowseClientOptions) {
    this.chain = opts.chain ?? ARC_TESTNET;
    this.plinthAddress = opts.plinthAddress;
    const viemChain = defineChain({
      id: this.chain.chainId,
      name: "Arc Testnet",
      nativeCurrency: { name: "USDC", symbol: "USDC", decimals: 18 },
      rpcUrls: { default: { http: [this.chain.rpc] } },
    });
    this.publicClient = createPublicClient({
      chain: viemChain,
      transport: http(this.chain.rpc, { timeout: 60_000, retryCount: 2 }),
    });
  }

  /**
   * List every vault that has ever existed on this Plinth deployment.
   *
   * `fromBlock` defaults to 0; pass the deployment block for efficiency
   * on large chains. `withState=true` fetches each vault's current state.
   */
  async listAllVaults(
    fromBlock: bigint = 0n,
    toBlock: bigint | "latest" = "latest",
    withState: boolean = true,
  ): Promise<VaultListing[]> {
    const event = parseAbiItem(
      "event VaultCreated(bytes32 indexed vaultId, address indexed agent, address[] approvedVenues, string strategyDescriptor, uint256 initialDeposit)",
    );
    const logs = await this.publicClient.getLogs({
      address: this.plinthAddress, event, fromBlock, toBlock,
    });

    const listings: VaultListing[] = [];
    for (const l of logs) {
      const decoded = decodeEventLog({
        abi: PLINTH_ABI, data: l.data, topics: l.topics, eventName: "VaultCreated",
      });
      const listing: VaultListing = {
        vaultId: decoded.args.vaultId as Hex,
        agent: decoded.args.agent as Hex,
        strategyDescriptor: decoded.args.strategyDescriptor as string,
        approvedVenues: decoded.args.approvedVenues as Hex[],
        initialDeposit: decoded.args.initialDeposit as bigint,
        createdAtBlock: l.blockNumber ?? 0n,
        createdAtTxHash: l.transactionHash ?? ("0x" as Hex),
      };
      if (withState) {
        const r = (await this.publicClient.readContract({
          address: this.plinthAddress, abi: PLINTH_ABI,
          functionName: "vaults", args: [listing.vaultId],
        })) as readonly [Hex, bigint, number, bigint, bigint, bigint, bigint, string];
        listing.state = {
          agent: r[0], createdAt: r[1], status: r[2],
          totalShares: r[3], inVault: r[4], deployedAUM: r[5],
          reportedPnL: r[6], strategyDescriptor: r[7],
        };
        listing.nav = (await this.publicClient.readContract({
          address: this.plinthAddress, abi: PLINTH_ABI,
          functionName: "nav", args: [listing.vaultId],
        })) as bigint;
      }
      listings.push(listing);
    }
    return listings;
  }

  /**
   * All underwriter reviews for a given vault. Newer first.
   */
  async listReviews(
    vaultId: Hex,
    fromBlock: bigint = 0n,
  ): Promise<UnderwriterReview[]> {
    const event = parseAbiItem(
      "event UnderwriterReviewPosted(bytes32 indexed vaultId, address indexed underwriter, bytes32 reviewHash, string reviewUri)",
    );
    const logs = await this.publicClient.getLogs({
      address: this.plinthAddress, event,
      args: { vaultId },
      fromBlock,
    });
    return logs.map((l: Log) => {
      const d = decodeEventLog({
        abi: PLINTH_ABI, data: l.data, topics: l.topics,
        eventName: "UnderwriterReviewPosted",
      });
      return {
        vaultId:     d.args.vaultId as Hex,
        underwriter: d.args.underwriter as Hex,
        reviewHash:  d.args.reviewHash as Hex,
        reviewUri:   d.args.reviewUri as string,
        blockNumber: l.blockNumber ?? 0n,
        txHash:      l.transactionHash ?? ("0x" as Hex),
      };
    }).reverse();
  }
}
