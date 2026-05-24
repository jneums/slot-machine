/**
 * Slot Machine Tool-Specific Test Suite
 */

import { describe, beforeAll, afterAll, it, expect, inject } from 'vitest';
import { PocketIc, createIdentity } from '@dfinity/pic';
import { IDL } from '@icp-sdk/core/candid';
import { AnonymousIdentity } from '@icp-sdk/core/agent';
import { idlFactory as mcpServerIdlFactory } from '../.dfx/local/canisters/slot_machine/service.did.js';
import type { _SERVICE as McpServerService } from '../.dfx/local/canisters/slot_machine/service.did.d.ts';
import type { Actor } from '@dfinity/pic';
import path from 'node:path';

const MCP_SERVER_WASM_PATH = path.resolve(
  __dirname,
  '../.dfx/local/canisters/slot_machine/slot_machine.wasm',
);

// Helper to call a tool via JSON-RPC with optional API key
async function callTool(
  actor: Actor<McpServerService>,
  toolName: string,
  args: Record<string, any> = {},
  apiKey?: string,
  id: string = 'test',
) {
  const rpcPayload = {
    jsonrpc: '2.0',
    method: 'tools/call',
    params: { name: toolName, arguments: args },
    id,
  };
  const body = new TextEncoder().encode(JSON.stringify(rpcPayload));
  const headers: [string, string][] = [['Content-Type', 'application/json']];
  if (apiKey) {
    headers.push(['X-API-Key', apiKey]);
  }
  const httpResponse = await actor.http_request_update({
    method: 'POST',
    url: '/mcp',
    headers,
    body,
    certificate_version: [],
  });
  if (httpResponse.status_code !== 200) {
    const bodyText = new TextDecoder().decode(httpResponse.body as Uint8Array);
    return {
      _status: httpResponse.status_code,
      _body: bodyText,
      result: {
        isError: true,
        content: [{ text: `HTTP ${httpResponse.status_code}: ${bodyText}` }],
      },
    };
  }
  const responseBody = JSON.parse(
    new TextDecoder().decode(httpResponse.body as Uint8Array),
  );
  return responseBody;
}

function parseResult(response: any): any {
  if (response.result?.content?.[0]?.text) {
    return JSON.parse(response.result.content[0].text);
  }
  return null;
}

