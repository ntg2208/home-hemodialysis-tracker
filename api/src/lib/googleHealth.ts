// Order matters: cheap/sparse types first, the dense `heart-rate` LAST so that if a
// run is killed (timeout/OOM) the cheap types have already persisted their sync_state.
export const SYNC_TYPES = [
  'steps',
  'daily-resting-heart-rate',
  'sleep',
  'oxygen-saturation',
  'daily-heart-rate-variability',
  'heart-rate-variability',
  'respiratory-rate-sleep-summary',
  'daily-sleep-temperature-derivations',
  'heart-rate',
] as const;
export type SyncType = (typeof SYNC_TYPES)[number];

// Per-type fetch strategy. dailyRollUp supports interval types (≤90 days/call);
// list supports daily/sample/session types via filter expressions.
export type FetchStrategy =
  | { method: 'dailyRollUp' }
  | { method: 'list'; filterField: string; filterDateField: 'date' | 'civil_start_time' | 'civil_end_time' | 'civil_time' };

export const SYNC_TYPE_STRATEGY: Record<SyncType, FetchStrategy> = {
  'steps':                               { method: 'dailyRollUp' },
  'daily-resting-heart-rate':            { method: 'list', filterField: 'daily_resting_heart_rate',          filterDateField: 'date' },
  'sleep':                               { method: 'list', filterField: 'sleep',                             filterDateField: 'civil_end_time' },
  'oxygen-saturation':                   { method: 'list', filterField: 'oxygen_saturation',                 filterDateField: 'civil_time' },
  'daily-heart-rate-variability':        { method: 'list', filterField: 'daily_heart_rate_variability',      filterDateField: 'date' },
  'heart-rate-variability':              { method: 'list', filterField: 'heart_rate_variability',            filterDateField: 'civil_time' },
  'respiratory-rate-sleep-summary':      { method: 'list', filterField: 'respiratory_rate_sleep_summary',    filterDateField: 'civil_time' },
  'daily-sleep-temperature-derivations': { method: 'list', filterField: 'daily_sleep_temperature_derivations', filterDateField: 'date' },
  // Dense: ~30-50k samples/day. Safe because the daily scheduled sync only ever pulls ~1 day per run.
  'heart-rate':                          { method: 'list', filterField: 'heart_rate',                        filterDateField: 'civil_time' },
};

// The list-strategy types whose same-day ("today") values feed the energy-pacing
// morning call. All are method:'list' (no dailyRollUp). Excludes raw 'heart-rate'
// (huge, daytime/HR-ceiling concern only) and 'steps' (dailyRollUp, inherently T-1).
export const FRESHEN_TYPES = [
  'sleep',
  'daily-heart-rate-variability',
  'daily-resting-heart-rate',
  'respiratory-rate-sleep-summary',
  'daily-sleep-temperature-derivations',
] as const satisfies readonly SyncType[];


function parseCivilDate(date: string): { date: { year: number; month: number; day: number } } {
  const [year, month, day] = date.split('-').map(Number);
  return { date: { year, month, day } };
}

const TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token';
const HEALTH_BASE = 'https://health.googleapis.com/v4';

const SCOPES = [
  'https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly',
  'https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly',
  'https://www.googleapis.com/auth/googlehealth.sleep.readonly',
].join(' ');

export function buildOAuthUrl({
  clientId,
  redirectUri,
  state,
}: {
  clientId: string;
  redirectUri: string;
  state?: string;
}): string {
  const params = new URLSearchParams({
    client_id: clientId,
    redirect_uri: redirectUri,
    response_type: 'code',
    scope: SCOPES,
    access_type: 'offline',
    prompt: 'consent', // forces refresh_token to always be returned
  });
  if (state) params.set('state', state);
  return `https://accounts.google.com/o/oauth2/v2/auth?${params}`;
}

