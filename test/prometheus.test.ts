/**
 * MCP Server Requirements Test Suite (Prometheus Protocol)
 */

import { describe, beforeAll, afterAll, it, expect, inject } from 'vitest';
import { PocketIc, createIdentity } from '@dfinity/pic';
import { IDL } from '@icp-sdk/core/candid';
import { AnonymousIdentity } from '@icp-sdk/core/agent';
import { Principal } from '@icp-sdk/core/principal';
import { idlFactory as mcpServerIdlFactory } from '../.dfx/local/canisters/slot_machine/service.did.js';
import type { _SERVICE as McpServerService } from '../.dfx/local/canisters/slot_machine/service.did.d.ts';
import type { Actor } from '@dfinity/pic';
import path from 'node:path';

const MCP_SERVER_WASM_PATH = path.resolve(
  __dirname,
  '../.dfx/local/canisters/slot_machine/slot_machine.wasm',
);

describe('MCP Server Requirements', () => {
  let pic: PocketIc;
  let serverActor: Actor<McpServerService>;
  let canisterId: Principal;
  let testOwner = createIdentity('test-owner');
  let apiKey: string;

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
      caller: testOwner,
      arg: initArg.buffer as ArrayBufferLike,
    });

    serverActor = pic.createActor<McpServerService>(
      mcpServerIdlFactory,
      canisterId,
    );

    // Create API key for auth'd requests
    serverActor.setIdentity(testOwner);
    apiKey = await serverActor.create_my_api_key('test-key', ['openid']);
  });

  afterAll(async () => {
    await pic?.tearDown();
  });

  describe('JSON-RPC Tool Discovery', () => {
    it('should respond to tools/list request via http_request_update', async () => {
      const rpcPayload = {
        jsonrpc: '2.0',
        method: 'tools/list',
        params: {},
        id: 'test-tools-list',
      };
      const body = new TextEncoder().encode(JSON.stringify(rpcPayload));
      const httpResponse = await serverActor.http_request_update({
        method: 'POST',
        url: '/mcp',
        headers: [['Content-Type', 'application/json'], ['X-API-Key', apiKey]],
        body,
        certificate_version: [],
      });
      expect(httpResponse.status_code).toBe(200);
    });

    it('should return valid JSON-RPC response with tools array', async () => {
      const rpcPayload = {
        jsonrpc: '2.0',
        method: 'tools/list',
        params: {},
        id: 'test-tools-list',
      };
      const body = new TextEncoder().encode(JSON.stringify(rpcPayload));
      const httpResponse = await serverActor.http_request_update({
        method: 'POST',
        url: '/mcp',
        headers: [['Content-Type', 'application/json'], ['X-API-Key', apiKey]],
        body,
        certificate_version: [],
      });
      const responseBody = JSON.parse(
        new TextDecoder().decode(httpResponse.body as Uint8Array),
      );
      expect(responseBody).toHaveProperty('jsonrpc', '2.0');
      expect(responseBody).toHaveProperty('id', 'test-tools-list');
      expect(responseBody).not.toHaveProperty('error');
      expect(responseBody).toHaveProperty('result');
      expect(responseBody.result).toHaveProperty('tools');
      expect(Array.isArray(responseBody.result.tools)).toBe(true);
    });

    it('should return tools with required fields (name, description, inputSchema)', async () => {
      const rpcPayload = {
        jsonrpc: '2.0',
        method: 'tools/list',
        params: {},
        id: 'test-tools-list',
      };
      const body = new TextEncoder().encode(JSON.stringify(rpcPayload));
      const httpResponse = await serverActor.http_request_update({
        method: 'POST',
        url: '/mcp',
        headers: [['Content-Type', 'application/json'], ['X-API-Key', apiKey]],
        body,
        certificate_version: [],
      });
      const responseBody = JSON.parse(
        new TextDecoder().decode(httpResponse.body as Uint8Array),
      );
      const tools = responseBody.result.tools;
      if (tools.length > 0) {
        tools.forEach((tool: any) => {
          expect(tool).toHaveProperty('name');
          expect(typeof tool.name).toBe('string');
          expect(tool.name.length).toBeGreaterThan(0);
          if (tool.description !== undefined) {
            expect(typeof tool.description).toBe('string');
          }
          if (tool.inputSchema !== undefined) {
            expect(typeof tool.inputSchema).toBe('object');
          }
        });
      }
    });
  });

  describe('Owner System', () => {
    it('should have get_owner method', async () => {
      // @ts-ignore
      const owner = await serverActor.get_owner();
      expect(owner).toBeDefined();
      expect(typeof owner.toText).toBe('function');
    });

    it('should return a valid Principal as owner', async () => {
      // @ts-ignore
      const owner = await serverActor.get_owner();
      const ownerText = owner.toText();
      expect(typeof ownerText).toBe('string');
      expect(ownerText.length).toBeGreaterThan(0);
      expect(ownerText).not.toBe('2vxsx-fae');
    });
  });

  describe('Wallet/Treasury System', () => {
    it('should have get_treasury_balance method', async () => {
      const dummyLedgerId = Principal.fromText('aaaaa-aa');
      // @ts-ignore
      const balance = await serverActor.get_treasury_balance(dummyLedgerId);
      expect(balance).toBeDefined();
    });

    it('should return a numeric balance (bigint or number)', async () => {
      const dummyLedgerId = Principal.fromText('aaaaa-aa');
      // @ts-ignore
      const balance = await serverActor.get_treasury_balance(dummyLedgerId);
      const isNumeric = typeof balance === 'bigint' || typeof balance === 'number';
      expect(isNumeric).toBe(true);
      if (typeof balance === 'bigint') {
        expect(balance >= 0n).toBe(true);
      } else {
        expect(balance >= 0).toBe(true);
      }
    });
  });

  describe('ICRC-120 Upgrade System', () => {
    it('should have icrc120_upgrade_finished method', async () => {
      // @ts-ignore
      const result = await serverActor.icrc120_upgrade_finished();
      expect(result).toBeDefined();
    });

    it('should return valid upgrade status', async () => {
      // @ts-ignore
      const result = await serverActor.icrc120_upgrade_finished();
      expect(result).toBeDefined();
      const hasValidKey =
        'Success' in result ||
        'InProgress' in result ||
        'Failed' in result;
      expect(hasValidKey).toBe(true);
      if ('Success' in result) {
        const timestamp = result.Success;
        expect(typeof timestamp === 'bigint' || typeof timestamp === 'number').toBe(true);
        if (typeof timestamp === 'bigint') {
          expect(timestamp > 0n).toBe(true);
        } else {
          expect(timestamp > 0).toBe(true);
        }
      }
    });
  });

  describe('API Key System', () => {
    it('should have API key system enabled', async () => {
      const testIdentity = createIdentity('test-api-key-user-2');
      serverActor.setIdentity(testIdentity);
      // @ts-ignore
      const newKey = await serverActor.create_my_api_key('test-key-2', ['openid']);
      expect(typeof newKey).toBe('string');
      expect(newKey.length).toBeGreaterThan(0);
    });
  });

  describe('Complete System Integration', () => {
    it('should meet all requirements for create-motoko-mcp-server template', async () => {
      const requirements = {
        toolDiscovery: false,
        ownerSystem: false,
        walletSystem: false,
        icrc120: false,
      };

      try {
        const rpcPayload = {
          jsonrpc: '2.0',
          method: 'tools/list',
          params: {},
          id: 'integration-test',
        };
        const body = new TextEncoder().encode(JSON.stringify(rpcPayload));
        const httpResponse = await serverActor.http_request_update({
          method: 'POST',
          url: '/mcp',
          headers: [['Content-Type', 'application/json'], ['X-API-Key', apiKey]],
          body,
          certificate_version: [],
        });
        if (httpResponse.status_code === 200) {
          const responseBody = JSON.parse(
            new TextDecoder().decode(httpResponse.body as Uint8Array),
          );
          if (responseBody.result?.tools && Array.isArray(responseBody.result.tools)) {
            requirements.toolDiscovery = true;
          }
        }
      } catch (e) {}

      try {
        // @ts-ignore
        const owner = await serverActor.get_owner();
        if (owner && typeof owner.toText === 'function') {
          requirements.ownerSystem = true;
        }
      } catch (e) {}

      try {
        const dummyLedgerId = Principal.fromText('aaaaa-aa');
        // @ts-ignore
        const balance = await serverActor.get_treasury_balance(dummyLedgerId);
        if (typeof balance === 'bigint' || typeof balance === 'number') {
          requirements.walletSystem = true;
        }
      } catch (e) {}

      try {
        // @ts-ignore
        const result = await serverActor.icrc120_upgrade_finished();
        if (result && ('Success' in result || 'InProgress' in result || 'Failed' in result)) {
          requirements.icrc120 = true;
        }
      } catch (e) {}

      expect(requirements.toolDiscovery).toBe(true);
      expect(requirements.ownerSystem).toBe(true);
      expect(requirements.walletSystem).toBe(true);
      expect(requirements.icrc120).toBe(true);

      console.log('\n✅ MCP Server Requirements Summary:');
      console.log(`   📡 Tool Discovery (JSON-RPC): ${requirements.toolDiscovery ? '✅' : '❌'}`);
      console.log(`   👤 Owner System: ${requirements.ownerSystem ? '✅' : '❌'}`);
      console.log(`   💰 Wallet/Treasury System: ${requirements.walletSystem ? '✅' : '❌'}`);
      console.log(`   🔄 ICRC-120 Upgrade: ${requirements.icrc120 ? '✅' : '❌'}`);
    });
  });
});
