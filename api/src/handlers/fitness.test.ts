import { describe, it, expect, vi } from 'vitest';
import { runSync, clampSyncEnd, freshenToday, type SyncDeps } from './fitness.js';
import { SYNC_TYPES } from '../lib/googleHealth.js';

describe('clampSyncEnd', () => {
  const yest = '2026-06-19';
  it('defaults to yesterday when no/invalid param', () => {
    expect(clampSyncEnd(undefined, yest)).toBe(yest);
    expect(clampSyncEnd('garbage', yest)).toBe(yest);
    expect(clampSyncEnd('2026-6-1', yest)).toBe(yest);
  });
  it('uses a valid date that is on/before yesterday', () => {
    expect(clampSyncEnd('2026-06-04', yest)).toBe('2026-06-04');
    expect(clampSyncEnd('2026-06-19', yest)).toBe('2026-06-19');
  });
  it('clamps a future date to yesterday', () => {
    expect(clampSyncEnd('2026-06-25', yest)).toBe(yest);
  });
});

// Build a set of fake deps. `failOn` names data types whose fetch should throw.
function makeDeps(failOn: string[] = []): { deps: SyncDeps; states: Array<Record<string, string>>; uploads: string[] } {
  const states: Array<Record<string, string>> = [];
  const uploads: string[] = [];
  const deps: SyncDeps = {
    readSyncState: vi.fn().mockResolvedValue({}),
    writeSyncState: vi.fn(async (s) => { states.push({ ...s }); }),
    uploadJson: vi.fn(async (path: string) => { uploads.push(path); }),
    fetchRollUp: vi.fn(async ({ dataType }) => {
      if (failOn.includes(dataType)) throw new Error(`boom ${dataType}`);
      return { rollupDataPoints: [] };
    }),
    fetchList: vi.fn(async ({ dataType }) => {
      if (failOn.includes(dataType)) throw new Error(`boom ${dataType}`);
      return [];
    }),
  };
  return { deps, states, uploads };
}

const OPTS = { backfillDays: 3, lastInclusiveDate: '2026-05-30' };

describe('runSync per-type isolation', () => {
  it('records an error for the failing type but still processes the rest', async () => {
    const { deps } = makeDeps(['sleep']);
    const summary = await runSync(deps, OPTS);

    expect(summary['sleep'].status).toBe('error');
    expect(summary['sleep'].error).toContain('boom sleep');

    // A type that comes AFTER sleep in SYNC_TYPES still succeeds — the loop is not aborted.
    expect(summary['oxygen-saturation'].status).toBe('ok');
    expect(summary['steps'].status).toBe('ok');
  });

  it('does not advance sync_state for a failed type, but does for successful ones', async () => {
    const { deps, states } = makeDeps(['sleep']);
    await runSync(deps, OPTS);

    const finalState = states[states.length - 1];
    expect(finalState['steps']).toBe('2026-05-30');
    expect(finalState['oxygen-saturation']).toBe('2026-05-30');
    expect(finalState['sleep']).toBeUndefined();
  });

  it('persists sync_state after each successful type (incremental, survives later failure)', async () => {
    // heart-rate is last in SYNC_TYPES; if it throws, every earlier type must already be persisted.
    const { deps, states } = makeDeps(['heart-rate']);
    await runSync(deps, OPTS);

    // writeSyncState called once per successful type (all but heart-rate).
    const successfulCount = SYNC_TYPES.length - 1;
    expect(states.length).toBe(successfulCount);
    expect(states[states.length - 1]['heart-rate']).toBeUndefined();
  });

  it('marks every type ok when nothing fails', async () => {
    const { deps } = makeDeps([]);
    const summary = await runSync(deps, OPTS);
    for (const t of SYNC_TYPES) expect(summary[t].status).toBe('ok');
  });
});

describe('runSync onlyType selector', () => {
  it('processes a single type when onlyType is set', async () => {
    const { deps } = makeDeps([]);
    const summary = await runSync(deps, { ...OPTS, onlyType: 'heart-rate' });
    expect(Object.keys(summary)).toEqual(['heart-rate']);
  });
});

describe('runSync backfill window', () => {
  it('uses the backfill window when no prior state exists', async () => {
    const { deps } = makeDeps([]);
    const summary = await runSync(deps, { backfillDays: 3, lastInclusiveDate: '2026-05-30', onlyType: 'steps' });
    // 3-day window ending 2026-05-30 → starts 2026-05-28.
    expect(summary['steps'].from).toBe('2026-05-28');
    expect(summary['steps'].to).toBe('2026-05-30');
  });

  it('resumes from the day after last sync when state exists', async () => {
    const { deps } = makeDeps([]);
    (deps.readSyncState as ReturnType<typeof vi.fn>).mockResolvedValue({ steps: '2026-05-29' });
    const summary = await runSync(deps, { backfillDays: 365, lastInclusiveDate: '2026-05-30', onlyType: 'steps' });
    expect(summary['steps'].from).toBe('2026-05-30');
  });

  it('reports days_covered 0 when already caught up', async () => {
    const { deps } = makeDeps([]);
    (deps.readSyncState as ReturnType<typeof vi.fn>).mockResolvedValue({ steps: '2026-05-30' });
    const summary = await runSync(deps, { backfillDays: 365, lastInclusiveDate: '2026-05-30', onlyType: 'steps' });
    expect(summary['steps'].days_covered).toBe(0);
  });
});

describe('freshenToday', () => {
  it('fetches a single day, writes to the today/ namespace, and never advances a cursor', async () => {
    const uploads: Array<{ path: string; data: any }> = [];
    const deps = {
      uploadJson: vi.fn(async (path: string, data: unknown) => {
        uploads.push({ path, data: data as any });
      }),
      fetchList: vi.fn(async () => [{ a: 1 }, { a: 2 }]),
    };

    const summary = await freshenToday(deps, { types: ['sleep'], date: '2026-06-22' });

    expect(deps.fetchList).toHaveBeenCalledWith(
      expect.objectContaining({ dataType: 'sleep', startDate: '2026-06-22', endDate: '2026-06-22' }),
    );
    expect(uploads).toHaveLength(1);
    expect(uploads[0].path).toBe('raw/sleep/today/2026-06-22.json');
    expect(uploads[0].data.count).toBe(2);
    expect(uploads[0].data.date).toBe('2026-06-22');
    expect(summary).toEqual({ sleep: { count: 2, status: 'ok' } });
    // FreshenDeps deliberately has no readSyncState/writeSyncState — the cursor cannot move.
    expect('readSyncState' in deps).toBe(false);
    expect('writeSyncState' in deps).toBe(false);
  });

  it('records a non-list type as an error result, without throwing', async () => {
    const deps = { uploadJson: vi.fn(async () => {}), fetchList: vi.fn(async () => []) };
    // 'steps' is the only dailyRollUp type in SYNC_TYPE_STRATEGY.
    const summary = await freshenToday(deps, { types: ['steps'], date: '2026-06-22' });
    expect(summary['steps'].status).toBe('error');
    expect(deps.fetchList).not.toHaveBeenCalled();
  });

  it('isolates a failing type instead of aborting the rest', async () => {
    const deps = {
      uploadJson: vi.fn(async () => {}),
      fetchList: vi.fn(async () => {
        throw new Error('boom');
      }),
    };
    const summary = await freshenToday(deps, { types: ['sleep'], date: '2026-06-22' });
    expect(summary['sleep'].status).toBe('error');
    const result = summary['sleep'];
    if (result.status === 'error') expect(result.error).toBe('boom');
  });
});
