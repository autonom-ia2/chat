import { frontendURL } from 'dashboard/helper/URLHelper.js';
import {
  AUTONOMIA_PERMISSIONS,
  DESEMPENHO_VIEW_PERMISSION,
  PROSPECTING_PERMISSIONS,
  INSURANCE_PERMISSIONS,
} from 'dashboard/constants/permissions.js';
import { contaDaRota, ensureProspectingEnabled } from './contaDaRota';
import { painelDesempenhoLigado } from './agentes/composables/usePainelDesempenho';

// Lazy-loaded pages (owned by HUB / CONSTRUTOR / PAINEL implementers).
// Dynamic imports keep this NAV module self-contained and code-split the
// Autonomia bundle out of the main dashboard chunk.
// #1181: a lista, a criação e a página do agente passam por seletores que escolhem a
// página antiga ou a nova pela flag autonomia_agents_journey (a antiga continua no mesmo pedaço).
const AgentesListaEntrada = () =>
  import('./agentes/entrada/AgentesListaEntrada.vue');
const AgentesCriarEntrada = () =>
  import('./agentes/entrada/AgentesCriarEntrada.vue');
const AgentePaginaEntrada = () =>
  import('./agentes/entrada/AgentePaginaEntrada.vue');
// #2226 — painel de desempenho do agente (PR 1: protótipo com dados inventados).
const DesempenhoPage = () => import('./agentes/pages/DesempenhoPage.vue');
const ProspectingSearchPage = () =>
  import('./prospecting/pages/ProspectingSearchPage.vue');
const ProspectingListsPage = () =>
  import('./prospecting/pages/ProspectingListsPage.vue');
const InviteConnectionPage = () => import('./pages/InviteConnectionPage.vue');
const InsurancePage = () => import('./insurance/pages/InsurancePage.vue');

// Prospecção e Cotação (#452): Ver lê, Editar escreve; o backend aplica o mesmo corte.
const prospectingMeta = {
  permissions: ['administrator', ...PROSPECTING_PERMISSIONS],
};
const prospectingManageMeta = {
  permissions: ['administrator', 'prospecting_manage'],
};
const insuranceMeta = {
  permissions: ['administrator', ...INSURANCE_PERMISSIONS],
};

// Agentes Autonom.ia (#452): custom roles with autonomia_view see and test agents; creating
// one needs autonomia_manage. The backend enforces the same split.
const agentsMeta = {
  permissions: ['administrator', ...AUTONOMIA_PERMISSIONS],
};
const agentsManageMeta = {
  permissions: ['administrator', 'autonomia_manage'],
};
// #2251 — o painel de desempenho tem chave própria (só ver), independente de ver os agentes.
const desempenhoMeta = {
  permissions: ['administrator', DESEMPENHO_VIEW_PERMISSION],
};

// Gate POR CONTA (aditivo, ISOLADO): mantém o ENV master (kill-switch global,
// exposto como window.globalConfig.AUTONOMIA_AGENTS_ENABLED) como pré-condição E
// exige a conta marcada como habilitada pelo gate isolado, exposto no payload da
// conta via `autonomia_agents_enabled` (_account.json.jbuilder ->
// Autonomia::Agents::Config.enabled?). NÃO depende do sistema de features do
// Chatwoot. Com a conta OFF, a rota redireciona para 'home' (recurso invisível,
// igual ao 404 do backend). Sem regressão: ENV OFF segue bloqueando todas as contas.
const ensureAutonomiaEnabled = async (to, _from, next) => {
  const masterEnabled =
    window.globalConfig?.AUTONOMIA_AGENTS_ENABLED === 'true';
  const account = masterEnabled ? await contaDaRota(to) : null;
  const accountEnabled = account?.autonomia_agents_enabled === true;

  if (masterEnabled && accountEnabled) {
    next();
    return;
  }
  next({ name: 'home', params: to.params });
};

// #2226 — o painel de desempenho, além do ENV master, exige a nova jornada e a flag
// agentes_painel_desempenho na conta. Quem abre: administrador ou função com desempenho_view (#2251).
const ensureDesempenhoEnabled = async (to, _from, next) => {
  const masterEnabled =
    window.globalConfig?.AUTONOMIA_AGENTS_ENABLED === 'true';
  const account = masterEnabled ? await contaDaRota(to) : null;
  if (painelDesempenhoLigado(account)) {
    next();
    return;
  }
  next({ name: 'home', params: to.params });
};

