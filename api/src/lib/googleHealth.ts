// Google Health API data types to sync.
// Verify slugs at https://developers.google.com/health/data-types before first deploy.
export const SYNC_TYPES = ['steps', 'resting-heart-rate', 'sleep', 'oxygen-saturation'] as const;
export type SyncType = (typeof SYNC_TYPES)[number];

const TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token';
const HEALTH_BASE = 'https://health.googleapis.com/v4';

// Scopes — verify at https://developers.google.com/health/scopes
const SCOPES = [
  'https://www.googleapis.com/auth/googlehealth.activityandfitness',
  'https://www.googleapis.com/auth/googlehealth.healthmetrics',
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
    body: JSON.stringify({ start_time: startDate, end_time: endDate }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`fetchDailyRollUp(${dataType}) failed: ${res.status} ${text}`);
  }
  return res.json();
}
