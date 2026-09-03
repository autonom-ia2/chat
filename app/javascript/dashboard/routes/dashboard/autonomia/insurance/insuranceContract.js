// Contrato FE do módulo Cotação (Insurance) — contract-first (PRD §9.2, §15).
// A conexão real com o connector chega na Onda 3; até lá a página Conexões renderiza
// estes estados a partir de um mock local, sem chamar API. Nenhum segredo passa por aqui.

export const CONNECTION_STATES = Object.freeze({
  NOT_CONFIGURED: 'not_configured',
  PROVISIONING: 'provisioning',
  AUTHENTICATING: 'authenticating',
  DISCOVERING: 'discovering',
  READY: 'ready',
  DEGRADED: 'degraded',
  // O portal recusou a credencial da corretora (senha trocada, acesso revogado).
  AUTH_REQUIRED: 'auth_required',
  HUMAN_REQUIRED: 'human_required',
  OFFLINE: 'offline',
});

// Tom visual por estado (classes do design system `n-*`). Estados transitórios são "info".
export const STATE_TONE = Object.freeze({
  [CONNECTION_STATES.NOT_CONFIGURED]: 'neutral',
  [CONNECTION_STATES.PROVISIONING]: 'info',
  [CONNECTION_STATES.AUTHENTICATING]: 'info',
  [CONNECTION_STATES.DISCOVERING]: 'info',
  [CONNECTION_STATES.READY]: 'success',
  [CONNECTION_STATES.DEGRADED]: 'warning',
  [CONNECTION_STATES.AUTH_REQUIRED]: 'warning',
  [CONNECTION_STATES.HUMAN_REQUIRED]: 'warning',
  [CONNECTION_STATES.OFFLINE]: 'danger',
});

export const TRANSIENT_STATES = Object.freeze([
  CONNECTION_STATES.PROVISIONING,
  CONNECTION_STATES.AUTHENTICATING,
  CONNECTION_STATES.DISCOVERING,
]);

export const isTransientState = state => TRANSIENT_STATES.includes(state);
export const isConnectedState = state =>
  [CONNECTION_STATES.READY, CONNECTION_STATES.DEGRADED].includes(state);

// Mascara o login da corretora como o backend fará (`username_hint`): 2 primeiros
// caracteres + domínio. Nunca exibir o login completo nem a senha.
export const maskUsername = username => {
  if (!username) return '';
  const [local, domain] = String(username).split('@');
  const head = local.slice(0, 2);
  const masked = `${head}${'*'.repeat(Math.max(local.length - 2, 2))}`;
  return domain ? `${masked}@${domain}` : masked;
};

export const buildConnection = (overrides = {}) => ({
  provider: 'agger',
  status: CONNECTION_STATES.NOT_CONFIGURED,
  username_hint: '',
  last_authenticated_at: null,
  last_healthcheck_at: null,
  last_capability_scan_at: null,
  capabilities: [],
  ...overrides,
});

// Capability map de exemplo (PRD §15.1) — formato que o connector devolverá por conta.
export const MOCK_CAPABILITIES = Object.freeze([
  {
    product: 'auto',
    enabled: true,
    insurers: ['porto', 'tokio', 'hdi', 'allianz'],
  },
  { product: 'residencial', enabled: true, insurers: ['porto', 'tokio'] },
  {
    product: 'rc_profissional',
    enabled: true,
    insurers: ['tokio', 'hdi', 'chubb'],
  },
  { product: 'vida', enabled: false, insurers: [] },
]);
