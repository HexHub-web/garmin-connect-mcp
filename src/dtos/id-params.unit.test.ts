import { describe, expect, it } from 'vitest';
import { getDeviceSettingsSchema, getDeviceSolarSchema, getWorkoutSchema } from './devices.dto';
import { getScheduledWorkoutSchema, getTrainingPlanSchema } from './performance.dto';

const traversalAttempts = [
  '../../userprofile-service/socialProfile',
  '123/../../456',
  '123?includeAll=true',
  '123#fragment',
  '%2e%2e',
  '',
];

describe('string ID inputs that are interpolated into Garmin API paths', () => {
  it('accept plain Garmin identifiers', () => {
    expect(getDeviceSettingsSchema.parse({ deviceId: '3456789012' }).deviceId).toBe('3456789012');
    expect(getWorkoutSchema.parse({ workoutId: '987654321' }).workoutId).toBe('987654321');
    expect(getTrainingPlanSchema.parse({ planId: 'plan_42-a' }).planId).toBe('plan_42-a');
  });

  it.each(traversalAttempts)('reject %j as an ID', (value) => {
    expect(getDeviceSettingsSchema.safeParse({ deviceId: value }).success).toBe(false);
    expect(
      getDeviceSolarSchema.safeParse({ deviceId: value, startDate: '2024-01-01', endDate: '2024-01-02' })
        .success,
    ).toBe(false);
    expect(getWorkoutSchema.safeParse({ workoutId: value }).success).toBe(false);
    expect(getTrainingPlanSchema.safeParse({ planId: value }).success).toBe(false);
    expect(getScheduledWorkoutSchema.safeParse({ workoutId: value }).success).toBe(false);
  });
});
