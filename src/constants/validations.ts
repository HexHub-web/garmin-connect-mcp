import { z } from 'zod';

export const dateString = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Must be YYYY-MM-DD format');

export const garminId = z
  .string()
  .regex(/^[A-Za-z0-9_-]+$/, 'Must contain only letters, digits, "-" or "_"');
