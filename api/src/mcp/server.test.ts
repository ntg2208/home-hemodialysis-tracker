import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('../lib/reads/bloodTestReads.js', () => ({
  getBloodMarkers: vi.fn(async () => [{ marker: 'potassium', value: 5.0 }]),
  getOutOfRangeMarkers: vi.fn(async () => [{ marker: 'potassium', value: 6.1 }]),
}));
vi.mock('../lib/reads/sessionReads.js', () => ({
  getSessions: vi.fn(async () => [{ session_id: 's1', readings: [] }]),
}));
vi.mock('../lib/reads/inventoryReads.js', async () => {
  const actual = await vi.importActual<typeof import('../lib/reads/inventoryReads.js')>(
    '../lib/reads/inventoryReads.js',
  );
  return {
    enrichStock: actual.enrichStock, // keep the real pure enrichment
    getInventory: vi.fn(async () => ({
      stock: { 'CAR-172-C': 4 }, cycle: null,
      pak_installed_at: null, pak_sessions: 0, pak_avg_sessions: null,
    })),
    getOrders: vi.fn(async () => ({
      current_order: null,
      history: [{ date: '2026-05-25T10:00:00Z', note: 'delivery applied', items: [] }],
    })),
  };
});

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

  it('lists the five read tools', async () => {
    const client = await connected();
    const names = (await client.listTools()).tools.map((t) => t.name).sort();
    expect(names).toEqual(
      ['get_blood_markers', 'get_inventory', 'get_orders', 'get_out_of_range_markers', 'get_sessions'],
    );
  });

  it('get_inventory returns catalogue-enriched items', async () => {
    const client = await connected();
    const res = await client.callTool({ name: 'get_inventory', arguments: {} });
    const text = (res.content as { type: string; text: string }[])[0].text;
    const out = JSON.parse(text);
    expect(out.items).toEqual([
      {
        code: 'CAR-172-C', label: 'Cartridges', qty: 4, unit: 'cartridge', box_size: 6,
        box_label: 'box', per_session: 1, target_qty: 24, section: 'nxstage',
        sessions_remaining: 4, status: 'red',
      },
    ]);
  });

  it('get_orders returns current_order + history', async () => {
    const client = await connected();
    const res = await client.callTool({ name: 'get_orders', arguments: {} });
    const text = (res.content as { type: string; text: string }[])[0].text;
    const out = JSON.parse(text);
    expect(out.current_order).toBeNull();
    expect(out.history).toHaveLength(1);
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
