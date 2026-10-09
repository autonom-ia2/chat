import { readFileSync } from 'node:fs';
import fs from 'node:fs/promises';
import path from 'node:path';
import type {
  APIRequestContext,
  APIResponse,
  Page,
  Request,
} from '@playwright/test';

export type PreviewRole = 'admin' | 'editor' | 'viewer';

export type PreviewCredentials = {
  email: string;
  password: string;
};

export type PreviewAgent = {
  id: string | number;
  name?: string;
  state?: string;
};

export type PreviewConversation = {
  displayId: number;
  agentId: string | number;
  agentBotId: number;
  status: 'pending' | 'open';
};

export type PreviewAccount = {
  id: number;
  credentials: Record<PreviewRole, PreviewCredentials>;
  agents: Record<string, PreviewAgent>;
  roleIds?: Record<PreviewRole, number>;
  pauseConversation?: PreviewConversation;
};

export type AgentsPreviewManifest = {
  version: 1;
  seed: string;
  accounts: {
    a: PreviewAccount;
    empty: PreviewAccount;
    b?: PreviewAccount;
  };
};

export type PanelPreviewRole =
  | 'admin'
  | 'editor'
  | 'viewer'
  | 'participant'
  | 'participant_no_perm'
  | 'super_admin';

export type PanelPreviewCredentials = {
  email: string;
  password: string;
};

export type PanelPreviewAgent = {
  id: number;
  name: string;
  status: string;
  actuation: 'external' | 'internal' | 'both';
  agent_type: string;
};

export type PanelPreviewInbox = {
  id: number;
  name: string;
};

export type PanelPreviewConversation = {
  id: number;
  display_id: number;
  inbox_id: number;
};

export type PanelPreviewAccount = {
  id: number;
  credentials: Record<PanelPreviewRole, PanelPreviewCredentials>;
  agents: Record<string, PanelPreviewAgent>;
  inboxes: Record<string, PanelPreviewInbox>;
  conversations: Record<string, PanelPreviewConversation>;
};

export type PanelPreviewManifest = {
  version: 1;
  seed: 'f4-panel-v1';
  database: 'chat2you_agentes_ia_f4';
  accounts: {
    a: PanelPreviewAccount;
    b: PanelPreviewAccount;
  };
};

// The GESTAO runtime deliberately uses the same account/role projection as F4,
// but its seed and database are different. Keep the names separate so a test
// cannot accidentally boot the F4 snapshot with a GESTAO manifest.
export type GestaoPreviewRole = PanelPreviewRole;
export type GestaoPreviewCredentials = PanelPreviewCredentials;
export type GestaoPreviewAgent = PanelPreviewAgent;
export type GestaoPreviewInbox = PanelPreviewInbox;
export type GestaoPreviewConversation = PanelPreviewConversation;
export type GestaoPreviewAccount = PanelPreviewAccount;

export type GestaoPreviewManifest = {
  version: 1;
  seed: 'gestao-v1';
  database: 'chat2you_agentes_ia_gestao';
  accounts: {
    a: GestaoPreviewAccount;
    b: GestaoPreviewAccount;
  };
};

export type PreviewApi = {
  get: (url: string) => Promise<APIResponse>;
  patch: (url: string, data: unknown) => Promise<APIResponse>;
  delete: (url: string) => Promise<APIResponse>;
};

export type TransportScenario =
  | { kind: 'normal' }
  | {
      kind: 'transport_delay';
      until: Promise<void>;
      matches: (request: Request) => boolean;
    }
  | {
      kind: 'provider_error';
      matches: (request: Request) => boolean;
    };

const REPO_ROOT = path.resolve(__dirname, '../../..');
const PREVIEW_ROOT = path.join(REPO_ROOT, '.codex', 'preview');
const ARTIFACT_ROOT = path.join(PREVIEW_ROOT, 'agents', 'screenshots');
const SHARED_WORKSPACE_ROOT = '/Users/Shared/maccluster-workspaces/chat2you';
const SNAPSHOT_BRANCH = 'docs/agentes-ia-prd';
const SHARED_RUNTIME_OUTPUT =
  /^\/Users\/Shared\/maccluster-workspaces\/chat2you\/[^/]+\/\.codex\/runtime-m2-[^/]+\/(screenshots|playwright)$/;
