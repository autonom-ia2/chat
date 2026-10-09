import { readFileSync } from 'node:fs';
import path from 'node:path';
import { defineConfig, devices } from '@playwright/test';

const LOOPBACK_HOSTS = new Set(['localhost', '127.0.0.1', '::1', '[::1]']);
const SHARED_WORKSPACE_ROOT = '/Users/Shared/maccluster-workspaces/chat2you';
const SNAPSHOT_BRANCH = 'docs/agentes-ia-prd';
const SHARED_RUNTIME_OUTPUT =
  /^\/Users\/Shared\/maccluster-workspaces\/chat2you\/([^/]+)\/\.codex\/runtime-m2-[^/]+\/(screenshots|playwright)$/;

const isOfficialRuntimeOutput = (value: string) => {
  const match = value.match(SHARED_RUNTIME_OUTPUT);
  if (!match) return false;

  const snapshotRoot = `${SHARED_WORKSPACE_ROOT}/${match[1]}`;
  try {
    const marker = JSON.parse(
      readFileSync(path.join(snapshotRoot, '.maccluster-workspace.json'), 'utf8')
    ) as Record<string, unknown>;
    return (
      marker.source_branch === SNAPSHOT_BRANCH &&
      typeof marker.source_head === 'string' &&
      typeof marker.content_sha256 === 'string'
    );
  } catch {
    return false;
  }
};

const rawBaseURL = process.env.AGENTS_PREVIEW_URL;

if (!rawBaseURL) {
  throw new Error(
    'AGENTS_PREVIEW_URL is required and must point to the local preview server'
  );
}

const parsedBaseURL = new URL(rawBaseURL);
if (
  parsedBaseURL.protocol !== 'http:' ||
  !LOOPBACK_HOSTS.has(parsedBaseURL.hostname) ||
  parsedBaseURL.username ||
  parsedBaseURL.password
) {
  throw new Error(
    'AGENTS_PREVIEW_URL must be an unauthenticated HTTP loopback URL'
  );
}

const configuredOutputDir = process.env.AGENTS_PLAYWRIGHT_OUTPUT_DIR;
const outputDir = configuredOutputDir
  ? path.resolve(configuredOutputDir)
  : path.resolve(__dirname, '../../.codex/preview/agents/playwright');
if (
  configuredOutputDir && !isOfficialRuntimeOutput(outputDir)
) {
  throw new Error(
    'AGENTS_PLAYWRIGHT_OUTPUT_DIR must be the playwright directory of an isolated M2 runtime'
  );
}
const headless = process.env.AGENTS_HEADLESS !== 'false';

export default defineConfig({
  testDir: './tests/agents',
  outputDir,
  timeout: 60 * 1000,
  expect: { timeout: 15 * 1000 },
  fullyParallel: false,
  workers: 1,
  retries: 0,
  forbidOnly: true,
  reporter: 'list',
  use: {
    baseURL: parsedBaseURL.toString(),
    headless,
    locale: 'pt-BR',
    timezoneId: 'America/Sao_Paulo',
    serviceWorkers: 'block',
    trace: 'off',
    video: 'off',
    screenshot: 'only-on-failure',
    actionTimeout: 15 * 1000,
    navigationTimeout: 30 * 1000,
  },
  projects: [
    {
      name: 'chromium-1440-light',
      use: {
        ...devices['Desktop Chrome'],
        baseURL: parsedBaseURL.toString(),
        viewport: { width: 1440, height: 1080 },
        colorScheme: 'light',
      },
    },
    {
      name: 'chromium-400-light',
      use: {
        ...devices['Desktop Chrome'],
        baseURL: parsedBaseURL.toString(),
        viewport: { width: 400, height: 844 },
        colorScheme: 'light',
      },
    },
    {
      name: 'chromium-1440-dark',
      use: {
        ...devices['Desktop Chrome'],
        baseURL: parsedBaseURL.toString(),
        viewport: { width: 1440, height: 1080 },
        colorScheme: 'dark',
      },
    },
    {
      name: 'chromium-400-dark',
      use: {
        ...devices['Desktop Chrome'],
        baseURL: parsedBaseURL.toString(),
        viewport: { width: 400, height: 844 },
        colorScheme: 'dark',
      },
    },
  ],
});
