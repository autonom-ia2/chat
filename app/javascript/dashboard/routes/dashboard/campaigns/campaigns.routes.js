import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { CAMPAIGN_PERMISSIONS } from 'dashboard/constants/permissions.js';
import { campaignJourneyRoutes } from './journey/campaignJourney.routes';

const CampaignsPageRouteView = () =>
  import('./pages/CampaignsPageRouteView.vue');
const LiveChatCampaignsPage = () => import('./pages/LiveChatCampaignsPage.vue');
const SMSCampaignsPage = () => import('./pages/SMSCampaignsPage.vue');
const WhatsAppCampaignsPage = () => import('./pages/WhatsAppCampaignsPage.vue');
const WhatsAppCampaignAnalyticsPage = () =>
  import('./pages/WhatsAppCampaignAnalyticsPage.vue');
const WhatsAppApiCampaignsPage = () =>
  import('./pages/WhatsAppApiCampaignsPage.vue');
const EmailSenderPage = () => import('./pages/EmailSenderPage.vue');
const EmailCampaignsPage = () => import('./pages/EmailCampaignsPage.vue');
const SettingsWrapper = () => import('../settings/SettingsWrapper.vue');
const WhatsAppTemplatesPage = () => import('../settings/templates/Index.vue');

const meta = {
  featureFlag: FEATURE_FLAGS.CAMPAIGNS,
  permissions: ['administrator', ...CAMPAIGN_PERMISSIONS],
};

const requireEmailCampaigns = (to, _from, next) => {
  if (
    window.globalConfig?.EMAIL_CAMPAIGN_ENABLED === 'true' &&
    window.globalConfig?.CRM_KANBAN_ENABLED === 'true'
  ) {
    next();
    return;
  }
  next({ name: 'campaigns_sms_index', params: to.params });
};

const campaignsRoutes = {
  routes: [
    // Modelos WhatsApp dentro de Campanhas (#725): a mesma tela de Configurações → Modelos,
    // com endereço próprio para só o grupo Campanhas do menu ficar aceso. Por ora só
    // administrador, como em Configurações; funções personalizadas ficam para o #726.
    {
      path: frontendURL('accounts/:accountId/campaigns/templates'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'campaigns_templates_index',
          meta: {
            featureFlag: FEATURE_FLAGS.CAMPAIGNS,
            permissions: ['administrator'],
          },
          component: WhatsAppTemplatesPage,
        },
      ],
    },
    {
      path: frontendURL('accounts/:accountId/campaigns'),
      component: CampaignsPageRouteView,
      children: [
        {
          path: '',
          redirect: to => {
            return { name: 'campaigns_ongoing_index', params: to.params };
          },
        },
        {
          path: 'ongoing',
          name: 'campaigns_ongoing_index',
          meta,
          redirect: to => {
            return { name: 'campaigns_livechat_index', params: to.params };
          },
        },
        {
          path: 'one_off',
          name: 'campaigns_one_off_index',
          meta,
          redirect: to => {
            return { name: 'campaigns_sms_index', params: to.params };
          },
        },
        {
          path: 'live_chat',
          name: 'campaigns_livechat_index',
          meta,
          component: LiveChatCampaignsPage,
        },
        {
          path: 'sms',
          name: 'campaigns_sms_index',
          meta,
          component: SMSCampaignsPage,
        },
        {
          path: 'whatsapp',
          name: 'campaigns_whatsapp_index',
          meta: {
            ...meta,
            featureFlag: FEATURE_FLAGS.WHATSAPP_CAMPAIGNS,
          },
          component: WhatsAppCampaignsPage,
        },
        {
          path: 'whatsapp/:campaignId/analytics',
          name: 'campaigns_whatsapp_analytics',
          meta: {
            ...meta,
            featureFlag: FEATURE_FLAGS.WHATSAPP_CAMPAIGNS,
          },
          component: WhatsAppCampaignAnalyticsPage,
        },
        {
          path: 'whatsapp_api',
          name: 'campaigns_whatsapp_api_index',
          meta,
          beforeEnter: (to, _from, next) => {
            if (
              window.globalConfig?.WHATSAPP_API_CAMPAIGNS_ENABLED === 'true'
            ) {
              next();
              return;
            }
            next({ name: 'campaigns_whatsapp_index', params: to.params });
          },
          component: WhatsAppApiCampaignsPage,
        },
        {
          path: 'email_sender',
          name: 'campaigns_email_sender_index',
          meta,
          beforeEnter: requireEmailCampaigns,
          component: EmailSenderPage,
        },
        {
          path: 'email_campaigns',
          name: 'campaigns_email_index',
          meta,
          beforeEnter: requireEmailCampaigns,
          component: EmailCampaignsPage,
        },
        {
          path: 'email_campaigns/:campaignId/builder',
          name: 'campaigns_email_builder',
          meta,
          beforeEnter: requireEmailCampaigns,
          component: () => import('./pages/EmailBuilderPage.vue'),
        },
        {
          path: 'email_campaigns/:campaignId?/templates',
          name: 'campaigns_email_templates',
          meta,
          beforeEnter: requireEmailCampaigns,
          component: () => import('./pages/EmailTemplatesPage.vue'),
        },
        {
          // "Trazer meu modelo" (#1099): só com a flag da conta e quem gerencia campanhas.
          path: 'email_campaigns/templates/import/:importId?',
          name: 'campaigns_email_template_import',
          meta: {
            featureFlag: FEATURE_FLAGS.EMAIL_TEMPLATE_IMPORT,
            permissions: ['administrator', 'campaign_manage'],
          },
          beforeEnter: requireEmailCampaigns,
          component: () => import('./pages/EmailTemplateImportPage.vue'),
        },
        ...campaignJourneyRoutes,
      ],
    },
  ],
};

export default campaignsRoutes;
