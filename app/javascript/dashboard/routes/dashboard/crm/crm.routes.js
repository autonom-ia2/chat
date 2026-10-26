import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { isCrmKanbanEnabled } from 'dashboard/helper/routeHelpers';
import {
  CRM_VIEW_PERMISSION,
  CRM_VIEW_REPORTS_PERMISSION,
  CRM_ADMIN_PERMISSION,
  CAMPAIGN_PERMISSIONS,
  SLA_MANAGE_PERMISSION,
  TOKEN_MANAGE_PERMISSION,
} from 'dashboard/constants/permissions.js';
const CrmKanbanPage = () => import('./pages/CrmKanbanPage.vue');
// CRM › Números (#1897): o painel de hoje sem a flag `crm_numeros_lentes`; com ela, "Só eu · Equipe".
const CrmNumerosPage = () => import('./pages/CrmNumerosPage.vue');
const CrmNumerosOrigensPage = () => import('./pages/CrmNumerosOrigensPage.vue');
const CrmAiUsagePage = () => import('./pages/CrmAiUsagePage.vue');
const CrmSlaPage = () => import('./pages/CrmSlaPage.vue');
const CaixasPage = () => import('./caixas/pages/CaixasPage.vue');
const CaixaPage = () => import('./caixas/pages/CaixaPage.vue');
const CrmIntegrationTokensPage = () =>
  import('./pages/CrmIntegrationTokensPage.vue');
// Journey on: multichannel overview (#1007); off: the old e-mail report page, unchanged.
const CrmCampaignManagementPage = () =>
  import('../campaigns/journey/CampaignManagementSwitch.vue');

// 'agent' keeps plain (non-custom-role) agents in per the locked decision;
// custom-role seats are gated by the granular crm_view permission key.
const meta = {
  permissions: ['administrator', 'agent', CRM_VIEW_PERMISSION],
};

const reportsMeta = {
  permissions: ['administrator', 'agent', CRM_VIEW_REPORTS_PERMISSION],
};

// Números: quem vê a equipe (reportsMeta) e, com a flag, quem só trabalha no CRM (crm_view vê "Só eu"). Sem a flag,
// a página manda de volta para o Kanban quem não vê a equipe (useQuemVeNumeros).
const numerosMeta = {
  permissions: [...reportsMeta.permissions, CRM_VIEW_PERMISSION],
};

// Admin-equivalent CRM settings: only the account administrator or an explicit crm_admin seat.
const adminMeta = {
  permissions: ['administrator', CRM_ADMIN_PERMISSION],
};

// CRM › SLA is the only SLA screen (#1618): crm_admin keeps it, and sla_manage
// (the key the SLA policy API checks) opens it too.
const slaMeta = {
  permissions: ['administrator', CRM_ADMIN_PERMISSION, SLA_MANAGE_PERMISSION],
};

// Campaign reports and CTWA links are campaign data (#452): their APIs check campaign_view.
const campaignsMeta = {
  permissions: ['administrator', ...CAMPAIGN_PERMISSIONS],
};

const ensureCrmEnabled = (to, _from, next) => {
  if (isCrmKanbanEnabled()) {
    next();
    return;
  }
  next({ name: 'home', params: to.params });
};

const ensureCrmAiEnabled = (to, _from, next) => {
  if (isCrmKanbanEnabled() && window.globalConfig?.CRM_AI_ENABLED === 'true') {
    next();
    return;
  }
  next({ name: 'home', params: to.params });
};

