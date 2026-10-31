import { FEATURE_FLAGS } from '../../../../featureFlags';
import { frontendURL } from '../../../../helper/URLHelper';

// #2414 F0 — protótipo navegável da "Automação livre". Só desta branch; não vai
// para produção como está. As mesmas permissões de automacoes.routes.js.
const LivreLayout = () => import('./pages/LivreLayout.vue');
const LivreListaPage = () => import('./pages/LivreListaPage.vue');
const LivreComecarPage = () => import('./pages/LivreComecarPage.vue');
const LivreReceitasPage = () => import('./pages/LivreReceitasPage.vue');
const LivreContePage = () => import('./pages/LivreContePage.vue');
const LivreEditorPage = () => import('./pages/LivreEditorPage.vue');
const LivreFunilPage = () => import('./pages/LivreFunilPage.vue');

const VER = ['administrator', 'automation_view', 'automation_manage'];
const MUDAR = ['administrator', 'automation_manage'];
const meta = permissions => ({
  featureFlag: FEATURE_FLAGS.AUTOMATIONS,
  permissions,
});

export const routes = [
  {
    path: frontendURL('accounts/:accountId/automacoes/livre'),
    component: LivreLayout,
    meta: meta(VER),
    children: [
      {
        path: '',
        name: 'automacoes_livre_lista',
        component: LivreListaPage,
        meta: meta(VER),
      },
      {
        path: 'comecar',
        name: 'automacoes_livre_comecar',
        component: LivreComecarPage,
        meta: meta(MUDAR),
      },
      {
        path: 'receitas',
        name: 'automacoes_livre_receitas',
        component: LivreReceitasPage,
        meta: meta(MUDAR),
      },
      {
        path: 'conte',
        name: 'automacoes_livre_conte',
        component: LivreContePage,
        meta: meta(MUDAR),
      },
      {
        path: 'funil',
        name: 'automacoes_livre_funil',
        component: LivreFunilPage,
        meta: meta(VER),
      },
      {
        path: 'nova',
        name: 'automacoes_livre_nova',
        component: LivreEditorPage,
        meta: meta(MUDAR),
      },
      {
        path: ':id',
        name: 'automacoes_livre_editar',
        component: LivreEditorPage,
        meta: meta(VER),
      },
    ],
  },
];
