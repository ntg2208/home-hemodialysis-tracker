import { SecretManagerServiceClient } from '@google-cloud/secret-manager';

const PROJECT = process.env.GCP_PROJECT ?? 'homehd-personal';
const SECRET_NAME = 'health-oauth-refresh-token';

let _client: SecretManagerServiceClient | null = null;
function getClient(): SecretManagerServiceClient {
  if (!_client) _client = new SecretManagerServiceClient();
  return _client;
}

function secretVersionName(version = 'latest'): string {
  return `projects/${PROJECT}/secrets/${SECRET_NAME}/versions/${version}`;
}

function secretParentName(): string {
  return `projects/${PROJECT}/secrets/${SECRET_NAME}`;
}

export async function getRefreshToken(): Promise<string> {
  const [version] = await getClient().accessSecretVersion({
    name: secretVersionName(),
  });
  const payload = version.payload?.data;
  if (!payload) throw new Error('Refresh token secret is empty');
  return Buffer.isBuffer(payload)
    ? payload.toString('utf8')
    : String(payload);
}

export async function setRefreshToken(token: string): Promise<void> {
  await getClient().addSecretVersion({
    parent: secretParentName(),
    payload: { data: Buffer.from(token, 'utf8') },
  });
}
