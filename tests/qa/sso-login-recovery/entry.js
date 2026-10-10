import { createApp } from 'vue';
import { createStore } from 'vuex';
import { createPinia } from 'pinia';
import { createRouter, createWebHistory, RouterView } from 'vue-router';
import { createI18n } from 'vue-i18n';
import axios from 'axios';
import FloatingVue from 'floating-vue';
import '@chatwoot/viz/style.css';

const params = new URLSearchParams(window.location.search);
const locale = params.get('locale') || 'pt_BR';
const loaders = {
  en: () => import('dashboard/i18n/locale/en/index.js'),
  pt_BR: () => import('dashboard/i18n/locale/pt_BR/index.js'),
};
const messages = (await loaders[locale]()).default;

window.axios = axios;
window.globalConfig = {
  installationName: 'Chatwoot Synthetic QA',
  frontendUrl: window.location.origin,
};
window.chatwootConfig = {
  apiHost: `${window.location.origin}/`,
  allowedLoginMethods: ['email'],
  autonomiaSsoEnabled: 'true',
  autonomiaSsoAutoRedirect: params.get('auto_redirect') || 'false',
  autonomiaSsoUrl:
    params.get('configured_auth_url') || '/auth/autonomia?source=visual-gate',
  signupEnabled: 'false',
};
window.qa = { locale, missing: [], vueErrors: [], vueWarnings: [] };
document.documentElement.lang = locale.replace('_', '-');
document.documentElement.dir = 'ltr';
const search = params.toString();
window.history.replaceState(
  null,
  '',
  `/app/login${search ? `?${search}` : ''}`
);

const Login = (await import('v3/views/login/Index.vue')).default;
const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/app/login',
      component: Login,
      props: route => ({
        email: route.query.email || '',
        ssoAuthToken: route.query.sso_token || '',
        ssoSource: route.query.sso_source || '',
        redirectTo: route.query.redirect_to || '',
        authError: route.query.error || '',
      }),
    },
  ],
});
await router.push(`/app/login${search ? `?${search}` : ''}`);
const store = createStore({
  modules: {
    globalConfig: {
      namespaced: true,
      getters: {
        get: () => ({
          installationName: 'Chatwoot Synthetic QA',
          logo: 'data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 width=%22160%22 height=%2232%22%3E%3Crect width=%22160%22 height=%2232%22 rx=%228%22 fill=%22%235b5bd6%22/%3E%3Ctext x=%2280%22 y=%2221%22 text-anchor=%22middle%22 font-family=%22Arial%22 font-size=%2214%22 fill=%22white%22%3ESynthetic QA%3C/text%3E%3C/svg%3E',
          logoDark: '',
        }),
      },
    },
  },
});
const i18n = createI18n({
  legacy: false,
  locale,
  fallbackLocale: false,
  messages: { [locale]: messages },
  missing: (language, key) => window.qa.missing.push({ language, key }),
});
const app = createApp(RouterView);
app.config.errorHandler = (error, instance, info) => {
  window.qa.vueErrors.push({ message: error.message, info });
};
app.config.warnHandler = message => window.qa.vueWarnings.push(message);
app.use(FloatingVue, {
  instantMove: true,
  arrowOverflow: false,
  disposeTimeout: 5000000,
  themes: { tooltip: { strategy: 'fixed' } },
});
app.use(store).use(createPinia()).use(router).use(i18n).mount('#app');
window.qa.ready = true;
