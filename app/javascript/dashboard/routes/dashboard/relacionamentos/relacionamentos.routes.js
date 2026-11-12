import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { comFlags } from 'dashboard/helper/comFlags';
import { desvioDoTrazer } from './lista/rotaDoTrazer';

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
// As mesmas flags da lista (`relationships_home`): a tela nova mora dentro do
// menu de Relacionamentos, então quem não o tem não chega nas fichas por link.
const FLAGS = [FLAG, FEATURE_FLAGS.RELATIONSHIPS_NAVIGATION];

const rota = (path, name, component) => ({
  path: frontendURL(`accounts/:accountId/relacionamentos/${path}`),
  name,
  component,
  meta: { featureFlag: FLAG, permissions: PERMISSIONS },
  beforeEnter: comFlags(...FLAGS),
});

// #2947 — até a E3 (#2896) a tela nova de trazer só existe na demonstração: as
// flags decidem primeiro; liberada, fora da demonstração a pessoa cai na
// importação de contatos.
const comAsFlags = comFlags(...FLAGS);
const trazerSoNaDemonstracao = (to, from, next) =>
  comAsFlags(to, from, barrada => {
    const destino = barrada || desvioDoTrazer(to);
    return destino ? next(destino) : next();
  });

export const routes = [
  rota('pessoas/:contactId', 'relacionamentos_pessoa', FichaDaPessoaPage),
  rota('empresas/:companyId', 'relacionamentos_empresa', FichaDaEmpresaPage),
  {
    ...rota('trazer', 'relacionamentos_trazer', TrazerListaPage),
    beforeEnter: trazerSoNaDemonstracao,
  },
];
