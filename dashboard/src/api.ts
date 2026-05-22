import { ApiResponseSchema, type ApiResponse } from './schemas';

export type ApiErrorCode = 'unauthorized' | 'network' | 'bad_data' | 'server';

export class ApiError extends Error {
  constructor(public code: ApiErrorCode, message: string) {
    super(message);
    this.name = 'ApiError';
  }
}

export async function fetchAll(key: string): Promise<ApiResponse> {
  let res: Response;
  try {
    res = await fetch('/api/blood-tests', {
      headers: { Authorization: `Bearer ${key}` },
    });
  } catch {
    throw new ApiError('network', 'Could not reach the server.');
  }

  if (res.status === 401) throw new ApiError('unauthorized', 'Access key rejected.');
  if (!res.ok) throw new ApiError('server', `Server error (${res.status}).`);

  let body: unknown;
  try {
    body = await res.json();
  } catch {
    throw new ApiError('bad_data', 'Server returned an invalid response.');
  }

  const parsed = ApiResponseSchema.safeParse(body);
  if (!parsed.success) {
    throw new ApiError('bad_data', 'Response did not match the expected shape.');
  }
  return parsed.data;
}
