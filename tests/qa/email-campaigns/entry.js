import { createApp } from 'vue';
import { createStore } from 'vuex';
import { createPinia } from 'pinia';
import { createRouter, createMemoryHistory } from 'vue-router';
import { createI18n } from 'vue-i18n';
import axios from 'axios';
import App from './App.vue';

const params = new URLSearchParams(location.search);
const locale = params.get('locale') || 'pt_BR';
const loaders = {
  pt_BR: () => import('dashboard/i18n/locale/pt_BR/index.js'),
  en: () => import('dashboard/i18n/locale/en/index.js'),
  ar: () => import('dashboard/i18n/locale/ar/index.js'),
  de: () => import('dashboard/i18n/locale/de/index.js'),
  ja: () => import('dashboard/i18n/locale/ja/index.js'),
};
const messages = (await loaders[locale]()).default;
window.axios = axios;
window.globalConfig = { installationName: 'QA Synthetic', frontendUrl: location.origin };
window.__qa = { locale, missing: [], vueErrors: [], vueWarnings: [] };
document.documentElement.lang = locale.replace('_', '-');
document.documentElement.dir = locale === 'ar' ? 'rtl' : 'ltr';
document.documentElement.classList.toggle('dark', params.get('theme') === 'dark');
const initialRoute = '/app/accounts/436/crm/campaign-management';
history.replaceState(null, '', initialRoute + location.search);
const router = createRouter({
  history: createMemoryHistory(),
  routes: [{ path: initialRoute, component: App }],
});
await router.push({ path: initialRoute, query: params.get('campaign') ? { email_campaign: params.get('campaign') } : {} });
const store = createStore({
  modules: {
    globalConfig: { namespaced: true, getters: { get: () => ({ emailCampaignEnabled: true, crmKanbanEnabled: true, installationName: 'QA Synthetic' }) } },
    inboxes: { namespaced: true, getters: { getWhatsAppInboxes: () => [] }, actions: { get: () => [] } },
  },
});
const i18n = createI18n({ legacy: false, locale, fallbackLocale: false, messages: { [locale]: messages }, missing: (language, key) => { window.__qa.missing.push({ language, key }); } });
window.__qa.t = (key, values) => i18n.global.t(key, values || {});
const app = createApp(App);
app.config.errorHandler = (error, instance, info) => { window.__qa.vueErrors.push({ message: error.message, info }); console.error(error); };
app.config.warnHandler = message => window.__qa.vueWarnings.push(message);
app.use(store).use(createPinia()).use(router).use(i18n).mount('#app');
window.__qa.ready = true;
