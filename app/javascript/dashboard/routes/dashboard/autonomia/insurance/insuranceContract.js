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
  // Diagnóstico estruturado. `null` de propósito: uma conexão nunca verificada não tem camadas nem
  // evidência, e a tela precisa distinguir isso de "verificado e deu ruim".
  failure: null,
  evidence: null,
  layers: null,
  insurers_pending_auth: null,
  // (Havia aqui um `account_already_active`, do critério 1.5. Removido em 11/09/2026: o portal manda
  // "já existe uma sessão ativa" em TODO login — 6 de 6 nos logins simultâneos medidos — e nada no
  // payload diz quem abriu a sessão. O aviso afirmava ao corretor uma coisa que o dado não sustenta.)
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

// CAUSAS DE FALHA (critério 1.1). O `status` diz o quanto a conexão está ruim; a causa diz de QUEM
// é a ação. São coisas diferentes e a tela precisa das duas.
//
// O defeito que isto corrige: `auth_required` era o destino de qualquer 403, e a tela traduzia
// `auth_required` em "Confira o usuário e a senha da corretora". Em 05/09/2026 uma sessão derrubada
// por login no navegador pediu duas trocas de senha que estavam certas.
export const FAILURE_CAUSES = Object.freeze({
  CREDENTIAL_REJECTED: 'credential_rejected',
  SESSION_LOST: 'session_lost',
  PORTAL_UNAVAILABLE: 'portal_unavailable',
  PORTAL_TIMEOUT: 'portal_timeout',
  INTEGRATION_OUTDATED: 'integration_outdated',
  REQUEST_INVALID: 'request_invalid',
  NOT_SUPPORTED: 'not_supported',
  MISCONFIGURED: 'misconfigured',
});

// A ÚNICA porta para pedir ação ao corretor. Vale pelo `actor` que o adapter classificou, e não por
// uma lista de causas repetida aqui: causa nova que ninguém lembrou de cadastrar cai em `false`,
// que é o lado seguro — não pedir nada é sempre melhor do que pedir a senha errada.
export const asksBrokerAction = failure => failure?.actor === 'broker';

// Chave de mensagem por causa. Cada causa tem texto próprio; sem causa, texto genérico.
//
// CAUSA DESCONHECIDA CAI NO GENÉRICO, e não vira chave crua na tela. O Rails grava `failure` cru
// (`connections/sync.rb`), então uma causa nova do adapter chegava aqui e a tela escrevia
// `INSURANCE.CONNECTION.FAILURES.QUOTA_EXCEEDED` no lugar da frase.
//
// A allowlist é `FAILURE_CAUSES`, que já existia e é a mesma lista que o resto do módulo usa —
// não uma segunda cópia mantida à mão. Vale para as três entradas que passam pelo mesmo
// `sanitize_deep` do Rails: esta, `evidence.check` (guardada com `te()` no componente) e
// `layers.*` (guardada por `LAYER_STATES` acima).
const CAUSAS_CONHECIDAS = new Set(Object.values(FAILURE_CAUSES));

export const failureMessageKey = failure => {
  const cause = failure?.cause;
  if (!cause || !CAUSAS_CONHECIDAS.has(String(cause))) {
    return 'INSURANCE.CONNECTION.FAILURES.UNKNOWN';
  }
  return `INSURANCE.CONNECTION.FAILURES.${String(cause).toUpperCase()}`;
};

// CAMADAS (critério 1.2). `unknown` não é "meio ok": é ninguém olhou.
export const LAYER_ORDER = Object.freeze([
  'runtime',
  'platform_auth',
  'insurer_auth',
  'product_support',
  'risk',
]);

// Estados que a tela sabe desenhar. Um valor fora desta lista chega do adapter (o Rails grava
// `layers` cru em `connections/sync.rb`) e, sem esta guarda, virava
// `INSURANCE.CONNECTION.LAYERS.STATE.SEJA_LA_O_QUE_FOR` na tela, com o marcador de cor sem classe
// nenhuma. Desconhecido é `unknown`: "não sei" é a resposta honesta para estado que não sabemos ler.
export const LAYER_STATES = ['ok', 'failed', 'pending', 'unknown'];

export const layerRows = layers =>
  LAYER_ORDER.map(key => {
    const state = layers?.[key] ?? 'unknown';
    return { key, state: LAYER_STATES.includes(state) ? state : 'unknown' };
  });

// EVIDÊNCIA (critério 1.6). Instante ABSOLUTO e o que foi feito — "às 14h02, consultando o cadastro
// da corretora". "Há 3 minutos" não é conferível contra o que o corretor viu no portal, e envelhece
// sozinho na tela sem nada ter sido reverificado.
export const formatVerifiedAt = iso => {
  if (!iso) return '';
  const data = new Date(iso);
  if (Number.isNaN(data.getTime())) return '';
  return data.toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
};
