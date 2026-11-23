import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { GarminClient } from '../client';
import { registerActivityTools } from './activities.tools';
import { registerHealthTools } from './health.tools';
import { registerTrendTools } from './trends.tools';
import { registerSleepTools } from './sleep.tools';
import { registerBodyTools } from './body.tools';
import { registerPerformanceTools } from './performance.tools';
import { registerProfileTools } from './profile.tools';
import { registerRangeTools } from './range.tools';
import { registerSnapshotTools } from './snapshot.tools';
import { registerTrainingTools } from './training.tools';
import { registerWellnessTools } from './wellness.tools';
import { registerChallengeTools } from './challenges.tools';
import { registerWriteTools } from './write.tools';

export type RegisterAllToolsOptions = {
  isReadOnly: boolean;
};

export function registerAllTools(
  server: McpServer,
  client: GarminClient,
  options: RegisterAllToolsOptions,
): void {
  registerActivityTools(server, client);
  registerHealthTools(server, client);
  registerTrendTools(server, client);
  registerSleepTools(server, client);
  registerBodyTools(server, client);
  registerPerformanceTools(server, client);
  registerProfileTools(server, client);
  registerRangeTools(server, client);
  registerSnapshotTools(server, client);
  registerTrainingTools(server, client);
  registerWellnessTools(server, client);
  registerChallengeTools(server, client);

  if (!options.isReadOnly) {
    registerWriteTools(server, client);
  }
}
