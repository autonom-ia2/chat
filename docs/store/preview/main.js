import { createApp } from 'vue';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import { createRouter, createWebHistory } from 'vue-router';
import FloatingVue from 'floating-vue';
import pt from 'dashboard/i18n/locale/pt_BR/financial.json';
import App from './Preview.vue';
import fixtures from '../../../spec/fixtures/autonomia_store/contracts.v1.json';
import './preview.scss';

const data = structuredClone(fixtures.catalog);
data.data.forEach(item => {
  item.service.logoUrl = null;
  item.service.name =
    item.group === 'agent' ? 'Agente de atendimento' : 'Campanhas de e-mail';
  item.service.description =
    item.group === 'agent'
      ? 'Atendimento especializado com instruções e conhecimento herdados.'
      : 'Organize campanhas e acompanhe os resultados dos envios.';
  item.offers.forEach(offer => {
    offer.plan.name = 'Plano mensal';
    offer.limits.forEach(limit => {
      limit.metricName = 'Contas habilitadas';
      limit.unit = 'contas';
    });
  });
});
const drafts = [];
const publications = {};
const state = { type: 'SuperAdmin' };
const respond = payload => Promise.resolve({ data: structuredClone(payload) });
const denied = () => Promise.reject({ response: { status: 403 } });
// A closed, in-memory transport: no request is made to any backend.
window.axios = {
  get(url) {
    if (store.state.type !== 'SuperAdmin') return denied();
    if (url.endsWith('/catalog')) return respond(data);
    if (url.endsWith('/features'))
      return respond({
        data: ['prospecting', 'email_campaigns', 'whatsapp_api_campaigns'],
      });
    if (url.endsWith('/services'))
      return respond({ data: drafts.filter(value => value.resource === url) });
    if (url.endsWith('/publication')) {
      const id = url.split('/').at(-2);
      if (publications[id]) return respond({ publication: publications[id] });
      return Promise.reject({ response: { status: 404 } });
    }
    throw new Error('Unexpected local request');
  },
  post(url, payload) {
    if (store.state.type !== 'SuperAdmin') return denied();
    if (!url.endsWith('/services')) throw new Error('Unexpected local request');
    let service = drafts.find(value => value.intent === payload.idempotencyKey);
    if (!service) {
      service = {
        id: crypto.randomUUID(),
        name: payload.name,
        intent: payload.idempotencyKey,
        status: 'inactive',
        resource: url,
      };
      drafts.push(service);
    }
    return respond({ service });
  },
  put(url, payload) {
    if (store.state.type !== 'SuperAdmin') return denied();
    if (!url.endsWith('/publication'))
      throw new Error('Unexpected local request');
    return Promise.reject({ response: { status: 409 } });
  },
};
const store = createStore({
  state,
  getters: {
    getCurrentUser: value => ({ type: value.type }),
    'accounts/isRTL': () => false,
    getCurrentAccountId: () => 17,
    'autonomiaAgents/getRecord': () => () => ({
      name: 'Agente de demonstração',
    }),
  },
  mutations: {
    role(value, type) {
      value.type = type;
    },
  },
});
const router = createRouter({
  history: createWebHistory(),
  routes: [{ path: '/:pathMatch(.*)*', component: App }],
});
createApp(App)
  .use(store)
  .use(router)
  .use(createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: pt } }))
  .use(FloatingVue)
  .mount('#app');
