import { frontendURL } from 'dashboard/helper/URLHelper.js';

import CampaignsPageRouteView from './pages/CampaignsPageRouteView.vue';
import LiveChatCampaignsPage from './pages/LiveChatCampaignsPage.vue';
import SMSCampaignsPage from './pages/SMSCampaignsPage.vue';
import WhatsAppCampaignsPage from './pages/WhatsAppCampaignsPage.vue';
import WhatsAppCampaignAnalyticsPage from './pages/WhatsAppCampaignAnalyticsPage.vue';
import WhatsAppApiCampaignsPage from './pages/WhatsAppApiCampaignsPage.vue';
import EmailSenderPage from './pages/EmailSenderPage.vue';
import EmailCampaignsPage from './pages/EmailCampaignsPage.vue';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const meta = {
  featureFlag: FEATURE_FLAGS.CAMPAIGNS,
  permissions: ['administrator'],
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
          path: 'email_campaigns/:campaignId/templates',
          name: 'campaigns_email_templates',
          meta,
          beforeEnter: requireEmailCampaigns,
          component: () => import('./pages/EmailTemplatesPage.vue'),
        },
      ],
    },
  ],
};

export default campaignsRoutes;
