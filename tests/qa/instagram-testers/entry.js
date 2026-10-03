import { createApp, h } from 'vue';
import { createStore } from 'vuex';
import { createPinia } from 'pinia';
import { createRouter, createMemoryHistory, RouterView } from 'vue-router';
import { createI18n } from 'vue-i18n';
import VueDOMPurifyHTML from 'vue-dompurify-html';
import FloatingVue from 'floating-vue';
import axios from 'axios';
import App from './App.vue';
import WizardApp from './WizardApp.vue';
import ReauthorizeApp from './ReauthorizeApp.vue';
import ChannelList from 'dashboard/routes/dashboard/settings/inbox/ChannelList.vue';
import ChannelFactory from 'dashboard/routes/dashboard/settings/inbox/ChannelFactory.vue';
import AddAgents from 'dashboard/routes/dashboard/settings/inbox/AddAgents.vue';
import FinishSetup from 'dashboard/routes/dashboard/settings/inbox/FinishSetup.vue';
import WootWizard from 'components/ui/Wizard.vue';
import { computedAppearance } from './visual-helpers.mjs';

const params = new URLSearchParams(window.location.search);
const locale = params.get('locale') === 'en' ? 'en' : 'pt_BR';
const isWizard = params.get('flow') === 'wizard';
const isReauthorize = params.get('flow') === 'reauthorize';
const wizardStage = params.get('stage') || 'channels';
const messages =
  locale === 'en'
    ? (await import('dashboard/i18n/locale/en/index.js')).default
    : (await import('dashboard/i18n/locale/pt_BR/index.js')).default;
window.axios = axios;
window.globalConfig = {
  installationName: 'QA Synthetic',
  frontendUrl: window.location.origin,
};
window.chatwootConfig = {
  instagramAppId: 'synthetic-instagram-app',
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
const wizardPaths = {
  channels: '/app/accounts/910/settings/inboxes/new',
  instagram: '/app/accounts/910/settings/inboxes/new/instagram',
  agents: '/app/accounts/910/settings/inboxes/new/9101/agents',
  finish: '/app/accounts/910/settings/inboxes/new/9101/finish',
};
let pathname = '/app/accounts/910/settings/inboxes/new/instagram';
if (isWizard) pathname = wizardPaths[wizardStage] || wizardPaths.channels;
if (isReauthorize)
  pathname = '/app/accounts/910/settings/inboxes/new/reauthorize';

const wizardRoutes = [
  {
    path: '/app/accounts/:accountId/settings/inboxes/new',
    component: WizardApp,
    children: [
      {
        path: '',
        name: 'settings_inbox_new',
        component: ChannelList,
      },
      {
        path: ':sub_page',
        name: 'settings_inboxes_page_channel',
        component: ChannelFactory,
        props: route => ({ channelName: route.params.sub_page }),
      },
      {
        path: ':inbox_id/agents',
        name: 'settings_inboxes_add_agents',
        component: AddAgents,
      },
      {
        path: ':inbox_id/finish',
        name: 'settings_inbox_finish',
        component: FinishSetup,
      },
    ],
  },
  {
    path: '/app/accounts/:accountId/settings/inboxes/:inboxId',
    name: 'settings_inbox_show',
    component: { template: '<p>QA synthetic inbox settings</p>' },
  },
  {
    path: '/app/accounts/:accountId/inboxes/:inboxId',
    name: 'inbox_dashboard',
    component: { template: '<p>QA synthetic inbox dashboard</p>' },
  },
];
const reauthorizeRoutes = [
  {
    path: '/app/accounts/:accountId/settings/inboxes/new/reauthorize',
    name: 'qa_reauthorize',
    component: ReauthorizeApp,
  },
];
const legacyRoutes = [
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
];
let routes = legacyRoutes;
if (isWizard) routes = wizardRoutes;
if (isReauthorize) routes = reauthorizeRoutes;
const router = createRouter({ history: createMemoryHistory(), routes });
await router.push(pathname);
const syntheticAccount = {
  id: 910,
  name: 'Conta sintética QA',
  features: {
    channel_instagram: true,
    channel_email: true,
    channel_website: true,
  },
};
const syntheticInbox = {
  id: 9101,
  name: 'Instagram QA',
  channel_type: 'Channel::Instagram',
  instagram_id: 'synthetic-instagram-id',
  provider_config: {},
};
const store = createStore({
  getters: {
    getCurrentAccountId: () => 910,
    getSelectedChat: () => null,
  },
  modules: {
    globalConfig: {
      namespaced: true,
      getters: {
        get: () => ({
          instagramTesterAutomationEnabled: params.get('feature') !== 'off',
          installationName: 'QA Synthetic',
          apiChannelName: 'API',
        }),
        isOnChatwootCloud: () => false,
        isMetaInboxCreationDisabled: () => params.get('restricted') === 'true',
        isMetaMessageSendingDisabled: () => false,
      },
    },
    accounts: {
      namespaced: true,
      getters: {
        getAccount: () => () => syntheticAccount,
        isFeatureEnabledonAccount: () => (_id, feature) =>
          Boolean(syntheticAccount.features[feature]),
      },
    },
    inboxes: {
      namespaced: true,
      state: { records: [syntheticInbox] },
      getters: {
        getInboxes: state => state.records,
        getInbox: state => id =>
          state.records.find(record => record.id === Number(id)) || {},
        getInboxById: state => id => {
          const record =
            state.records.find(item => item.id === Number(id)) || {};
          return {
            ...record,
            channelType: record.channel_type,
          };
        },
        getFacebookInboxByInstagramId: () => () => undefined,
      },
    },
    agents: {
      namespaced: true,
      state: {
        records: [
          {
            id: 9102,
            name: 'Ana QA',
            thumbnail: '',
            avatar_url: '',
          },
          {
            id: 9103,
            name: 'Bruno QA',
            thumbnail: '',
            avatar_url: '',
          },
        ],
      },
      getters: { getAgents: state => state.records },
      actions: { get: () => undefined },
    },
    auth: {
      namespaced: true,
      getters: {},
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
const rootComponent =
  isWizard || isReauthorize ? { setup: () => () => h(RouterView) } : App;
const app = createApp(rootComponent);
app.component('woot-wizard', WootWizard);
app.component('woot-code', {
  props: { script: { type: String, default: '' } },
  setup: props => () => h('pre', { class: 'text-start' }, props.script),
});
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
  .use(FloatingVue, {
    instantMove: true,
    arrowOverflow: false,
    themes: { tooltip: { strategy: 'fixed' } },
  })
  .use(VueDOMPurifyHTML)
  .mount('#app');
window.instagramQa.ready = true;
