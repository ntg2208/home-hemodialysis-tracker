import { describe, it, expect } from 'vitest';
import { withRetry } from './withRetry';

const noSleep = () => Promise.resolve();

describe('withRetry', () => {
  it('returns the result without retrying when the first attempt succeeds', async () => {
    let attempts = 0;
    const result = await withRetry(
      async () => { attempts++; return 'ok'; },
      { retries: 2, sleep: noSleep },
    );
    expect(result).toBe('ok');
    expect(attempts).toBe(1);
  });

  it('retries on a retryable error then resolves', async () => {
    let attempts = 0;
    const result = await withRetry(
      async () => {
        attempts++;
        if (attempts < 3) throw new Error('boom');
        return 'recovered';
      },
      { retries: 2, sleep: noSleep, shouldRetry: () => true },
    );
    expect(result).toBe('recovered');
    expect(attempts).toBe(3);
  });

  it('does not retry when shouldRetry returns false', async () => {
    let attempts = 0;
    await expect(
      withRetry(
        async () => { attempts++; throw new Error('fatal'); },
        { retries: 3, sleep: noSleep, shouldRetry: () => false },
      ),
    ).rejects.toThrow('fatal');
    expect(attempts).toBe(1);
  });

  it('throws the last error after exhausting all retries', async () => {
    let attempts = 0;
    await expect(
      withRetry(
        async () => { attempts++; throw new Error(`fail-${attempts}`); },
        { retries: 2, sleep: noSleep, shouldRetry: () => true },
      ),
    ).rejects.toThrow('fail-3');
    expect(attempts).toBe(3); // 1 initial + 2 retries
  });

  it('waits the configured delay between attempts', async () => {
    const slept: number[] = [];
    let attempts = 0;
    await withRetry(
      async () => { attempts++; if (attempts < 3) throw new Error('x'); return 1; },
      { retries: 2, delays: [10, 50], sleep: (ms) => { slept.push(ms); return Promise.resolve(); }, shouldRetry: () => true },
    );
    expect(slept).toEqual([10, 50]);
  });
});
