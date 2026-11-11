import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { comFlags } from 'dashboard/helper/comFlags';

const FichaDaPessoaPage = () => import('./pages/FichaDaPessoaPage.vue');
const FichaDaEmpresaPage = () => import('./pages/FichaDaEmpresaPage.vue');
const TrazerListaPage = () => import('./pages/TrazerListaPage.vue');

// #2894 — as telas novas de Relacionamentos, atrás de relacionamentos_novo. A
// lista não ganha rota: ela é a própria `relationships_home` (ver
// relationships/routes.js), que escolhe a tela pela flag. Mesmas permissões da
// página de hoje.
const PERMISSIONS = [
  'administrator',
  'agent',
  'contact_view',
  'contact_manage',
  'attribute_manage',
];
const FLAG = FEATURE_FLAGS.RELACIONAMENTOS_NOVO;

const rota = (path, name, component) => ({
  path: frontendURL(`accounts/:accountId/relacionamentos/${path}`),
  name,
  component,
  meta: { featureFlag: FLAG, permissions: PERMISSIONS },
  beforeEnter: comFlags(FLAG),
});

export const routes = [
  rota('pessoas/:contactId', 'relacionamentos_pessoa', FichaDaPessoaPage),
  rota('empresas/:companyId', 'relacionamentos_empresa', FichaDaEmpresaPage),
  rota('trazer', 'relacionamentos_trazer', TrazerListaPage),
];
