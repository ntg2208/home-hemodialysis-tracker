import {
  ErrorResponseSchema,
  GetResponseSchema,
  SaveReadingResponseSchema,
  SaveSessionResponseSchema,
  UpdateSessionResponseSchema,
  type GetResponse,
  type Reading,
  type Session,
  type Settings,
} from './schemas';
import { z } from 'zod';

export class ApiError extends Error {
  constructor(public code: string, message?: string) {
    super(message ?? code);
  }
}

async function postJson<T>(
  settings: Settings,
  action: string,
  data: Record<string, unknown>,
  responseSchema: z.ZodType<T>,
): Promise<T> {
  let res: Response;
  try {
    res = await fetch(settings.script_url, {
      method: 'POST',
      // text/plain keeps this a CORS "simple request" so the browser skips
      // the OPTIONS preflight that Apps Script's /exec does not handle.
      // The Apps Script doPost still parses e.postData.contents as JSON.
      headers: { 'Content-Type': 'text/plain;charset=utf-8' },
      body: JSON.stringify({ secret: settings.shared_secret, action, data }),
      redirect: 'follow',
    });
  } catch (e) {
    throw new ApiError('network_error', String(e));
  }

  let body: unknown;
  try {
    body = await res.json();
  } catch (e) {
    throw new ApiError('invalid_json', String(e));
  }

  const err = ErrorResponseSchema.safeParse(body);
  if (err.success) throw new ApiError(err.data.error);

  const parsed = responseSchema.safeParse(body);
  if (!parsed.success) {
    throw new ApiError('schema_mismatch', parsed.error.message);
  }
  return parsed.data;
}

export async function probe(settings: Settings): Promise<void> {
  // Cheapest GET — just confirms URL + secret are valid.
  const url = `${settings.script_url}?secret=${encodeURIComponent(settings.shared_secret)}`;
  let res: Response;
  try {
    res = await fetch(url);
  } catch (e) {
    throw new ApiError('network_error', String(e));
  }
  let body: unknown;
  try {
    body = await res.json();
  } catch {
    throw new ApiError('invalid_json', 'Backend returned non-JSON. Check deployment access setting.');
  }
  const err = ErrorResponseSchema.safeParse(body);
  if (err.success) throw new ApiError(err.data.error);
  const ok = GetResponseSchema.safeParse(stripEmptyRows(body));
  if (!ok.success) throw new ApiError('schema_mismatch', ok.error.message);
}

export async function getAll(settings: Settings): Promise<GetResponse> {
  const url = `${settings.script_url}?secret=${encodeURIComponent(settings.shared_secret)}`;
  let res: Response;
  try {
    res = await fetch(url);
  } catch (e) {
    throw new ApiError('network_error', String(e));
  }
  let body: unknown;
  try {
    body = await res.json();
  } catch (e) {
    throw new ApiError('invalid_json', String(e));
  }
  const err = ErrorResponseSchema.safeParse(body);
  if (err.success) throw new ApiError(err.data.error);
  // Defensive: the Sheet may contain phantom empty rows if the user cleared
  // cell contents instead of deleting the row. Drop rows missing the primary
  // key so a half-cleared Sheet doesn't fail the whole load.
  const cleaned = stripEmptyRows(body);
  const parsed = GetResponseSchema.safeParse(cleaned);
  if (!parsed.success) throw new ApiError('schema_mismatch', parsed.error.message);
  return parsed.data;
}

function stripEmptyRows(body: unknown): unknown {
  if (!body || typeof body !== 'object') return body;
  const b = body as { sessions?: unknown; readings?: unknown };
  const keep = (rows: unknown, idKey: string) =>
    Array.isArray(rows)
      ? rows.filter(r => r && typeof r === 'object' && typeof (r as Record<string, unknown>)[idKey] === 'string' && (r as Record<string, string>)[idKey] !== '')
      : rows;
  return { ...b, sessions: keep(b.sessions, 'session_id'), readings: keep(b.readings, 'reading_id') };
}

export async function saveSession(settings: Settings, session: Session): Promise<void> {
  await postJson(settings, 'save_session', session, SaveSessionResponseSchema);
}

export async function saveReading(settings: Settings, reading: Reading): Promise<void> {
  await postJson(settings, 'save_reading', reading, SaveReadingResponseSchema);
}

export async function updateSession(
  settings: Settings,
  patch: Partial<Session> & { session_id: string },
): Promise<void> {
  await postJson(settings, 'update_session', patch, UpdateSessionResponseSchema);
}