// Módulo Cotação (Insurance): ENV master INSURANCE_QUOTING_ENABLED (kill-switch global,
// window.globalConfig) E conta marcada pelo SuperAdmin (`autonomia_insurance_enabled` no
// payload da conta -> Autonomia::Insurance::Config.enabled?). Mesmo contrato do backend.
// Link direto / F5: espera a conta (contaDaRota), como os outros guardas.
const ensureInsuranceEnabled = async (to, _from, next) => {
  const masterEnabled =
    window.globalConfig?.INSURANCE_QUOTING_ENABLED === 'true';
  const account = masterEnabled ? await contaDaRota(to) : null;
  const accountEnabled = account?.autonomia_insurance_enabled === true;

  if (masterEnabled && accountEnabled) {
    next();
    return;
  }
  next({ name: 'home', params: to.params });
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/autonomia/invite-connection'),
    name: 'autonomia_invite_connection',
    meta: {
      permissions: ['administrator', 'agent', 'custom_role'],
    },
    component: InviteConnectionPage,
  },
  {
    path: frontendURL('accounts/:accountId/agents'),
    name: 'autonomia_agents_index',
    meta: agentsMeta,
    beforeEnter: ensureAutonomiaEnabled,
    component: AgentesListaEntrada,
  },
  {
    path: frontendURL('accounts/:accountId/agents/new'),
    name: 'autonomia_agents_builder',
    meta: agentsManageMeta,
    beforeEnter: ensureAutonomiaEnabled,
    component: AgentesCriarEntrada,
  },
  {
    path: frontendURL(
      'accounts/:accountId/agents/:agentId/:tab(test|knowledge|channels|performance|tune|publish)?'
    ),
    name: 'autonomia_agent_panel',
    meta: agentsMeta,
    beforeEnter: ensureAutonomiaEnabled,
    component: AgentePaginaEntrada,
    props: route => ({
      agentId: route.params.agentId,
      tab: route.params.tab || 'test',
    }),
  },
  {
    // Agente nosso e de outro sistema (`?origem=webhook`), como a página do agente (#1648).
    path: frontendURL('accounts/:accountId/agents/:agentId/desempenho'),
    name: 'autonomia_agent_desempenho',
    meta: desempenhoMeta,
    beforeEnter: ensureDesempenhoEnabled,
    component: DesempenhoPage,
    props: route => ({ agentId: route.params.agentId }),
  },
  {
    path: frontendURL('accounts/:accountId/autonomia/prospecting/search'),
    name: 'autonomia_prospecting_search',
    meta: prospectingMeta,
    beforeEnter: ensureProspectingEnabled,
    component: ProspectingSearchPage,
  },
  {
    path: frontendURL('accounts/:accountId/autonomia/prospecting/lists'),
    name: 'autonomia_prospecting_lists',
    meta: prospectingMeta,
    beforeEnter: ensureProspectingEnabled,
    component: ProspectingListsPage,
  },
  {
    path: frontendURL('accounts/:accountId/autonomia/prospecting/settings'),
    name: 'autonomia_prospecting_settings',
    meta: prospectingManageMeta,
    beforeEnter: ensureProspectingEnabled,
    redirect: to => ({
      name: 'settings_prospecting_index',
      params: to.params,
    }),
  },
  {
    path: frontendURL('accounts/:accountId/autonomia/insurance'),
    name: 'autonomia_insurance',
    meta: insuranceMeta,
    beforeEnter: ensureInsuranceEnabled,
    redirect: to => ({
      name: 'autonomia_insurance_connections',
      params: to.params,
    }),
  },
  {
    path: frontendURL('accounts/:accountId/autonomia/insurance/connections'),
    name: 'autonomia_insurance_connections',
    meta: insuranceMeta,
    beforeEnter: ensureInsuranceEnabled,
    component: InsurancePage,
    props: { tab: 'connections' },
  },
  {
    path: frontendURL('accounts/:accountId/autonomia/insurance/agent'),
    name: 'autonomia_insurance_agent',
    meta: insuranceMeta,
    beforeEnter: ensureInsuranceEnabled,
    component: InsurancePage,
    props: { tab: 'agent' },
  },
];

export default { routes };