describe('Slot Machine Tool Tests', () => {
  let pic: PocketIc;
  let serverActor: Actor<McpServerService>;
  let canisterId: any;
  let testOwner = createIdentity('test-owner');
  let player1 = createIdentity('player-1');
  let player2 = createIdentity('player-2');
  let player1ApiKey: string;
  let player2ApiKey: string;

  beforeAll(async () => {
    const picUrl = inject('PIC_URL');
    pic = await PocketIc.create(picUrl);
    canisterId = await pic.createCanister();

    const initArg = IDL.encode(
      [IDL.Opt(IDL.Record({ owner: IDL.Opt(IDL.Principal) }))],
      [[{ owner: [testOwner.getPrincipal()] }]],
    );

    await pic.installCode({
      canisterId,
      wasm: MCP_SERVER_WASM_PATH,
      arg: initArg.buffer as ArrayBufferLike,
    });

    serverActor = pic.createActor<McpServerService>(
      mcpServerIdlFactory,
      canisterId,
    );

    // Create API keys for players
    serverActor.setIdentity(player1);
    player1ApiKey = await serverActor.create_my_api_key('player1-key', ['openid']);

    serverActor.setIdentity(player2);
    player2ApiKey = await serverActor.create_my_api_key('player2-key', ['openid']);
  });

  afterAll(async () => {
    await pic?.tearDown();
  });

  // ── Tool Discovery ──

  describe('Tool Discovery', () => {
    it('should list all 6 tools', async () => {
      // tools/list requires auth with API key
      const rpcPayload = {
        jsonrpc: '2.0',
        method: 'tools/list',
        params: {},
        id: 'list-tools',
      };
      const body = new TextEncoder().encode(JSON.stringify(rpcPayload));
      const httpResponse = await serverActor.http_request_update({
        method: 'POST',
        url: '/mcp',
        headers: [
          ['Content-Type', 'application/json'],
          ['X-API-Key', player1ApiKey],
        ],
        body,
        certificate_version: [],
      });
      expect(httpResponse.status_code).toBe(200);
      const responseBody = JSON.parse(
        new TextDecoder().decode(httpResponse.body as Uint8Array),
      );
      const tools = responseBody.result.tools;
      expect(tools).toHaveLength(6);
      const toolNames = tools.map((t: any) => t.name).sort();
      expect(toolNames).toEqual([
        'claim_faucet',
        'get_balance',
        'get_machine_stats',
        'get_spin_history',
        'spin',
        'verify_spin',
      ]);
    });
  });

  // ── claim_faucet ──

  describe('claim_faucet', () => {
    it('should reject unauthenticated callers', async () => {
      const response = await callTool(serverActor, 'claim_faucet', {});
      expect(response.result.isError).toBe(true);
    });

    it('should create account and grant 100 credits on first claim', async () => {
      const response = await callTool(serverActor, 'claim_faucet', {}, player1ApiKey);
      expect(response.result.isError).toBe(false);
      const result = parseResult(response);
      expect(result.balance).toBe(100);
      expect(result.claimed).toBe(100);
      expect(result.message).toContain('Welcome');
    });

    it('should reject second claim within 24 hours', async () => {
      const response = await callTool(serverActor, 'claim_faucet', {}, player1ApiKey);
      expect(response.result.isError).toBe(false);
      const result = parseResult(response);
      expect(result.claimed).toBe(0);
      expect(result.message).toContain('RATE_LIMITED');
    });
  });

  // ── get_balance ──

  describe('get_balance', () => {
    it('should reject unauthenticated callers', async () => {
      const response = await callTool(serverActor, 'get_balance', {});
      expect(response.result.isError).toBe(true);
    });

    it('should return account not found for new player', async () => {
      const newPlayer = createIdentity('no-account-player');
      serverActor.setIdentity(newPlayer);
      const newKey = await serverActor.create_my_api_key('temp-key', ['openid']);
      const response = await callTool(serverActor, 'get_balance', {}, newKey);
      expect(response.result.isError).toBe(true);
      expect(response.result.content[0].text).toContain('NOT_FOUND');
    });

    it('should return balance for existing player', async () => {
      const response = await callTool(serverActor, 'get_balance', {}, player1ApiKey);
      expect(response.result.isError).toBe(false);
      const result = parseResult(response);
      expect(result.balance).toBe(100);
      expect(result.totalSpins).toBe(0);
    });
  });

  // ── spin ──

  describe('spin', () => {
    it('should reject unauthenticated callers', async () => {
      const response = await callTool(serverActor, 'spin', { bet: 10 });
      expect(response.result.isError).toBe(true);
    });

    it('should reject spin without account', async () => {
      const noAccount = createIdentity('no-account-spinner');
      serverActor.setIdentity(noAccount);
      const noKey = await serverActor.create_my_api_key('temp-key', ['openid']);
      const response = await callTool(serverActor, 'spin', { bet: 10 }, noKey);
      expect(response.result.isError).toBe(true);
      expect(response.result.content[0].text).toContain('NOT_FOUND');
    });

    it('should reject bet below minimum', async () => {
      const response = await callTool(serverActor, 'spin', { bet: 0 }, player1ApiKey);
      expect(response.result.isError).toBe(true);
      expect(response.result.content[0].text).toContain('INVALID_INPUT');
    });

    it('should reject bet above maximum', async () => {
      const response = await callTool(serverActor, 'spin', { bet: 101 }, player1ApiKey);
      expect(response.result.isError).toBe(true);
      expect(response.result.content[0].text).toContain('INVALID_INPUT');
    });

    it('should successfully spin with valid bet', async () => {
      const response = await callTool(serverActor, 'spin', { bet: 10 }, player1ApiKey);
      expect(response.result.isError).toBe(false);
      const result = parseResult(response);
      expect(result.spinId).toBe('spin-1');
      expect(result.reels).toBeDefined();
      expect(result.reelSymbols).toHaveLength(3);
      expect(result.seed).toBeDefined();
      expect(result.seed.length).toBeGreaterThan(0);
      expect(result.multiplier).toBeGreaterThanOrEqual(0);
      expect(result.payout).toBeGreaterThanOrEqual(0);
      // Balance should be 100 - 10 + payout
      expect(result.balanceAfter).toBe(100 - 10 + result.payout);
    });

    it('should handle multiple spins and update stats', async () => {
      const spin2 = await callTool(serverActor, 'spin', { bet: 5 }, player1ApiKey);
      expect(spin2.result.isError).toBe(false);
      const r2 = parseResult(spin2);
      expect(r2.spinId).toBe('spin-2');

      const spin3 = await callTool(serverActor, 'spin', { bet: 1 }, player1ApiKey);
      expect(spin3.result.isError).toBe(false);
      const r3 = parseResult(spin3);
      expect(r3.spinId).toBe('spin-3');

      // Check balance reflects all spins
      const balRes = await callTool(serverActor, 'get_balance', {}, player1ApiKey);
      const bal = parseResult(balRes);
      expect(bal.totalSpins).toBe(3);
      expect(bal.totalWagered).toBe(16); // 10 + 5 + 1
    });
  });

  // ── get_spin_history ──

  describe('get_spin_history', () => {
    it('should reject unauthenticated callers', async () => {
      const response = await callTool(serverActor, 'get_spin_history', {});
      expect(response.result.isError).toBe(true);
    });

    it('should return spin history for player', async () => {
      const response = await callTool(serverActor, 'get_spin_history', {}, player1ApiKey);
      expect(response.result.isError).toBe(false);
      const result = parseResult(response);
      expect(result.total).toBe(3);
      expect(result.spins).toHaveLength(3);
      // Most recent first
      expect(result.spins[0].spinId).toBe('spin-3');
      expect(result.spins[1].spinId).toBe('spin-2');
      expect(result.spins[2].spinId).toBe('spin-1');
    });

    it('should respect limit parameter', async () => {
      const response = await callTool(serverActor, 'get_spin_history', { limit: 1 }, player1ApiKey);
      expect(response.result.isError).toBe(false);
      const result = parseResult(response);
      expect(result.spins).toHaveLength(1);
      expect(result.total).toBe(3);
      expect(result.showing).toBe(1);
    });

    it('should respect offset parameter', async () => {
      const response = await callTool(serverActor, 'get_spin_history', { limit: 1, offset: 2 }, player1ApiKey);
      expect(response.result.isError).toBe(false);
      const result = parseResult(response);
      expect(result.spins).toHaveLength(1);
      expect(result.spins[0].spinId).toBe('spin-1');
    });
  });

  // ── get_machine_stats ──

  describe('get_machine_stats', () => {
    it('should work with API key (public tool)', async () => {
      const response = await callTool(serverActor, 'get_machine_stats', {}, player1ApiKey);
      expect(response.result.isError).toBe(false);
      const result = parseResult(response);
      expect(result.totalSpins).toBe(3);
      expect(result.totalWagered).toBe(16);
      expect(result.totalPlayers).toBe(1);
      expect(result.payoutTable).toBeDefined();
      expect(result.payoutTable).toHaveLength(8);
      expect(result.symbolWeights).toBeDefined();
      expect(result.symbolWeights).toHaveLength(6);
      expect(result.randomnessSource).toContain('raw_rand');
      expect(result.betRange.min).toBe(1);
      expect(result.betRange.max).toBe(100);
    });
  });

  // ── verify_spin ──

  describe('verify_spin', () => {
    it('should verify a spin result (public tool)', async () => {
      const response = await callTool(serverActor, 'verify_spin', { spinId: 'spin-1' }, player1ApiKey);
      expect(response.result.isError).toBe(false);
      const result = parseResult(response);
      expect(result.spinId).toBe('spin-1');
      expect(result.verified).toBe(true);
      expect(result.seed).toBeDefined();
      expect(result.recordedReels).toBeDefined();
      expect(result.derivedReels).toBeDefined();
      expect(result.recordedReels).toBe(result.derivedReels);
      expect(result.algorithm).toContain('raw_rand');
    });

    it('should return NOT_FOUND for nonexistent spin', async () => {
      const response = await callTool(serverActor, 'verify_spin', { spinId: 'spin-999' }, player1ApiKey);
      expect(response.result.isError).toBe(true);
      expect(response.result.content[0].text).toContain('NOT_FOUND');
    });

    it('should reject missing spinId', async () => {
      const response = await callTool(serverActor, 'verify_spin', {}, player1ApiKey);
      expect(response.result.isError).toBe(true);
      expect(response.result.content[0].text).toContain('INVALID_INPUT');
    });
  });

  // ── Multi-player ──

  describe('Multi-player', () => {
    it('should track separate accounts for different players', async () => {
      // Player 2 claims faucet
      const claimRes = await callTool(serverActor, 'claim_faucet', {}, player2ApiKey);
      expect(claimRes.result.isError).toBe(false);
      const claim = parseResult(claimRes);
      expect(claim.balance).toBe(100);

      // Player 2 spins
      const spinRes = await callTool(serverActor, 'spin', { bet: 50 }, player2ApiKey);
      expect(spinRes.result.isError).toBe(false);

      // Player 2 balance should be independent
      const balRes = await callTool(serverActor, 'get_balance', {}, player2ApiKey);
      const bal = parseResult(balRes);
      expect(bal.totalSpins).toBe(1);
      expect(bal.totalWagered).toBe(50);

      // Machine stats should reflect both players
      const statsRes = await callTool(serverActor, 'get_machine_stats', {}, player1ApiKey);
      const stats = parseResult(statsRes);
      expect(stats.totalPlayers).toBe(2);
      expect(stats.totalSpins).toBe(4); // 3 from player1 + 1 from player2
    });
  });
});
