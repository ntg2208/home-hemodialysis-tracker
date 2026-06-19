import { Hono } from 'hono';
import { RESPONSE_ALREADY_SENT } from '@hono/node-server/utils/response';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { buildMcpServer } from './server.js';

export const mcpRoute = new Hono().post('/', async (c) => {
  const { incoming, outgoing } = c.env as unknown as {
    incoming: IncomingMessage;
    outgoing: ServerResponse;
  };
  const body = await c.req.json().catch(() => undefined);

  const server = buildMcpServer();
  const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
  outgoing.on('close', () => { transport.close(); server.close(); });
  await server.connect(transport);
  await transport.handleRequest(incoming, outgoing, body);
  return RESPONSE_ALREADY_SENT;
});
