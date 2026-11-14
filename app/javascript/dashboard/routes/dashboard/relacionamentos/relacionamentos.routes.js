import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { comFlags } from 'dashboard/helper/comFlags';
import { QUEM_TRAZ_LISTA } from './trazer/quemTraz';

const FichaDaPessoaPage = () => import('./pages/FichaDaPessoaPage.vue');
const FichaDaEmpresaPage = () => import('./pages/FichaDaEmpresaPage.vue');
const TrazerPage = () => import('./pages/TrazerPage.vue');

// #2894 — as telas novas de Relacionamentos, atrás de relacionamentos_novo. A
// lista não ganha rota: ela é a própria `relationships_home` (ver
// relationships/routes.js), que escolhe a tela pela flag. Mesmas permissões da
// página de hoje; "Trazer minha lista" (#2896) é só de quem pode importar
// contato.
const PERMISSIONS = [
  'administrator',
  'agent',
  'contact_view',
  'contact_manage',
  'attribute_manage',
];
const FLAG = FEATURE_FLAGS.RELACIONAMENTOS_NOVO;
// As mesmas flags da lista (`relationships_home`): a tela nova mora dentro do
// menu de Relacionamentos, então quem não o tem não chega nas fichas por link.
// Quem leva a uma destas telas de fora (a importação de contatos de hoje,
// #2896) confere as mesmas flags antes.
export const FLAGS_DAS_TELAS_NOVAS = [
  FLAG,
  FEATURE_FLAGS.RELATIONSHIPS_NAVIGATION,
];

const rota = (path, name, component, permissions = PERMISSIONS) => ({
  path: frontendURL(`accounts/:accountId/relacionamentos/${path}`),
  name,
  component,
  meta: { featureFlag: FLAG, permissions },
  beforeEnter: comFlags(...FLAGS_DAS_TELAS_NOVAS),
});

export const routes = [
  rota('pessoas/:contactId', 'relacionamentos_pessoa', FichaDaPessoaPage),
  rota('empresas/:companyId', 'relacionamentos_empresa', FichaDaEmpresaPage),
  rota('trazer', 'relacionamentos_trazer', TrazerPage, QUEM_TRAZ_LISTA),
];
