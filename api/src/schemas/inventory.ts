import { z } from 'zod';

export const EventBodySchema = z.object({
  type: z.enum(['session', 'manual', 'stock_count']),
  deltas: z.record(z.string(), z.number().int()),
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

export const CycleSchema = z.object({
  call_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  delivery_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  order: z.record(z.string(), z.number()).optional(),
  order_placed_at: z.string().nullable(),
  delivery_applied_at: z.string().nullable(),
});
export type Cycle = z.infer<typeof CycleSchema>;

export const SetPakInstallBodySchema = z.object({
  installed_at: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'installed_at must be YYYY-MM-DD'),
});
export type SetPakInstallBody = z.infer<typeof SetPakInstallBodySchema>;

export const StockGetResponseSchema = z.object({
  stock: z.record(z.string(), z.number()),
  cycle: CycleSchema.nullable(),
  pak_installed_at: z.string().nullable(),
  pak_sessions: z.number(),
});
export type StockGetResponse = z.infer<typeof StockGetResponseSchema>;
