export type StartupEnv = {
  GARMIN_EMAIL?: string;
  GARMIN_PASSWORD?: string;
};

export type StartupDecision =
  | { kind: 'start'; email?: string; password?: string }
  | { kind: 'error'; message: string };

export function resolveStartup(env: StartupEnv, hasSavedSession: boolean): StartupDecision {
  const email = env.GARMIN_EMAIL || undefined;
  const password = env.GARMIN_PASSWORD || undefined;

  if ((email && password) || hasSavedSession) {
    return { kind: 'start', email, password };
  }

  return {
    kind: 'error',
    message:
      'Error: no saved Garmin session and GARMIN_EMAIL/GARMIN_PASSWORD are not both set.\n' +
      'Sign in once from a terminal so the password never has to live in your MCP config:\n' +
      '  garmin-connect-mcp setup   (from a source checkout: node build/index.js setup)\n' +
      'Alternatively set GARMIN_EMAIL and GARMIN_PASSWORD when adding this MCP server.',
  };
}
