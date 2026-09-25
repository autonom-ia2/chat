import { createRouter, createMemoryHistory } from 'vue-router';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

// Páginas trocadas por componentes vazios: aqui só importa o roteamento.
const vazio = { render: () => null };
vi.mock('../pages/CampaignsPageRouteView.vue', () => ({ default: vazio }));
vi.mock('../pages/LiveChatCampaignsPage.vue', () => ({ default: vazio }));
vi.mock('../pages/SMSCampaignsPage.vue', () => ({ default: vazio }));
vi.mock('../pages/WhatsAppCampaignsPage.vue', () => ({ default: vazio }));
vi.mock('../pages/WhatsAppCampaignAnalyticsPage.vue', () => ({
  default: vazio,
}));
vi.mock('../pages/WhatsAppApiCampaignsPage.vue', () => ({ default: vazio }));
vi.mock('../pages/EmailSenderPage.vue', () => ({ default: vazio }));
vi.mock('../pages/EmailCampaignsPage.vue', () => ({ default: vazio }));
vi.mock('../../settings/SettingsWrapper.vue', () => ({ default: vazio }));
vi.mock('../../settings/templates/Index.vue', () => ({ default: vazio }));
vi.mock('../../crm/pages/CrmKanbanPage.vue', () => ({ default: vazio }));
vi.mock('../../crm/pages/CrmDashboardPage.vue', () => ({ default: vazio }));
vi.mock('../../crm/pages/CrmAiUsagePage.vue', () => ({ default: vazio }));
vi.mock('../../crm/pages/CrmSlaPage.vue', () => ({ default: vazio }));
vi.mock('../../crm/pages/CrmIntegrationTokensPage.vue', () => ({
  default: vazio,
}));
vi.mock('../../crm/pages/CrmCampaignManagementPage.vue', () => ({
  default: vazio,
}));

const { default: campaignsRoutes } = await import('../campaigns.routes');
const { default: crmRoutes } = await import('../../crm/crm.routes');
const { default: templatesRoutes } = await import(
  '../../settings/templates/templates.routes'
);

const montarRoteador = () =>
  createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', name: 'home', component: vazio },
      ...campaignsRoutes.routes,
      ...crmRoutes.routes,
      ...templatesRoutes.routes,
    ],
  });

// #725 — Modelos WhatsApp e Gestão de campanhas com endereço dentro de Campanhas:
// é o endereço que decide qual grupo do menu fica aceso.
describe('rotas do menu de Campanhas', () => {
  beforeEach(() => {
    window.globalConfig = { CRM_KANBAN_ENABLED: 'true' };
  });

  it('Modelos WhatsApp tem endereço em Campanhas, só para administrador', () => {
    const rota = montarRoteador().resolve({
      name: 'campaigns_templates_index',
      params: { accountId: 1 },
    });

    expect(rota.path).toBe('/app/accounts/1/campaigns/templates');
    expect(rota.meta.permissions).toEqual(['administrator']);
    expect(rota.meta.featureFlag).toBe(FEATURE_FLAGS.CAMPAIGNS);
  });

  it('Configurações → Modelos continua existindo', () => {
    // O atalho da paleta de comandos, os favoritos e a Central apontam para ela.
    const rota = montarRoteador().resolve({
      name: 'settings_templates',
      params: { accountId: 1 },
    });

    expect(rota.path).toBe('/app/accounts/1/settings/templates');
  });

  it('Gestão de campanhas mora em Campanhas, fora de /crm', () => {
    const rota = montarRoteador().resolve({
      name: 'crm_campaign_management_index',
      params: { accountId: 1 },
    });

    expect(rota.path).toBe('/app/accounts/1/campaigns/management');
    expect(rota.path.includes('/crm/')).toBe(false);
  });

  it('o endereço antigo leva ao novo, com a mesma query', async () => {
    const router = montarRoteador();

    await router.push(
      '/app/accounts/1/crm/campaign-management?campaign=12&period=30d'
    );

    expect(router.currentRoute.value.name).toBe(
      'crm_campaign_management_index'
    );
    expect(router.currentRoute.value.path).toBe(
      '/app/accounts/1/campaigns/management'
    );
    expect(router.currentRoute.value.query).toEqual({
      campaign: '12',
      period: '30d',
    });
  });
});
