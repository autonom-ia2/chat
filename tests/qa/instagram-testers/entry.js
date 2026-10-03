import { createApp } from 'vue';
import { createStore } from 'vuex';
import { createPinia } from 'pinia';
import { createRouter, createMemoryHistory } from 'vue-router';
import { createI18n } from 'vue-i18n';
import VueDOMPurifyHTML from 'vue-dompurify-html';
import axios from 'axios';
import App from './App.vue';
import { computedAppearance } from './visual-helpers.mjs';

const params = new URLSearchParams(window.location.search);
const locale = params.get('locale') === 'en' ? 'en' : 'pt_BR';
const messages =
  locale === 'en'
    ? (await import('dashboard/i18n/locale/en/index.js')).default
    : (await import('dashboard/i18n/locale/pt_BR/index.js')).default;
window.axios = axios;
window.globalConfig = {
  installationName: 'QA Synthetic',
  frontendUrl: window.location.origin,
};
window.instagramQa = {
  locale,
  missing: [],
  vueErrors: [],
  vueWarnings: [],
  ready: false,
  appearance: computedAppearance,
};
document.documentElement.lang = locale.replace('_', '-');
document.documentElement.classList.toggle(
  'dark',
  params.get('theme') === 'dark'
);
const pathname = '/app/accounts/910/settings/inboxes/new/instagram';
const router = createRouter({
  history: createMemoryHistory(),
  routes: [
    {
      path: '/app/accounts/:accountId/settings/inboxes/new/instagram',
      name: 'qa_instagram',
      component: App,
    },
    {
      path: '/app/accounts/:accountId/settings/inboxes/new',
      name: 'settings_inbox_new',
      component: { template: '<p>QA synthetic channel destination</p>' },
    },
  ],
});
await router.push(pathname);
const store = createStore({
  getters: { getCurrentAccountId: () => 910 },
  modules: {
    globalConfig: {
      namespaced: true,
      getters: {
        get: () => ({
          instagramTesterAutomationEnabled: params.get('feature') !== 'off',
          installationName: 'QA Synthetic',
        }),
        isOnChatwootCloud: () => false,
        isMetaInboxCreationDisabled: () => params.get('restricted') === 'true',
        isMetaMessageSendingDisabled: () => false,
      },
    },
    accounts: {
      namespaced: true,
      getters: {
        getAccount: () => () => ({ id: 910 }),
        isFeatureEnabledonAccount: () => () => false,
      },
    },
  },
});
const i18n = createI18n({
  legacy: false,
  locale,
  fallbackLocale: false,
  messages: { [locale]: messages },
  missing: (language, key) =>
    window.instagramQa.missing.push({ language, key }),
});
// Dynamic lookup is required by the harness; missing keys fail browser QA.
// eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
window.instagramQa.t = (key, values) => i18n.global.t(key, values || {});
const app = createApp(App);
app.config.errorHandler = (error, instance, info) => {
  window.instagramQa.vueErrors.push({ message: error.message, info });
  // eslint-disable-next-line no-console
  console.error(error);
};
app.config.warnHandler = message =>
  window.instagramQa.vueWarnings.push(message);
app
  .use(store)
  .use(createPinia())
  .use(router)
  .use(i18n)
  .use(VueDOMPurifyHTML)
  .mount('#app');
window.instagramQa.ready = true;
