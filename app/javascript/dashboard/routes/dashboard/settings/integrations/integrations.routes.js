import { FEATURE_FLAGS } from '../../../../featureFlags';
import { frontendURL } from '../../../../helper/URLHelper';
import { INTEGRATION_MANAGE_PERMISSION } from 'dashboard/constants/permissions';
import store from 'dashboard/store';

const SettingsWrapper = () => import('../SettingsWrapper.vue');
const IntegrationHooks = () => import('./IntegrationHooks.vue');
const Index = () => import('./Index.vue');
const Webhook = () => import('./Webhooks/Index.vue');
const DashboardApps = () => import('./DashboardApps/Index.vue');
const Slack = () => import('./Slack.vue');
const Linear = () => import('./Linear.vue');
const Stripe = () => import('./Stripe.vue');
const Notion = () => import('./Notion.vue');
const Shopify = () => import('./Shopify.vue');
const CrmN8n = () => import('./CrmN8n.vue');

export const redirectShopifyIfUnavailable = async (to, _from, next) => {
  const accountId = Number(to.params.accountId);
  const account = store.getters['accounts/getAccount'](accountId);
  if (!account.id) {
    await store.dispatch('accounts/get', { accountId, silent: true });
  }

  const isShopifyEnabled = [
    FEATURE_FLAGS.SHOPIFY,
    FEATURE_FLAGS.SHOPIFY_CUSTOM_APPS,
  ].some(feature =>
    store.getters['accounts/isFeatureEnabledonAccount'](accountId, feature)
  );

  next(
    isShopifyEnabled
      ? undefined
      : {
          name: 'settings_applications',
          params: { accountId: to.params.accountId },
        }
  );
};

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/integrations'),
      component: SettingsWrapper,
      props: {},
      children: [
        {
          path: '',
          name: 'settings_applications',
          component: Index,
          meta: {
            featureFlag: FEATURE_FLAGS.INTEGRATIONS,
            permissions: ['administrator', INTEGRATION_MANAGE_PERMISSION],
          },
        },
        {
          path: 'dashboard_apps',
          component: DashboardApps,
          name: 'settings_integrations_dashboard_apps',
          meta: {
            featureFlag: FEATURE_FLAGS.INTEGRATIONS,
            permissions: ['administrator', INTEGRATION_MANAGE_PERMISSION],
          },
        },
        {
          path: 'webhook',
          component: Webhook,
          name: 'settings_integrations_webhook',
          meta: {
            featureFlag: FEATURE_FLAGS.INTEGRATIONS,
            permissions: ['administrator', INTEGRATION_MANAGE_PERMISSION],
          },
        },
      ],
    },
    {
      path: frontendURL('accounts/:accountId/settings/integrations'),
      component: SettingsWrapper,
      children: [
        {
          path: 'slack',
          name: 'settings_integrations_slack',
          component: Slack,
          meta: {
            featureFlag: FEATURE_FLAGS.INTEGRATIONS,
            permissions: ['administrator', INTEGRATION_MANAGE_PERMISSION],
          },
          props: route => ({ code: route.query.code }),
        },
        {
          path: 'linear',
          name: 'settings_integrations_linear',
          component: Linear,
          meta: {
            permissions: ['administrator', INTEGRATION_MANAGE_PERMISSION],
          },
          props: route => ({ code: route.query.code }),
        },
        {
          path: 'stripe',
          name: 'settings_integrations_stripe',
          component: Stripe,
          meta: {
            featureFlag: FEATURE_FLAGS.STRIPE,
            permissions: ['administrator'],
          },
        },
        {
          path: 'notion',
          name: 'settings_integrations_notion',
          component: Notion,
          meta: {
            permissions: ['administrator', INTEGRATION_MANAGE_PERMISSION],
          },
          props: route => ({ code: route.query.code }),
        },
        {
          path: 'shopify',
          name: 'settings_integrations_shopify',
          component: Shopify,
          meta: {
            featureFlag: FEATURE_FLAGS.SHOPIFY,
            permissions: ['administrator', INTEGRATION_MANAGE_PERMISSION],
          },
          beforeEnter: redirectShopifyIfUnavailable,
          props: route => ({ error: route.query.error }),
        },
        {
          path: 'crm_n8n',
          name: 'settings_integrations_crm_n8n',
          component: CrmN8n,
          meta: {
            featureFlag: FEATURE_FLAGS.INTEGRATIONS,
            permissions: ['administrator', INTEGRATION_MANAGE_PERMISSION],
          },
        },
        {
          path: ':integration_id',
          name: 'settings_applications_integration',
          component: IntegrationHooks,
          meta: {
            featureFlag: FEATURE_FLAGS.INTEGRATIONS,
            permissions: ['administrator', INTEGRATION_MANAGE_PERMISSION],
          },
          props: route => ({
            integrationId: route.params.integration_id,
          }),
        },
      ],
    },
  ],
};
