import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { PROSPECTING_PERMISSIONS } from 'dashboard/constants/permissions.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { comFlags } from 'dashboard/helper/comFlags';
import { ensureProspectingEnabled } from '../../contaDaRota';
import { ROTAS } from './utils/acharRotas';

// #2692 — rotas da Prospecção nova (protótipo), todas atrás da flag
// prospeccao_nova e do mesmo guarda da Prospecção de hoje. A fila "Para
// chamar" abre fora da demonstração desde a fase 5 (#2697). Ver e Editar entram;
// quem só vê e abre a porta pelo endereço vai para "Suas buscas" (a própria
// página decide, com o aviso). As telas de hoje continuam nas rotas delas.
const AcharPortaPage = () => import('./pages/AcharPortaPage.vue');
const AcharConfiraPage = () => import('./pages/AcharConfiraPage.vue');
const AcharBuscasPage = () => import('./pages/AcharBuscasPage.vue');
const ParaChamarPage = () => import('./pages/ParaChamarPage.vue');
const AcharListasPage = () => import('./pages/AcharListasPage.vue');
const AcharListaPage = () => import('./pages/AcharListaPage.vue');

const meta = {
  permissions: ['administrator', ...PROSPECTING_PERMISSIONS],
  featureFlag: FEATURE_FLAGS.PROSPECCAO_NOVA,
};
const beforeEnter = [
  ensureProspectingEnabled,
  comFlags(FEATURE_FLAGS.PROSPECCAO_NOVA),
];
const base = 'accounts/:accountId/autonomia/prospecting';

export const acharRoutes = [
  {
    path: frontendURL(`${base}/achar`),
    name: ROTAS.PORTA,
    meta,
    beforeEnter,
    component: AcharPortaPage,
  },
  {
    path: frontendURL(`${base}/achar/buscas`),
    name: ROTAS.BUSCAS,
    meta,
    beforeEnter,
    component: AcharBuscasPage,
  },
  {
    path: frontendURL(`${base}/achar/buscas/:searchId`),
    name: ROTAS.BUSCA,
    meta,
    beforeEnter,
    component: AcharConfiraPage,
  },
  {
    path: frontendURL(`${base}/achar/nova/:searchId`),
    name: ROTAS.NOVA,
    meta,
    beforeEnter,
    component: AcharConfiraPage,
  },
  // "Suas listas" (#2775, F6): a aba ao lado de "Suas buscas" e a lista aberta.
  {
    path: frontendURL(`${base}/achar/listas`),
    name: ROTAS.LISTAS,
    meta,
    beforeEnter,
    component: AcharListasPage,
  },
  {
    path: frontendURL(`${base}/achar/listas/:listaId`),
    name: ROTAS.LISTA,
    meta,
    beforeEnter,
    component: AcharListaPage,
  },
  {
    path: frontendURL(`${base}/para-chamar`),
    name: ROTAS.FILA,
    meta,
    beforeEnter,
    component: ParaChamarPage,
  },
];
