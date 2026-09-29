import { defineConfig } from '@playwright/test';
import path from 'path';

const baseURL = process.env.RELATIONSHIPS_TEST_URL;
if (
  !baseURL ||
  !['127.0.0.1', 'localhost', '[::1]'].includes(new URL(baseURL).hostname)
) {
  throw new Error(
    'RELATIONSHIPS_TEST_URL must point to an isolated loopback server'
  );
}

export default defineConfig({
  testDir: './tests/relationships',
  outputDir: path.resolve(__dirname, '../../.codex/relationships/playwright'),
  reporter: 'list',
  workers: 1,
  retries: 0,
  use: {
    baseURL,
    headless: true,
    locale: 'pt-BR',
    timezoneId: 'America/Sao_Paulo',
    colorScheme: 'light',
    viewport: { width: 1630, height: 930 },
    screenshot: 'only-on-failure',
    trace: 'off',
  },
});
