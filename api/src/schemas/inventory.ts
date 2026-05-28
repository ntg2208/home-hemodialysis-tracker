import { z } from 'zod';

export const EventBodySchema = z.object({
  type: z.enum(['session', 'manual', 'stock_count']),
  deltas: z.record(z.string(), z.number()),
  note: z.string().optional(),
});
export type EventBody = z.infer<typeof EventBodySchema>;

export const ConfirmOrderBodySchema = z.object({
  call_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'call_date must be YYYY-MM-DD'),
  order: z.record(z.string(), z.number().int().nonnegative()),
});
export type ConfirmOrderBody = z.infer<typeof ConfirmOrderBodySchema>;

export const ApplyDeliveryBodySchema = z.object({
  adjustments: z.record(z.string(), z.number().int().nonnegative()).optional(),
});
export type ApplyDeliveryBody = z.infer<typeof ApplyDeliveryBodySchema>;

const CycleSchema = z.object({
  call_date: z.string(),
  delivery_date: z.string(),
  order: z.record(z.string(), z.number()).optional(),
  order_placed_at: z.string().nullable(),
  delivery_applied_at: z.string().nullable(),
});
export type Cycle = z.infer<typeof CycleSchema>;

export const StockGetResponseSchema = z.object({
  stock: z.record(z.string(), z.number()),
  cycle: CycleSchema.nullable(),
});
export type StockGetResponse = z.infer<typeof StockGetResponseSchema>;
