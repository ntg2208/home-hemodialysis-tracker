import { cloudGet, cloudPost, CloudRunError } from '../../api/cloudRun';
import type { AuthSettings } from '../../auth/storage';
import { InventoryResponseSchema, OkResponseSchema, type InventoryResponse } from './schemas';

export { CloudRunError as ApiError };

export async function fetchInventory(auth: AuthSettings): Promise<InventoryResponse> {
  const data = await cloudGet<unknown>(auth, '/api/inventory');
  const parsed = InventoryResponseSchema.safeParse(data);
  if (!parsed.success) throw new CloudRunError('bad_data', 'Inventory response shape mismatch.');
  return parsed.data;
}

export async function logEvent(
  auth: AuthSettings,
  type: 'session' | 'manual' | 'stock_count',
  deltas: Record<string, number>,
  note?: string,
): Promise<void> {
  const data = await cloudPost<unknown>(auth, '/api/inventory/event', { type, deltas, note });
  const parsed = OkResponseSchema.safeParse(data);
  if (!parsed.success) throw new CloudRunError('bad_data', 'Unexpected event response.');
}

export async function confirmOrder(
  auth: AuthSettings,
  call_date: string,
  order: Record<string, number>,
): Promise<void> {
  const data = await cloudPost<unknown>(auth, '/api/inventory/confirm-order', { call_date, order });
  const parsed = OkResponseSchema.safeParse(data);
  if (!parsed.success) throw new CloudRunError('bad_data', 'Unexpected confirm-order response.');
}

export async function applyDelivery(
  auth: AuthSettings,
  adjustments?: Record<string, number>,
): Promise<void> {
  const data = await cloudPost<unknown>(auth, '/api/inventory/apply-delivery', { adjustments });
  const parsed = OkResponseSchema.safeParse(data);
  if (!parsed.success) throw new CloudRunError('bad_data', 'Unexpected apply-delivery response.');
}

export async function initCycle(auth: AuthSettings, call_date: string): Promise<void> {
  await confirmOrder(auth, call_date, {});
}
