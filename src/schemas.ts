import { z } from 'zod';

// Backend stores all numerics as text (per appendAsText_ patch). Use z.coerce.number()
// so GET responses parse correctly whether the value comes back as string or number.

export const SessionSchema = z.object({
  session_id: z.string().min(1),
  date: z.string().min(1),
  pre_weight: z.coerce.number().optional(),
  uf_goal: z.coerce.number().optional(),
  uf_rate: z.coerce.number().optional(),
  pre_bp_sys: z.coerce.number().int().optional(),
  pre_bp_dia: z.coerce.number().int().optional(),
  pre_pulse: z.coerce.number().int().optional(),
  post_weight: z.coerce.number().optional(),
  post_bp_sys: z.coerce.number().int().optional(),
  post_bp_dia: z.coerce.number().int().optional(),
  post_pulse: z.coerce.number().int().optional(),
  duration_min: z.coerce.number().int().optional(),
  dialysate_volume: z.coerce.number().optional(),
  total_uf: z.coerce.number().optional(),
  blood_processed: z.coerce.number().optional(),
  created_at: z.string().optional(),
});
export type Session = z.infer<typeof SessionSchema>;

export const ReadingSchema = z.object({
  reading_id: z.string().min(1),
  session_id: z.string().min(1),
  seq: z.coerce.number().int(),
  time: z.string(),
  bp_sys: z.coerce.number().int().optional(),
  bp_dia: z.coerce.number().int().optional(),
  pulse: z.coerce.number().int().optional(),
  blood_flow: z.coerce.number().int().optional(),
  venous_pressure: z.coerce.number().int().optional(),
  arterial_pressure: z.coerce.number().int().optional(),
  note: z.string().optional(),
  created_at: z.string().optional(),
});
export type Reading = z.infer<typeof ReadingSchema>;

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

export const Settings = z.object({
  script_url: z.string().url(),
  shared_secret: z.string().min(1),
});
export type Settings = z.infer<typeof Settings>;