// Caixas no CRM (#1149): mesma permissão da gaveta antiga (quem gerencia os
// funis), atrás da flag por conta crm_configurar_caixas.
const caixasMeta = {
  ...adminMeta,
  featureFlag: FEATURE_FLAGS.CRM_CONFIGURAR_CAIXAS,
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/crm/caixas'),
    name: 'crm_caixas',
    meta: caixasMeta,
    beforeEnter: ensureCrmEnabled,
    component: CaixasPage,
  },
  {
    path: frontendURL('accounts/:accountId/crm/caixas/:inboxId'),
    name: 'crm_caixa',
    meta: caixasMeta,
    beforeEnter: ensureCrmEnabled,
    component: CaixaPage,
  },
  {
    path: frontendURL('accounts/:accountId/campaigns/links'),
    name: 'campaigns_tracked_links_index',
    meta: campaignsMeta,
    beforeEnter: ensureCrmEnabled,
    component: () => import('../campaigns/pages/TrackedLinksPage.vue'),
  },
  {
    // Anúncios da Meta (#1047): conexão guiada e painel, atrás da flag por conta meta_ads_hub.
    // Ver: administrador, meta_ads_view (#1794) ou meta_ads_manage (#2070). A função guarda só a chave mais alta, e a
    // lista de chaves que chega ao painel não expande manage em view: as duas entram aqui.
    path: frontendURL('accounts/:accountId/campaigns/meta-ads'),
    name: 'campaigns_meta_ads_index',
    meta: {
      permissions: ['administrator', 'meta_ads_view', 'meta_ads_manage'],
      featureFlag: FEATURE_FLAGS.META_ADS_HUB,
    },
    beforeEnter: ensureCrmEnabled,
    component: () => import('../campaigns/metaAds/MetaAdsPage.vue'),
  },
  {
    path: frontendURL('accounts/:accountId/crm'),
    name: 'crm_kanban_index',
    meta,
    beforeEnter: ensureCrmEnabled,
    component: CrmKanbanPage,
  },
  {
    // Calendar-only sub-page: reuses CrmKanbanPage but opens straight on the
    // calendar with the kanban/list/calendar switch + "New pipeline" hidden.
    path: frontendURL('accounts/:accountId/crm/calendar'),
    name: 'crm_calendar_index',
    meta: { ...meta, calendarOnly: true },
    beforeEnter: ensureCrmEnabled,
    component: CrmKanbanPage,
  },
  {
    path: frontendURL('accounts/:accountId/crm/dashboard'),
    name: 'crm_dashboard_index',
    meta: numerosMeta,
    beforeEnter: ensureCrmEnabled,
    component: CrmNumerosPage,
  },
  {
    // Números › "De onde vieram os clientes" (#2001, F6), aberta pela visão "Equipe" de Números. A página volta para
    // Números sem a flag `crm_numeros_origens` ou sem a visão "Equipe".
    path: frontendURL('accounts/:accountId/crm/dashboard/origens'),
    name: 'crm_numeros_origens',
    meta: numerosMeta,
    beforeEnter: ensureCrmEnabled,
    component: CrmNumerosOrigensPage,
  },
  {
    path: frontendURL('accounts/:accountId/crm/ai-usage'),
    name: 'crm_ai_usage_index',
    meta: reportsMeta,
    beforeEnter: ensureCrmAiEnabled,
    component: CrmAiUsagePage,
  },
  {
    path: frontendURL('accounts/:accountId/crm/sla'),
    name: 'crm_sla_index',
    meta: slaMeta,
    beforeEnter: ensureCrmEnabled,
    component: CrmSlaPage,
  },
  // Gestão de campanhas mora em Campanhas desde o #725: o endereço é /campaigns/management
  // (fora de /crm, senão o CRM também fica aceso no menu). O nome da rota não muda, e o
  // endereço antigo leva ao novo com a mesma query (favoritos e links do Guia seguem valendo).
  {
    path: frontendURL('accounts/:accountId/campaigns/management'),
    name: 'crm_campaign_management_index',
    meta: campaignsMeta,
    beforeEnter: ensureCrmEnabled,
    component: CrmCampaignManagementPage,
  },
  {
    path: frontendURL('accounts/:accountId/crm/campaign-management'),
    redirect: to => ({
      name: 'crm_campaign_management_index',
      params: to.params,
      query: to.query,
    }),
  },
  {
    path: frontendURL('accounts/:accountId/crm/settings/integration-tokens'),
    name: 'crm_integration_tokens_index',
    // Tokens do CRM são segredos que a plataforma gera (#2027): administrador ou token_manage.
    meta: { permissions: ['administrator', TOKEN_MANAGE_PERMISSION] },
    beforeEnter: ensureCrmEnabled,
    component: CrmIntegrationTokensPage,
  },
];

export default { routes };
