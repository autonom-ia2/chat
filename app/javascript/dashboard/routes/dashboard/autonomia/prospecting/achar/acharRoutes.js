import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { PROSPECTING_PERMISSIONS } from 'dashboard/constants/permissions.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { comFlags } from 'dashboard/helper/comFlags';
import { ensureProspectingEnabled } from '../../contaDaRota';
import { ROTAS, demoPedido } from './utils/acharRotas';

// #2692 — rotas da Prospecção nova (protótipo), todas atrás da flag
// prospeccao_nova e do mesmo guarda da Prospecção de hoje. Ver e Editar entram;
// quem só vê e abre a porta pelo endereço vai para "Suas buscas" (a própria
// página decide, com o aviso). As telas de hoje continuam nas rotas delas.
const AcharPortaPage = () => import('./pages/AcharPortaPage.vue');
const AcharConfiraPage = () => import('./pages/AcharConfiraPage.vue');
const AcharBuscasPage = () => import('./pages/AcharBuscasPage.vue');
const ParaChamarPage = () => import('./pages/ParaChamarPage.vue');

const meta = {
  permissions: ['administrator', ...PROSPECTING_PERMISSIONS],
  featureFlag: FEATURE_FLAGS.PROSPECCAO_NOVA,
};
const beforeEnter = [
  ensureProspectingEnabled,
  comFlags(FEATURE_FLAGS.PROSPECCAO_NOVA),
];
const base = 'accounts/:accountId/autonomia/prospecting';

// A fila "Para chamar" é da fase 5: fora da demonstração (só em
// desenvolvimento, com ?demo=) o endereço leva para as buscas.
export const soNaDemo = to =>
  demoPedido(to.query)
    ? true
    : { name: ROTAS.BUSCAS, params: { accountId: to.params.accountId } };

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
  {
    path: frontendURL(`${base}/para-chamar`),
    name: ROTAS.FILA,
    meta,
    beforeEnter: [...beforeEnter, soNaDemo],
    component: ParaChamarPage,
  },
];