export async function exchangeCode({
  code,
  clientId,
  clientSecret,
  redirectUri,
}: {
  code: string;
  clientId: string;
  clientSecret: string;
  redirectUri: string;
}): Promise<{ accessToken: string; refreshToken: string }> {
  const res = await fetch(TOKEN_ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'authorization_code',
      code,
      redirect_uri: redirectUri,
      client_id: clientId,
      client_secret: clientSecret,
    }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Token exchange failed: ${res.status} ${text}`);
  }
  const data = (await res.json()) as Record<string, unknown>;
  if (typeof data['access_token'] !== 'string' || typeof data['refresh_token'] !== 'string') {
    throw new Error(
      `Token exchange response missing tokens. Present keys: ${Object.keys(data).join(', ')}`
    );
  }
  return { accessToken: data['access_token'], refreshToken: data['refresh_token'] };
}

export async function refreshAccessToken({
  refreshToken,
  clientId,
  clientSecret,
}: {
  refreshToken: string;
  clientId: string;
  clientSecret: string;
}): Promise<string> {
  const res = await fetch(TOKEN_ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'refresh_token',
      refresh_token: refreshToken,
      client_id: clientId,
      client_secret: clientSecret,
    }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Token refresh failed: ${res.status} ${text}`);
  }
  const data = (await res.json()) as Record<string, unknown>;
  if (typeof data['access_token'] !== 'string') {
    throw new Error(
      `Token refresh response missing access_token. Present keys: ${Object.keys(data).join(', ')}`
    );
  }
  return data['access_token'];
}

// Fetch a daily rollup for a single data type over a date range.
// Returns the raw API response — stored as-is in GCS.
export async function fetchDailyRollUp({
  accessToken,
  dataType,
  startDate,
  endDate,
}: {
  accessToken: string;
  dataType: string;
  startDate: string; // YYYY-MM-DD
  endDate: string;   // YYYY-MM-DD
}): Promise<unknown> {
  const url = `${HEALTH_BASE}/users/me/dataTypes/${dataType}/dataPoints:dailyRollUp`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      range: {
        start: parseCivilDate(startDate),
        end: parseCivilDate(endDate),
      },
    }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`fetchDailyRollUp(${dataType}) failed: ${res.status} ${text}`);
  }
  return res.json();
}

// Fetch all data points for a type using the list endpoint (with pagination).
// filterField: snake_case type name (e.g. 'daily_resting_heart_rate')
// filterDateField: which date sub-field to filter on
// startDate/endDate: YYYY-MM-DD inclusive range (endDate converted to exclusive internally)
export async function fetchListAll({
  accessToken,
  dataType,
  filterField,
  filterDateField,
  startDate,
  endDate,
}: {
  accessToken: string;
  dataType: string;
  filterField: string;
  filterDateField: 'date' | 'civil_start_time' | 'civil_end_time' | 'civil_time';
  startDate: string;
  endDate: string;  // inclusive
}): Promise<unknown[]> {
  const baseUrl = `${HEALTH_BASE}/users/me/dataTypes/${dataType}/dataPoints`;
  const filterKey = filterDateField === 'date'
    ? `${filterField}.date`
    : filterDateField === 'civil_start_time'
      ? `${filterField}.interval.civil_start_time`
      : filterDateField === 'civil_end_time'
        ? `${filterField}.interval.civil_end_time`
        : `${filterField}.sample_time.civil_time`;

  // Compute exclusive end date for filter
  const endExclusive = new Date(endDate);
  endExclusive.setUTCDate(endExclusive.getUTCDate() + 1);
  const endExclusiveStr = endExclusive.toISOString().slice(0, 10);

  const filter = `${filterKey} >= "${startDate}" AND ${filterKey} < "${endExclusiveStr}"`;

  const allPoints: unknown[] = [];
  let pageToken: string | undefined;

  do {
    const params = new URLSearchParams({ filter, pageSize: '10000' });
    if (pageToken) params.set('pageToken', pageToken);
    const res = await fetch(`${baseUrl}?${params}`, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (!res.ok) {
      const text = await res.text();
      throw new Error(`fetchList(${dataType}) failed: ${res.status} ${text}`);
    }
    const data = (await res.json()) as { dataPoints?: unknown[]; nextPageToken?: string };
    if (Array.isArray(data.dataPoints)) allPoints.push(...data.dataPoints);
    pageToken = data.nextPageToken;
  } while (pageToken);

  return allPoints;
}
