import { z } from 'zod';

// Firestore stores all numerics as real numbers. Use z.number() for strict parsing.

export const SessionSchema = z.object({
  session_id: z.string().min(1),
  date: z.string().min(1),
  pre_weight: z.number().optional(),
  uf_goal: z.number().optional(),
  uf_rate: z.number().optional(),
  pre_bp_sys: z.number().int().optional(),
  pre_bp_dia: z.number().int().optional(),
  pre_pulse: z.number().int().optional(),
  post_weight: z.number().optional(),
  post_bp_sys: z.number().int().optional(),
  post_bp_dia: z.number().int().optional(),
  post_pulse: z.number().int().optional(),
  duration_min: z.number().int().optional(),
  dialysate_volume: z.number().optional(),
  total_uf: z.number().optional(),
  blood_processed: z.number().optional(),
  created_at: z.string().optional(),
});
export type Session = z.infer<typeof SessionSchema>;

export const ReadingSchema = z.object({
  reading_id: z.string().min(1),
  session_id: z.string().min(1),
  seq: z.number().int(),
  time: z.string(),
  bp_sys: z.number().int().optional(),
  bp_dia: z.number().int().optional(),
  pulse: z.number().int().optional(),
  blood_flow: z.number().int().optional(),
  venous_pressure: z.number().int().optional(),
  arterial_pressure: z.number().int().optional(),
  note: z.string().optional(),
  created_at: z.string().optional(),
});
export type Reading = z.infer<typeof ReadingSchema>;

export type PendingReading = Reading & {
  status: 'pending' | 'saved' | 'error';
  errorMsg?: string;
};

export const GetResponseSchema = z.object({
  ok: z.literal(true),
  sessions: z.array(SessionSchema),
  readings: z.array(ReadingSchema),
});
export type GetResponse = z.infer<typeof GetResponseSchema>;

export const SaveSessionResponseSchema = z.object({
  ok: z.literal(true),
  session_id: z.string(),
});

export const SaveReadingResponseSchema = z.object({
  ok: z.literal(true),
  reading_id: z.string(),
});

export const UpdateSessionResponseSchema = z.object({
  ok: z.literal(true),
});

export const ErrorResponseSchema = z.object({
  ok: z.literal(false),
  error: z.string(),
});
