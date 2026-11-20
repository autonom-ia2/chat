import { frontendURL } from 'dashboard/helper/URLHelper';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { INSTALLATION_TYPES } from 'dashboard/constants/installationTypes';

// #2894 — a porta de Relacionamentos abre a lista nova de pessoas e empresas, de
// todas as contas desde a E9 (#2902). A aba Empresas é `?aba=empresas` nesta
// mesma rota.
const ListaPage = () => import('../relacionamentos/pages/ListaPage.vue');
const CompanyMediaView = () => import('./CompanyMediaView.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/relationships'),
    name: 'relationships_home',
    component: ListaPage,
    meta: {
      featureFlag: FEATURE_FLAGS.RELATIONSHIPS_NAVIGATION,
      permissions: [
        'administrator',
        'agent',
        'contact_view',
        'contact_manage',
        'attribute_manage',
      ],
    },
  },
  {
    path: frontendURL('accounts/:accountId/companies/:companyId/media'),
    name: 'relationships_company_media',
    component: CompanyMediaView,
    // #3078 — quem lê a empresa no servidor (CompanyPolicy#show?, que a rota de
    // mídias cobra) chega aqui: a função com só ver contatos também.
    meta: {
      featureFlag: FEATURE_FLAGS.RELATIONSHIPS_COMPANY_MEDIA,
      permissions: ['administrator', 'agent', 'contact_view', 'contact_manage'],
      installationTypes: [
        INSTALLATION_TYPES.CLOUD,
        INSTALLATION_TYPES.ENTERPRISE,
      ],
    },
  },
];