const LOOPBACK_HOSTS = new Set(['localhost', '127.0.0.1', '::1', '[::1]']);
const SYNTHETIC_EMAIL_SUFFIX = '@example.invalid';

const isOfficialSnapshot = (snapshotRoot: string) => {
  if (path.dirname(snapshotRoot) !== SHARED_WORKSPACE_ROOT) return false;

  try {
    const marker = JSON.parse(
      readFileSync(
        path.join(snapshotRoot, '.maccluster-workspace.json'),
        'utf8'
      )
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

const isOfficialRuntimeOutput = (value: string) => {
  if (!SHARED_RUNTIME_OUTPUT.test(value)) return false;
  const snapshotRoot = value.split('/.codex/')[0];
  return isOfficialSnapshot(snapshotRoot);
};

const isRecord = (value: unknown): value is Record<string, unknown> =>
  Boolean(value) && typeof value === 'object' && !Array.isArray(value);

const isSyntheticCredentials = (value: unknown): value is PreviewCredentials =>
  isRecord(value) &&
  typeof value.email === 'string' &&
  value.email.endsWith(SYNTHETIC_EMAIL_SUFFIX) &&
  typeof value.password === 'string' &&
  value.password.length > 0;

const isPreviewAccount = (value: unknown): value is PreviewAccount => {
  if (!isRecord(value) || typeof value.id !== 'number') return false;
  if (!isRecord(value.credentials) || !isRecord(value.agents)) return false;

  const roles: PreviewRole[] = ['admin', 'editor', 'viewer'];
  const roleIdsValid =
    value.roleIds === undefined ||
    (isRecord(value.roleIds) &&
      roles.every(role => typeof value.roleIds?.[role] === 'number'));
  const conversation = value.pauseConversation;
  const conversationValid =
    conversation === undefined ||
    (isRecord(conversation) &&
      typeof conversation.displayId === 'number' &&
      (typeof conversation.agentId === 'number' ||
        typeof conversation.agentId === 'string') &&
      typeof conversation.agentBotId === 'number' &&
      (conversation.status === 'pending' || conversation.status === 'open'));

  return (
    roles.every(role => isSyntheticCredentials(value.credentials[role])) &&
    Object.values(value.agents).every(
      agent =>
        isRecord(agent) &&
        (typeof agent.id === 'number' || typeof agent.id === 'string')
    ) &&
    roleIdsValid &&
    conversationValid
  );
};

const isPanelRoleCredentials = (
  value: unknown
): value is Record<PanelPreviewRole, PanelPreviewCredentials> => {
  if (!isRecord(value)) return false;
  const roles: PanelPreviewRole[] = [
    'admin',
    'editor',
    'viewer',
    'participant',
    'participant_no_perm',
    'super_admin',
  ];
  return roles.every(role => isSyntheticCredentials(value[role]));
};

const isPanelAgent = (value: unknown): value is PanelPreviewAgent =>
  isRecord(value) &&
  typeof value.id === 'number' &&
  typeof value.name === 'string' &&
  typeof value.status === 'string' &&
  ['external', 'internal', 'both'].includes(String(value.actuation)) &&
  typeof value.agent_type === 'string';

const isPanelAccount = (value: unknown): value is PanelPreviewAccount => {
  if (!isRecord(value) || typeof value.id !== 'number') return false;
  if (!isPanelRoleCredentials(value.credentials)) return false;
  if (!isRecord(value.agents) || !isRecord(value.inboxes)) return false;
  if (!isRecord(value.conversations)) return false;

  const agentsValid = Object.values(value.agents).every(isPanelAgent);
  const inboxesValid = Object.values(value.inboxes).every(
    inbox =>
      isRecord(inbox) &&
      typeof inbox.id === 'number' &&
      typeof inbox.name === 'string'
  );
  const conversationsValid = Object.values(value.conversations).every(
    conversation =>
      isRecord(conversation) &&
      typeof conversation.id === 'number' &&
      typeof conversation.display_id === 'number' &&
      typeof conversation.inbox_id === 'number'
  );
  return agentsValid && inboxesValid && conversationsValid;
};

const resolveManifestPath = () => {
  const configuredPath = process.env.AGENTS_PREVIEW_MANIFEST;
  if (!configuredPath) {
    throw new Error(
      'AGENTS_PREVIEW_MANIFEST is required and must live under .codex/preview'
    );
  }

  const resolvedPath = path.isAbsolute(configuredPath)
    ? path.resolve(configuredPath)
    : path.resolve(REPO_ROOT, configuredPath);
  const relativePath = path.relative(PREVIEW_ROOT, resolvedPath);
  if (relativePath.startsWith('..') || path.isAbsolute(relativePath)) {
    throw new Error('AGENTS_PREVIEW_MANIFEST must live under .codex/preview');
  }
  return resolvedPath;
};

const resolvePanelManifestPath = () => {
  const configuredPath = process.env.AGENTS_PREVIEW_MANIFEST;
  if (!configuredPath) {
    throw new Error(
      'AGENTS_PREVIEW_MANIFEST is required for the F4 panel fixture'
    );
  }

  const resolvedPath = path.isAbsolute(configuredPath)
    ? path.resolve(configuredPath)
    : path.resolve(REPO_ROOT, configuredPath);
  const codexRoot = path.join(REPO_ROOT, '.codex');
  const relativePath = path.relative(codexRoot, resolvedPath);
  if (!relativePath.startsWith('..') && !path.isAbsolute(relativePath)) {
    return resolvedPath;
  }

  const snapshotRoot = path.dirname(REPO_ROOT);
  const externalManifest = path.join(
    snapshotRoot,
    '.codex',
    'runtime-m2-panel-f4',
    'fixtures-panel.json'
  );
  if (resolvedPath === externalManifest && isOfficialSnapshot(snapshotRoot)) {
    return resolvedPath;
  }

  throw new Error(
    'AGENTS_PREVIEW_MANIFEST deve estar no .codex interno ou no runtime-m2-panel-f4 de um snapshot oficial'
  );
};

const resolveGestaoManifestPath = () => {
  const configuredPath = process.env.AGENTS_PREVIEW_MANIFEST;
  if (!configuredPath) {
    throw new Error(
      'AGENTS_PREVIEW_MANIFEST is required for the GESTAO panel fixture'
    );
  }

  const resolvedPath = path.isAbsolute(configuredPath)
    ? path.resolve(configuredPath)
    : path.resolve(REPO_ROOT, configuredPath);
  const codexRoot = path.join(REPO_ROOT, '.codex');
  const relativePath = path.relative(codexRoot, resolvedPath);
  if (!relativePath.startsWith('..') && !path.isAbsolute(relativePath)) {
    return resolvedPath;
  }

  const snapshotRoot = path.dirname(REPO_ROOT);
  const externalManifest = path.join(
    snapshotRoot,
    '.codex',
    'runtime-m2-panel-gestao',
    'fixtures-gestao.json'
  );
  if (resolvedPath === externalManifest && isOfficialSnapshot(snapshotRoot)) {
    return resolvedPath;
  }

  throw new Error(
    'AGENTS_PREVIEW_MANIFEST deve estar no .codex interno ou no runtime-m2-panel-gestao de um snapshot oficial'
  );
};

export async function loadAgentsPreviewManifest(): Promise<AgentsPreviewManifest> {
  const content = await fs.readFile(resolveManifestPath(), 'utf8');
  let value: unknown;
  try {
    value = JSON.parse(content);
  } catch {
    throw new Error('AGENTS_PREVIEW_MANIFEST is not valid JSON');
  }

  if (
    !isRecord(value) ||
    value.version !== 1 ||
    value.seed !== 'f1-local-v1' ||
    !isRecord(value.accounts) ||
    !isPreviewAccount(value.accounts.a) ||
    !isPreviewAccount(value.accounts.empty) ||
    (value.accounts.b !== undefined && !isPreviewAccount(value.accounts.b))
  ) {
    throw new Error(
      'AGENTS_PREVIEW_MANIFEST does not match the F1 local fixture schema'
    );
  }

  return value as unknown as AgentsPreviewManifest;
}

export async function loadPanelPreviewManifest(): Promise<PanelPreviewManifest> {
  const content = await fs.readFile(resolvePanelManifestPath(), 'utf8');
  let value: unknown;
  try {
    value = JSON.parse(content);
  } catch {
    throw new Error('AGENTS_PREVIEW_MANIFEST is not valid JSON');
  }

  if (
    !isRecord(value) ||
    value.version !== 1 ||
    value.seed !== 'f4-panel-v1' ||
    value.database !== 'chat2you_agentes_ia_f4' ||
    !isRecord(value.accounts) ||
    !isPanelAccount(value.accounts.a) ||
    !isPanelAccount(value.accounts.b)
  ) {
    throw new Error(
      'AGENTS_PREVIEW_MANIFEST does not match the F4 panel fixture schema'
    );
  }

  return value as unknown as PanelPreviewManifest;
}

export async function loadGestaoPreviewManifest(): Promise<GestaoPreviewManifest> {
  const content = await fs.readFile(resolveGestaoManifestPath(), 'utf8');
  let value: unknown;
  try {
    value = JSON.parse(content);
  } catch {
    throw new Error('AGENTS_PREVIEW_MANIFEST is not valid JSON');
  }

  if (
    !isRecord(value) ||
    value.version !== 1 ||
    value.seed !== 'gestao-v1' ||
    value.database !== 'chat2you_agentes_ia_gestao' ||
    !isRecord(value.accounts) ||
    !isPanelAccount(value.accounts.a) ||
    !isPanelAccount(value.accounts.b)
  ) {
    throw new Error(
      'AGENTS_PREVIEW_MANIFEST does not match the GESTAO panel fixture schema'
    );
  }

  return value as unknown as GestaoPreviewManifest;
}

const isLocalResource = (url: URL) => {
  if (['about:', 'blob:', 'data:', 'file:'].includes(url.protocol)) return true;
  if (!['http:', 'https:', 'ws:', 'wss:'].includes(url.protocol)) return false;
  return LOOPBACK_HOSTS.has(url.hostname);
};

export type TransportLatch = {
  until: Promise<void>;
  release: () => void;
};

export const createTransportLatch = (): TransportLatch => {
  let release = () => {};
  const until = new Promise<void>(resolve => {
    release = () => resolve();
  });

  return { until, release };
};

export async function installLocalNetworkGuard(
  page: Page,
  scenario: TransportScenario = { kind: 'normal' }
) {
  await page.route('**/*', async route => {
    const request = route.request();
    const url = new URL(request.url());

    if (!isLocalResource(url)) {
      await route.abort('blockedbyclient');
      return;
    }

    if (scenario.kind === 'provider_error' && scenario.matches(request)) {
      await route.abort('failed');
      return;
    }

    if (scenario.kind === 'transport_delay' && scenario.matches(request)) {
      await scenario.until;
    }

    await route.continue();
  });
}

const authHeadersFrom = (response: APIResponse) => {
  const headers = response.headers();
  const authHeaders = Object.fromEntries(
    ['access-token', 'client', 'uid', 'expiry', 'token-type'].map(key => [
      key,
      headers[key],
    ])
  );

  if (Object.values(authHeaders).some(value => !value)) {
    throw new Error(
      'Synthetic sign-in did not return the expected auth headers'
    );
  }

  return authHeaders;
};

// Reuse a legitimate synthetic session within each worker instead of creating one
// per test and exhausting the product's device limit.
const syntheticSessions = new Map<string, Record<string, string>>();

export async function previewSession({
  page,
  request,
  account,
  role,
  baseURL,
  scenario = { kind: 'normal' },
}: {
  page: Page;
  request: APIRequestContext;
  account: PreviewAccount;
  role: PreviewRole;
  baseURL: string;
  scenario?: TransportScenario;
}) {
  await installLocalNetworkGuard(page, scenario);
  await page.addInitScript(() => {
    const observer = new MutationObserver(() => {
      const button = document.querySelector<HTMLButtonElement>(
        '[data-guia-entendi]'
      );
      if (button) button.click();
    });
    observer.observe(document, { childList: true, subtree: true });
  });
  const credentials = account.credentials[role];
  const sessionKey = `${baseURL}:${account.id}:${role}`;
  let authHeaders = syntheticSessions.get(sessionKey);
  if (!authHeaders) {
    const response = await request.post('/auth/sign_in', { data: credentials });
    if (!response.ok()) {
      throw new Error(
        `Synthetic sign-in failed with HTTP ${response.status()}`
      );
    }
    authHeaders = authHeadersFrom(response);
    syntheticSessions.set(sessionKey, authHeaders);
  }
  await page.context().addCookies([
    {
      name: 'cw_d_session_info',
      value: JSON.stringify(authHeaders),
      url: baseURL,
      sameSite: 'Lax',
    },
  ]);

  return {
    api: {
      get: (url: string) => request.get(url, { headers: authHeaders }),
      patch: (url: string, data: unknown) =>
        request.patch(url, { headers: authHeaders, data }),
      delete: (url: string) => request.delete(url, { headers: authHeaders }),
    } satisfies PreviewApi,
  };
}

export async function panelPreviewSession({
  page,
  request,
  account,
  role,
  baseURL,
  scenario = { kind: 'normal' },
}: {
  page: Page;
  request: APIRequestContext;
  account: PanelPreviewAccount;
  role: PanelPreviewRole;
  baseURL: string;
  scenario?: TransportScenario;
}) {
  await installLocalNetworkGuard(page, scenario);
  await page.addInitScript(() => {
    const observer = new MutationObserver(() => {
      const button = document.querySelector<HTMLButtonElement>(
        '[data-guia-entendi]'
      );
      if (button) button.click();
    });
    observer.observe(document, { childList: true, subtree: true });
  });
  const credentials = account.credentials[role];
  const sessionKey = `${baseURL}:f4:${account.id}:${role}`;
  let authHeaders = syntheticSessions.get(sessionKey);
  if (!authHeaders) {
    const response = await request.post('/auth/sign_in', { data: credentials });
    if (!response.ok()) {
      throw new Error(
        `Synthetic F4 sign-in failed with HTTP ${response.status()}`
      );
    }
    authHeaders = authHeadersFrom(response);
    syntheticSessions.set(sessionKey, authHeaders);
  }
  await page.context().addCookies([
    {
      name: 'cw_d_session_info',
      value: JSON.stringify(authHeaders),
      url: baseURL,
      sameSite: 'Lax',
    },
  ]);

  return {
    api: {
      get: (url: string) => request.get(url, { headers: authHeaders }),
      patch: (url: string, data: unknown) =>
        request.patch(url, { headers: authHeaders, data }),
      delete: (url: string) => request.delete(url, { headers: authHeaders }),
    } satisfies PreviewApi,
  };
}

export async function gestaoPreviewSession({
  page,
  request,
  account,
  role,
  baseURL,
  scenario = { kind: 'normal' },
}: {
  page: Page;
  request: APIRequestContext;
  account: GestaoPreviewAccount;
  role: GestaoPreviewRole;
  baseURL: string;
  scenario?: TransportScenario;
}) {
  await installLocalNetworkGuard(page, scenario);
  await page.addInitScript(() => {
    const observer = new MutationObserver(() => {
      const button = document.querySelector<HTMLButtonElement>(
        '[data-guia-entendi]'
      );
      if (button) button.click();
    });
    observer.observe(document, { childList: true, subtree: true });
  });
  const credentials = account.credentials[role];
  const sessionKey = `${baseURL}:gestao:${account.id}:${role}`;
  let authHeaders = syntheticSessions.get(sessionKey);
  if (!authHeaders) {
    const response = await request.post('/auth/sign_in', {
      data: credentials,
      headers: { 'user-agent': 'Chat2You-Gestao-QA' },
    });
    if (!response.ok()) {
      throw new Error(
        `Synthetic GESTAO sign-in failed with HTTP ${response.status()}`
      );
    }
    authHeaders = authHeadersFrom(response);
    syntheticSessions.set(sessionKey, authHeaders);
  }
  await page.context().addCookies([
    {
      name: 'cw_d_session_info',
      value: JSON.stringify(authHeaders),
      url: baseURL,
      sameSite: 'Lax',
    },
  ]);

  return {
    api: {
      get: (url: string) => request.get(url, { headers: authHeaders }),
      patch: (url: string, data: unknown) =>
        request.patch(url, { headers: authHeaders, data }),
      delete: (url: string) => request.delete(url, { headers: authHeaders }),
    } satisfies PreviewApi,
  };
}

export const agentsListPath = (accountId: number) =>
  `/api/v1/accounts/${accountId}/autonomia/agents`;

export const agentPath = (accountId: number, agentId: string | number) =>
  `${agentsListPath(accountId)}/${agentId}`;

export const panelAgentPath = (accountId: number, agentId: string | number) =>
  `${agentsListPath(accountId)}/${agentId}`;

export const panelAnalyticsPath = (
  accountId: number,
  agentId: string | number
) => `${panelAgentPath(accountId, agentId)}/analytics`;

export const panelAnalyticsConversationsPath = (
  accountId: number,
  agentId: string | number
) => `${panelAnalyticsPath(accountId, agentId)}/conversations`;

export const conversationPath = (accountId: number, displayId: number) =>
  `/api/v1/accounts/${accountId}/conversations/${displayId}`;

export const fixtureAgent = (account: PreviewAccount, key: string) => {
  const agent = account.agents[key];
  if (!agent) throw new Error(`F1 fixture agent is missing: ${key}`);
  return agent;
};

export async function gotoAgentsList(page: Page, accountId: number) {
  const responsePromise = page.waitForResponse(
    response =>
      new URL(response.url()).pathname === agentsListPath(accountId) &&
      response.request().method() === 'GET'
  );
  await page.goto(`/app/accounts/${accountId}/agents`);
  const response = await responsePromise;
  if (!response.ok()) {
    throw new Error(`Agents list failed with HTTP ${response.status()}`);
  }
  return response;
}

const screenshotOutputRoot = () => {
  const configuredRoot = process.env.AGENTS_PREVIEW_SCREENSHOTS_DIR;
  const outputRoot = configuredRoot
    ? path.resolve(configuredRoot)
    : ARTIFACT_ROOT;
  if (configuredRoot && !isOfficialRuntimeOutput(outputRoot)) {
    throw new Error(
      'AGENTS_PREVIEW_SCREENSHOTS_DIR must be the screenshots directory of an isolated M2 runtime'
    );
  }
  return outputRoot;
};

export async function screenshotPath(projectName: string, scenario: string) {
  const outputRoot = screenshotOutputRoot();
  await fs.mkdir(outputRoot, { recursive: true });
  return path.join(outputRoot, `${scenario}-${projectName}.png`);
}

export async function recordScreenshot({
  scenario,
  project,
  file,
}: {
  scenario: string;
  project: string;
  file: string;
}) {
  const outputRoot = screenshotOutputRoot();
  if (path.dirname(file) !== outputRoot) {
    throw new Error(
      'Screenshot file must be inside the isolated output directory'
    );
  }

  const manifestPath = path.join(outputRoot, 'manifest.json');
  const canonicalScenario = scenario.startsWith('panel-')
    ? scenario.slice('panel-'.length)
    : scenario;
  let entries: Array<{
    scenario: string;
    label: string;
    project: string;
    file: string;
  }> = [];
  try {
    const parsed: unknown = JSON.parse(await fs.readFile(manifestPath, 'utf8'));
    if (!Array.isArray(parsed))
      throw new Error('Screenshot manifest must be an array');
    entries = parsed as typeof entries;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
  }

  entries = entries.filter(entry => entry.file !== file);
  entries.push({
    scenario: canonicalScenario,
    label: canonicalScenario,
    project,
    file,
  });
  await fs.writeFile(manifestPath, `${JSON.stringify(entries, null, 2)}\n`, {
    mode: 0o600,
  });
}
