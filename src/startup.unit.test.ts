import { describe, expect, it } from 'vitest';
import { resolveStartup } from './startup';

describe('resolveStartup', () => {
  it('starts with email and password when no session is saved', () => {
    const decision = resolveStartup(
      { GARMIN_EMAIL: 'runner@example.com', GARMIN_PASSWORD: 'secret' },
      false,
    );

    expect(decision).toMatchObject({
      kind: 'start',
      email: 'runner@example.com',
      password: 'secret',
    });
  });

  it('starts from a saved session without any credentials', () => {
    const decision = resolveStartup({}, true);

    expect(decision).toMatchObject({ kind: 'start', email: undefined, password: undefined });
  });

  it('refuses to start without credentials or a saved session and points to setup', () => {
    const decision = resolveStartup({ GARMIN_EMAIL: 'runner@example.com' }, false);

    expect(decision.kind).toBe('error');
    expect(decision.kind === 'error' && decision.message).toContain('garmin-connect-mcp setup');
  });
});
