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

  it('is not read-only unless asked', () => {
    expect(resolveStartup({}, true)).toMatchObject({ kind: 'start', isReadOnly: false });
    expect(resolveStartup({ GARMIN_READ_ONLY: 'false' }, true)).toMatchObject({ isReadOnly: false });
  });

  it.each(['true', 'TRUE', '1', 'yes'])('turns on read-only mode for GARMIN_READ_ONLY=%s', (value) => {
    expect(resolveStartup({ GARMIN_READ_ONLY: value }, true)).toMatchObject({
      kind: 'start',
      isReadOnly: true,
    });
  });

  it('refuses to start without credentials or a saved session and points to setup', () => {
    const decision = resolveStartup({ GARMIN_EMAIL: 'runner@example.com' }, false);

    expect(decision.kind).toBe('error');
    expect(decision.kind === 'error' && decision.message).toContain('garmin-connect-mcp setup');
  });
});
