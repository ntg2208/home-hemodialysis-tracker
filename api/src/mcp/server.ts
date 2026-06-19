import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { getBloodMarkers, getOutOfRangeMarkers } from '../lib/reads/bloodTestReads.js';
import { getSessions } from '../lib/reads/sessionReads.js';
import { getInventory } from '../lib/reads/inventoryReads.js';
import type { QueryParams } from '../lib/queryFilter.js';

const csv = (s?: string): string[] | undefined =>
  s ? s.split(',').map((x) => x.trim()).filter(Boolean) : undefined;

const json = (data: unknown) => ({
  content: [{ type: 'text' as const, text: JSON.stringify(data) }],
});

const bloodArgs = {
  marker: z.string().optional().describe('Marker name(s), comma-separated. Symptom hints: itching→phosphate,calcium; fatigue→haemoglobin,ferritin; cramps→potassium,calcium; swelling→albumin,sodium.'),
  phase: z.string().optional().describe('One or more of: admission, in-center-hd, home-hd (comma-separated).'),
  from: z.string().optional().describe('Inclusive start, YYYY-MM or YYYY-MM-DD.'),
  to: z.string().optional().describe('Inclusive end, YYYY-MM or YYYY-MM-DD.'),
};

export function buildMcpServer(): McpServer {
  const server = new McpServer({ name: 'HD Tracker (read)', version: '1.0.0' });

  server.registerTool(
    'get_sessions',
    {
      description: 'Treatment session history with intra-session readings (BP trends, UF, weights).',
      inputSchema: {
        from: z.string().optional().describe('Inclusive start date YYYY-MM-DD.'),
        to: z.string().optional().describe('Inclusive end date YYYY-MM-DD.'),
        limit: z.number().int().positive().optional().describe('Max sessions, newest first.'),
      },
    },
    async ({ from, to, limit }) => json(await getSessions({ from, to, limit })),
  );

  server.registerTool(
    'get_blood_markers',
    { description: 'Blood test history filtered by marker/phase/date.', inputSchema: bloodArgs },
    async ({ marker, phase, from, to }) => {
      const p: QueryParams = { marker: csv(marker), phase: csv(phase), from, to };
      return json(await getBloodMarkers(p));
    },
  );

  server.registerTool(
    'get_out_of_range_markers',
    { description: 'Blood markers whose value falls outside its reference range.', inputSchema: { from: bloodArgs.from, to: bloodArgs.to } },
    async ({ from, to }) => json(await getOutOfRangeMarkers({ from, to })),
  );

  server.registerTool(
    'get_inventory',
    { description: 'Current consumable stock levels, order cycle, and PAK status.', inputSchema: {} },
    async () => json(await getInventory()),
  );

  return server;
}
