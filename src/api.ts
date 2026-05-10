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
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ secret: settings.shared_secret, action, data }),
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
    throw new ApiError('invalid_response', 'Backend returned non-JSON. Check deployment access setting.');
  }
  const err = ErrorResponseSchema.safeParse(body);
  if (err.success) throw new ApiError(err.data.error);
  const ok = GetResponseSchema.safeParse(body);
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
  const parsed = GetResponseSchema.safeParse(body);
  if (!parsed.success) throw new ApiError('schema_mismatch', parsed.error.message);
  return parsed.data;
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
