import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { GarminAuth, hasSavedSession } from './garmin-auth';

let tokenDir: string;

beforeEach(() => {
  tokenDir = fs.mkdtempSync(path.join(os.tmpdir(), 'garmin-auth-test-'));
});

afterEach(() => {
  fs.rmSync(tokenDir, { recursive: true, force: true });
});

describe('hasSavedSession', () => {
  it('is false when no OAuth1 token has been saved', () => {
    expect(hasSavedSession(tokenDir)).toBe(false);
  });

  it('is true once setup has saved an OAuth1 token', () => {
    fs.writeFileSync(
      path.join(tokenDir, 'oauth1_token.json'),
      JSON.stringify({ oauth_token: 't', oauth_token_secret: 's' }),
    );

    expect(hasSavedSession(tokenDir)).toBe(true);
  });
});

describe('GarminAuth without credentials', () => {
  it('asks the user to run setup instead of attempting a login', async () => {
    const auth = new GarminAuth(undefined, undefined, undefined, tokenDir);

    await expect(auth.request('/userprofile-service/socialProfile')).rejects.toThrow(
      'garmin-connect-mcp setup',
    );
  });
});
