import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import store from 'dashboard/store';
import {
  PERMISSOES_PARA_CRIAR,
  PERMISSOES_PARA_VER,
} from './helpers/usePodeCriarModelo';

const ModelosListaPage = () => import('./pages/ModelosListaPage.vue');
const ModeloPage = () => import('./pages/ModeloPage.vue');
const ModeloCriarPage = () => import('./pages/ModeloCriarPage.vue');
const ModeloEnviadoPage = () => import('./pages/ModeloEnviadoPage.vue');
const ModeloUsarPage = () => import('./pages/ModeloUsarPage.vue');
const AutorizacaoPage = () => import('./pages/AutorizacaoPage.vue');

// Modelos de mensagem do WhatsApp, nova jornada (#1332), ligada à API de Modelos
// (#1330). Atrás da flag whatsapp_templates_journey: desligada, o endereço volta
// para a tela de sempre (campaigns_templates_index) e o menu não muda.
// Ver e usar: administrador e whatsapp_templates_view/manage. Criar, alterar e
// apagar: administrador e whatsapp_templates_manage.
const VER = PERMISSOES_PARA_VER;

const contaDa = async to => {
  const contaId = Number(to.params.accountId);
  const carregada = store.getters['accounts/getAccount'](contaId);
  if (carregada?.id) return carregada;
  try {
    await store.dispatch('accounts/get');
  } catch {
    return null;
  }
  return store.getters['accounts/getAccount'](contaId);
};

// meta.featureFlag só esconde o menu; quem fecha o endereço é este guarda.
export const exigirJornadaDeModelos = async (to, _from, next) => {
  const conta = await contaDa(to);
  if (conta?.features?.[FEATURE_FLAGS.WHATSAPP_TEMPLATES_JOURNEY]) {
    next();
    return;
  }
  next({ name: 'campaigns_templates_index', params: to.params });
};

// Quem só vê e abre "novo" ou "alterar" pelo endereço volta para a lista (que
// já diz "você pode ver os modelos"), em vez de cair numa tela em branco.
const LISTA = 'campaigns/modelos-whatsapp';
const meta = (permissions, fallbackPath) => ({
  featureFlag: FEATURE_FLAGS.WHATSAPP_TEMPLATES_JOURNEY,
  permissions,
  ...(fallbackPath ? { fallbackPath } : {}),
});

const base = 'accounts/:accountId/campaigns/modelos-whatsapp';

export const routes = [
  {
    path: frontendURL(base),
    name: 'modelos_whatsapp_lista',
    component: ModelosListaPage,
    meta: meta(VER),
    beforeEnter: exigirJornadaDeModelos,
  },
  {
    path: frontendURL(`${base}/novo`),
    name: 'modelos_whatsapp_novo',
    component: ModeloCriarPage,
    meta: meta(PERMISSOES_PARA_CRIAR, LISTA),
    beforeEnter: exigirJornadaDeModelos,
  },
  {
    path: frontendURL(`${base}/enviado`),
    name: 'modelos_whatsapp_enviado',
    component: ModeloEnviadoPage,
    meta: meta(PERMISSOES_PARA_CRIAR, LISTA),
    beforeEnter: exigirJornadaDeModelos,
  },
  // #1586: autorização do dono para o sistema criar modelos (só quem administra modelos).
  {
    path: frontendURL(`${base}/autorizacao`),
    name: 'modelos_whatsapp_autorizacao',
    component: AutorizacaoPage,
    meta: meta(PERMISSOES_PARA_CRIAR, LISTA),
    beforeEnter: exigirJornadaDeModelos,
  },
  {
    path: frontendURL(`${base}/:id`),
    name: 'modelos_whatsapp_modelo',
    component: ModeloPage,
    meta: meta(VER),
    beforeEnter: exigirJornadaDeModelos,
  },
  {
    path: frontendURL(`${base}/:id/alterar`),
    name: 'modelos_whatsapp_alterar',
    component: ModeloCriarPage,
    meta: meta(PERMISSOES_PARA_CRIAR, LISTA),
    beforeEnter: exigirJornadaDeModelos,
  },
  {
    path: frontendURL(`${base}/:id/usar`),
    name: 'modelos_whatsapp_usar',
    component: ModeloUsarPage,
    meta: meta(VER),
    beforeEnter: exigirJornadaDeModelos,
  },
];
