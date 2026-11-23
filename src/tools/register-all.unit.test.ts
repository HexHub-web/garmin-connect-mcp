import { describe, expect, it } from 'vitest';
import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import type { GarminClient } from '../client';
import { registerAllTools } from './index';

const WRITE_TOOLS = [
  'set_activity_name',
  'create_manual_activity',
  'delete_activity',
  'add_weigh_in',
  'set_hydration',
  'set_blood_pressure',
  'add_gear_to_activity',
  'remove_gear_from_activity',
];

function registeredToolNames(isReadOnly: boolean): string[] {
  const names: string[] = [];
  const server = {
    registerTool: (name: string) => {
      names.push(name);
    },
  } as unknown as McpServer;

  registerAllTools(server, {} as GarminClient, { isReadOnly });
  return names;
}

describe('registerAllTools', () => {
  it('registers the write tools by default', () => {
    const names = registeredToolNames(false);

    expect(names).toEqual(expect.arrayContaining(WRITE_TOOLS));
    expect(names).toContain('get_daily_health_snapshot');
  });

  it('leaves out every tool that changes the Garmin account in read-only mode', () => {
    const readOnly = registeredToolNames(true);
    const all = registeredToolNames(false);

    expect(readOnly.filter((name) => WRITE_TOOLS.includes(name))).toEqual([]);
    expect(readOnly).toContain('get_daily_health_snapshot');
    expect(readOnly).toHaveLength(all.length - WRITE_TOOLS.length);
  });
});
