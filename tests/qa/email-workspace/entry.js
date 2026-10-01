import { createApp } from 'vue';
import { createStore } from 'vuex';
import { createPinia } from 'pinia';
import { createRouter, createMemoryHistory } from 'vue-router';
import { createI18n } from 'vue-i18n';
import axios from 'axios';
import FloatingVue from 'floating-vue';
import '@chatwoot/viz/style.css';
import messages from 'dashboard/i18n/locale/en/index.js';
import emailCampaigns from 'dashboard/store/modules/emailCampaigns';
import emailSenderIdentities from 'dashboard/store/modules/emailSenderIdentities';
import Campaigns from 'dashboard/routes/dashboard/campaigns/pages/EmailCampaignsPage.vue';
import Builder from 'dashboard/routes/dashboard/campaigns/pages/EmailBuilderPage.vue';
import Templates from 'dashboard/routes/dashboard/campaigns/pages/EmailTemplatesPage.vue';
import App from './App.vue';

window.axios = axios;
window.globalConfig = {
  installationName: 'Chat2You',
  frontendUrl: location.origin,
};
window.__qa = { missing: [], errors: [], warnings: [] };
const params = new URLSearchParams(location.search);
document.documentElement.classList.toggle(
  'dark',
  params.get('theme') === 'dark'
);
const router = createRouter({
  history: createMemoryHistory(),
  routes: [
    {
      path: '/app/accounts/:accountId/campaigns/email_campaigns',
      name: 'campaigns_email_index',
      component: Campaigns,
    },
    {
      path: '/app/accounts/:accountId/campaigns/email_campaigns/:campaignId/builder',
      name: 'campaigns_email_builder',
      component: Builder,
    },
    {
      path: '/app/accounts/:accountId/campaigns/email_campaigns/:campaignId?/templates',
      name: 'campaigns_email_templates',
      component: Templates,
    },
  ],
});
await router.push(location.pathname + location.search);
router.afterEach(to => history.replaceState(null, '', to.fullPath));
const readonly = params.get('role') === 'readonly';
const store = createStore({
  getters: {
    getCurrentAccountId: () => 800,
    getCurrentCustomRoleId: () => (readonly ? 1 : null),
    getCurrentUser: () => ({
      accounts: [
        {
          id: 800,
          permissions: readonly
            ? ['campaign_view']
            : ['campaign_view', 'campaign_manage'],
        },
      ],
    }),
  },
  modules: {
    emailCampaigns: {
      ...emailCampaigns,
      state: { ...emailCampaigns.state, records: [], uiFlags: {} },
    },
    emailSenderIdentities: {
      ...emailSenderIdentities,
      state: { ...emailSenderIdentities.state, records: [], uiFlags: {} },
    },
    inboxes: {
      namespaced: true,
      getters: { getInboxes: () => [] },
      actions: { get: () => [] },
    },
    globalConfig: {
      namespaced: true,
      getters: {
        get: () => ({
          emailCampaignEnabled: true,
          crmKanbanEnabled: true,
          installationName: 'Chat2You',
        }),
      },
    },
  },
});
await store.dispatch('emailSenderIdentities/get');
const i18n = createI18n({
  legacy: false,
  locale: 'en',
  fallbackLocale: false,
  messages: { en: messages },
  missing: (locale, key) => window.__qa.missing.push(key),
});
const app = createApp(App);
app.config.errorHandler = (error, instance, info) => {
  window.__qa.errors.push({ message: error.message, info });
  console.error(error);
};
app.config.warnHandler = message => window.__qa.warnings.push(message);
app
  .use(FloatingVue, { themes: { tooltip: { strategy: 'fixed' } } })
  .use(store)
  .use(createPinia())
  .use(router)
  .use(i18n)
  .mount('#app');
window.__qa.ready = true;
