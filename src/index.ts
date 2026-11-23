import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { GarminClient, hasSavedSession } from './client';
import { isSetupCommand, runSetup } from './setup-cli';
import { resolveStartup } from './startup';
import { registerAllTools } from './tools';

async function startServer(): Promise<void> {
  const decision = resolveStartup(process.env, hasSavedSession());

  if (decision.kind === 'error') {
    console.error(decision.message);
    process.exit(1);
  }

  const { email, password } = decision;

  const server = new McpServer({
    name: 'garmin-connect-mcp',
    version: '1.2.0',
  });

  const client = new GarminClient(email, password);

  registerAllTools(server, client, { isReadOnly: decision.isReadOnly });

  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('Garmin Connect MCP server running on stdio');
}

async function main(): Promise<void> {
  if (isSetupCommand(process.argv)) {
    await runSetup();
    return;
  }

  await startServer();
}

main().catch((error) => {
  console.error('Fatal error starting server:', error);
  process.exit(1);
});
