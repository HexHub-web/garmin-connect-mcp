import { describe, expect, it } from 'vitest';
import { createMutableOutput, isSetupCommand, runSetup } from './setup-cli';

describe('setup command', () => {
  it('recognizes the documented setup argument', () => {
    expect(isSetupCommand(['node', 'build/index.js', 'setup'])).toBe(true);
    expect(isSetupCommand(['node', 'build/index.js'])).toBe(false);
  });

  it('prompts for the MFA code when authentication asks for it', async () => {
    const questions: string[] = [];
    const logs: string[] = [];
    let exitCode: number | undefined;

    await runSetup({
      env: { GARMIN_EMAIL: 'runner@example.com', GARMIN_PASSWORD: 'secret' },
      ask: async (question) => {
        questions.push(question);
        return '654321';
      },
      askSecret: async () => {
        throw new Error('password comes from the environment in this test');
      },
      close: () => {},
      log: (message) => logs.push(message),
      exit: (code) => {
        exitCode = code;
      },
      authenticate: async (_email, _password, promptMfa) => {
        const code = await promptMfa();
        expect(code).toBe('654321');
        return 'Ada';
      },
    });

    expect(questions).toEqual(['MFA code: ']);
    expect(logs.some((line) => line.includes('MFA code required'))).toBe(true);
    expect(logs.some((line) => line.includes('Logged in as: Ada'))).toBe(true);
    expect(exitCode).toBeUndefined();
  });

  it('asks for the email in plain text and the password with hidden input', async () => {
    const questions: string[] = [];
    const secretQuestions: string[] = [];

    await runSetup({
      env: {},
      ask: async (question) => {
        questions.push(question);
        return question.startsWith('Garmin email') ? 'runner@example.com' : '';
      },
      askSecret: async (question) => {
        secretQuestions.push(question);
        return 'secret';
      },
      close: () => {},
      log: () => {},
      exit: () => {},
      authenticate: async (email, password) => {
        expect(email).toBe('runner@example.com');
        expect(password).toBe('secret');
        return 'Ada';
      },
    });

    expect(questions).toEqual(['Garmin email: ']);
    expect(secretQuestions).toEqual(['Garmin password: ']);
  });

  it('exits when email or password is missing', async () => {
    let exitCode: number | undefined;

    await runSetup({
      env: {},
      ask: async () => '',
      askSecret: async () => '',
      close: () => {},
      log: () => {},
      exit: (code) => {
        exitCode = code;
      },
      authenticate: async () => 'unused',
    });

    expect(exitCode).toBe(1);
  });

  it('hides typed characters while muted and shows them otherwise', async () => {
    const written: string[] = [];
    const target = { write: (chunk: string) => written.push(chunk) };
    const output = createMutableOutput(target);

    output.stream.write('Garmin password: ');
    output.setMuted(true);
    output.stream.write('hunter2');
    output.setMuted(false);
    output.stream.write('\n');

    expect(written.join('')).toBe('Garmin password: \n');
  });
});
