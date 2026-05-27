import { cloudGet, CloudRunError } from '../../api/cloudRun';
import type { AuthSettings } from '../../auth/storage';
import { ApiResponseSchema, type ApiResponse } from './schemas';

export { CloudRunError as ApiError };

export async function fetchAll(auth: AuthSettings): Promise<ApiResponse> {
  const data = await cloudGet<unknown>(auth, '/api/blood-tests');
  const parsed = ApiResponseSchema.safeParse(data);
  if (!parsed.success) {
    throw new CloudRunError('bad_data', 'Response did not match the expected shape.');
  }
  return parsed.data;
}
