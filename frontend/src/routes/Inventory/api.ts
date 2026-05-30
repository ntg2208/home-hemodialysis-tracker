import { cloudGet, cloudPost, CloudRunError } from '../../api/cloudRun';
import type { AuthSettings } from '../../auth/storage';
import { InventoryResponseSchema, OkResponseSchema, DeliveriesResponseSchema, type InventoryResponse, type DeliveriesResponse } from './schemas';

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
  delivery_date?: string,
): Promise<void> {
  const body: Record<string, unknown> = { call_date, order };
  if (delivery_date) body.delivery_date = delivery_date;
  const data = await cloudPost<unknown>(auth, '/api/inventory/confirm-order', body);
  const parsed = OkResponseSchema.safeParse(data);
  if (!parsed.success) throw new CloudRunError('bad_data', 'Unexpected confirm-order response.');
}

export async function updateCycleDates(
  auth: AuthSettings,
  call_date: string,
  delivery_date: string,
): Promise<void> {
  const data = await cloudPost<unknown>(auth, '/api/inventory/update-cycle-dates', { call_date, delivery_date });
  const parsed = OkResponseSchema.safeParse(data);
  if (!parsed.success) throw new CloudRunError('bad_data', 'Unexpected update-cycle-dates response.');
}

export async function applyDelivery(
  auth: AuthSettings,
  adjustments?: Record<string, number>,
): Promise<void> {
  const data = await cloudPost<unknown>(auth, '/api/inventory/apply-delivery', { adjustments });
  const parsed = OkResponseSchema.safeParse(data);
  if (!parsed.success) throw new CloudRunError('bad_data', 'Unexpected apply-delivery response.');
}

export async function initCycle(auth: AuthSettings, call_date: string, delivery_date?: string): Promise<void> {
  await confirmOrder(auth, call_date, {}, delivery_date);
}

export async function fetchDeliveries(auth: AuthSettings): Promise<DeliveriesResponse> {
  const data = await cloudGet<unknown>(auth, '/api/inventory/deliveries');
  const parsed = DeliveriesResponseSchema.safeParse(data);
  if (!parsed.success) throw new CloudRunError('bad_data', 'Deliveries response shape mismatch.');
  return parsed.data;
}

export async function setPakInstall(auth: AuthSettings, installed_at: string): Promise<void> {
  const data = await cloudPost<unknown>(auth, '/api/inventory/set-pak-install', { installed_at });
  const parsed = OkResponseSchema.safeParse(data);
  if (!parsed.success) throw new CloudRunError('bad_data', 'Unexpected set-pak-install response.');
}
