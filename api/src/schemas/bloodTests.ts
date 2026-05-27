import { z } from 'zod';

export const PHASES = ['admission', 'in-center-hd', 'home-hd'] as const;

export const BloodTestRowSchema = z.object({
  marker: z.string().min(1),
  datetime: z.string().min(1),
  value: z.number(),
  unit: z.string(),
  ref_low: z.number().nullable(),
  ref_high: z.number().nullable(),
  timing: z.enum(['pre', 'post', '']),
  note: z.string(),
  source: z.string(),
  lab_id: z.string(),
  phase: z.enum(PHASES),
  created_at: z.string(),
  qualitative: z.boolean(),
});

export type BloodTestRow = z.infer<typeof BloodTestRowSchema>;

export const BloodTestRowInputSchema = BloodTestRowSchema.omit({ created_at: true });
export type BloodTestRowInput = z.infer<typeof BloodTestRowInputSchema>;

export const PostBodySchema = z.object({
  rows: z.array(BloodTestRowInputSchema).min(1).max(100),
});
export type PostBody = z.infer<typeof PostBodySchema>;
