import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('../lib/reads/bloodTestReads.js', () => ({
  getBloodMarkers: vi.fn(async () => [{ marker: 'potassium', value: 5.0 }]),
  getOutOfRangeMarkers: vi.fn(async () => [{ marker: 'potassium', value: 6.1 }]),
}));
vi.mock('../lib/reads/sessionReads.js', () => ({
  getSessions: vi.fn(async () => [{ session_id: 's1', readings: [] }]),
}));
vi.mock('../lib/reads/inventoryReads.js', () => ({
  getInventory: vi.fn(async () => ({ stock: { 'CAR-172-C': 4 } })),
}));

import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import { buildMcpServer } from './server.js';
import { getBloodMarkers } from '../lib/reads/bloodTestReads.js';

async function connected() {
  const [clientT, serverT] = InMemoryTransport.createLinkedPair();
  const server = buildMcpServer();
  const client = new Client({ name: 'test', version: '0.0.0' });
  await Promise.all([server.connect(serverT), client.connect(clientT)]);
  return client;
}

describe('buildMcpServer', () => {
  beforeEach(() => vi.clearAllMocks());

  it('lists the four read tools', async () => {
    const client = await connected();
    const names = (await client.listTools()).tools.map((t) => t.name).sort();
    expect(names).toEqual(
      ['get_blood_markers', 'get_inventory', 'get_out_of_range_markers', 'get_sessions'],
    );
  });

  it('get_blood_markers passes args through and returns JSON text', async () => {
    const client = await connected();
    const res = await client.callTool({
      name: 'get_blood_markers',
      arguments: { marker: 'potassium', phase: 'home-hd' },
    });
    expect(getBloodMarkers).toHaveBeenCalledWith({ marker: ['potassium'], phase: ['home-hd'] });
    const text = (res.content as { type: string; text: string }[])[0].text;
    expect(JSON.parse(text)).toEqual([{ marker: 'potassium', value: 5.0 }]);
  });
});
