import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { getBloodMarkers, getOutOfRangeMarkers } from '../lib/reads/bloodTestReads.js';
import { getSessions } from '../lib/reads/sessionReads.js';
import { getInventory, getOrders, getRates, enrichStock } from '../lib/reads/inventoryReads.js';
import type { QueryParams } from '../lib/queryFilter.js';

const csv = (s?: string): string[] | undefined =>
  s ? s.split(',').map((x) => x.trim()).filter(Boolean) : undefined;

const json = (data: unknown) => ({
  content: [{ type: 'text' as const, text: JSON.stringify(data) }],
});

/** YYYY-MM-DD for `months` months ago from now (UTC). */
const monthsAgo = (months: number): string => {
  const d = new Date();
  d.setUTCMonth(d.getUTCMonth() - months);
  return d.toISOString().slice(0, 10);
};

// Canonical blood-marker IDs grouped by panel — surfaced in the get_blood_markers
// arg description so clients query with valid IDs.
const MARKER_GLOSSARY = [
  'FBC: haemoglobin, haematocrit, rbc, wbc, platelets, mcv, mch, mchc, rdw, mpv, neutrophils, lymphocytes, monocytes, eosinophils, basophils, nucleated_rbc, reticulocyte_count_lnw, reticulocytes_abs_lnw',
  'U&E/renal: sodium, potassium, chloride, bicarbonate, urea, creatinine, egfr, aki_alert',
  'Bone/mineral: calcium, adjusted_calcium, phosphate, parathyroid_hormone, vitamin_d, alkaline_phosphatase',
  'Liver: albumin, globulin, total_protein, bilirubin, alt',
  'Haematinics/iron: iron, ferritin, transferrin, transferrin_saturation, holotranscobalamin, folic_acid',
  'Inflammation/glycaemic: crp, hba1c',
  'Virology/screening: hbv_surface_ab, hbv_surface_ag, hcv_ab, hiv_1_2_ab_ag, mrsa_screen, histo_nwlp',
].join(' | ');

const INSTRUCTIONS = [
  'Read-only access to a home-haemodialysis patient\'s treatment, blood-test, inventory and order data.',
  '',
  'Inventory & supply math (get_inventory): each item carries unit, box_size, per_session (effective per-session use), target_qty, and server-computed sessions_remaining + status. A typical session consumes 1 SAK dialysate, 1 cartridge, 1 saline, 1 on/off pack, 1 chlorine strip, and 2 needles; a PAK lasts ~10 sessions. status is red when sessions_remaining < 8 (~2 weeks), amber < 16 (~4 weeks), green otherwise (assuming ~4 sessions/week). Hospital items (heparin, EPO) have no per-session rate; their status is quantity-based. The per_session and target_qty shown reflect the patient\'s configured supply rates (their personal overrides where set, otherwise standard defaults).',
  '',
  'Orders (get_orders): history lists fulfilled deliveries (newest first); current_order is the single open order for the active cycle (null if none placed). Quantities include a box count.',
  '',
  'Blood markers (get_blood_markers): query by marker ID (see the marker arg for the full glossary by panel). Each row already includes unit and reference range (ref_low/ref_high), so out-of-range can be read directly or via get_out_of_range_markers.',
].join('\n');

const bloodArgs = {
  marker: z.string().optional().describe(
    `Marker ID(s), comma-separated. Valid IDs by panel — ${MARKER_GLOSSARY}. Symptom hints: itching→phosphate,calcium; fatigue→haemoglobin,ferritin; cramps→potassium,calcium; swelling→albumin,sodium.`,
  ),
  phase: z.string().optional().describe('One or more of: admission, in-center-hd, home-hd (comma-separated).'),
  from: z.string().optional().describe('Inclusive start, YYYY-MM or YYYY-MM-DD.'),
  to: z.string().optional().describe('Inclusive end, YYYY-MM or YYYY-MM-DD.'),
};

export function buildMcpServer(): McpServer {
  const server = new McpServer(
    { name: 'HD Tracker (read)', version: '1.0.0' },
    { instructions: INSTRUCTIONS },
  );

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
    {
      description:
        'Current consumable stock with per-item unit, box size, per-session use, target, and computed sessions_remaining + status (red<8 / amber<16 / green sessions). Plus order cycle and PAK status.',
      inputSchema: {},
    },
    async () => {
      const [inv, rates] = await Promise.all([getInventory(), getRates()]);
      return json({
        items: enrichStock(inv.stock, rates),
        cycle: inv.cycle,
        pak_installed_at: inv.pak_installed_at,
        pak_sessions: inv.pak_sessions,
        pak_avg_sessions: inv.pak_avg_sessions,
      });
    },
  );

  server.registerTool(
    'get_orders',
    {
      description:
        'Recent supply orders/deliveries. history = fulfilled deliveries (newest first, each with a box count); current_order = the one open order for this cycle (null if none placed). Defaults to the last 3 months.',
      inputSchema: {
        from: z.string().optional().describe('Inclusive start date YYYY-MM-DD. Default: 3 months ago.'),
        to: z.string().optional().describe('Inclusive end date YYYY-MM-DD.'),
        limit: z.number().int().positive().optional().describe('Cap history to newest N; overrides the date window.'),
      },
    },
    async ({ from, to, limit }) =>
      json(await getOrders({ from: limit != null ? from : (from ?? monthsAgo(3)), to, limit })),
  );

  return server;
}
