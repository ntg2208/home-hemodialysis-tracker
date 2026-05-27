import type { MiddlewareHandler } from 'hono';

export function bearerAuth(getKey: () => string | undefined): MiddlewareHandler {
  return async (c, next) => {
    const key = getKey();
    if (!key) {
      return c.json({ error: 'server_misconfigured', message: 'API key env var not set.' }, 500);
    }
    const header = c.req.header('Authorization');
    if (header !== `Bearer ${key}`) {
      return c.json({ error: 'unauthorized' }, 401);
    }
    await next();
  };
}
