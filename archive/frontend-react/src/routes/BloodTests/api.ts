import { cloudGet, CloudRunError } from '../../api/cloudRun';
import type { AuthSettings } from '../../auth/storage';
import { ApiResponseSchema, type ApiResponse } from './schemas';

export { CloudRunError as ApiError };

export async function fetchRange(
  auth: AuthSettings,
  range: { from?: string; to?: string },
): Promise<ApiResponse> {
  const params: Record<string, string> = {};
  if (range.from) params.from = range.from;
  if (range.to) params.to = range.to;
  const data = await cloudGet<unknown>(auth, '/api/blood-tests', params);
  const parsed = ApiResponseSchema.safeParse(data);
  if (!parsed.success) {
    throw new CloudRunError('bad_data', 'Response did not match the expected shape.');
  }
  return parsed.data;
}
