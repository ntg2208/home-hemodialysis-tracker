import { z } from 'zod';

export const CycleSchema = z.object({
  call_date: z.string(),
  delivery_date: z.string(),
  order: z.record(z.string(), z.number()).optional(),
  order_placed_at: z.string().nullable(),
  delivery_applied_at: z.string().nullable(),
});
export type Cycle = z.infer<typeof CycleSchema>;

export const InventoryResponseSchema = z.object({
  stock: z.record(z.string(), z.number()),
  cycle: CycleSchema.nullable(),
});
export type InventoryResponse = z.infer<typeof InventoryResponseSchema>;

export const OkResponseSchema = z.object({ ok: z.literal(true) });
export type OkResponse = z.infer<typeof OkResponseSchema>;
