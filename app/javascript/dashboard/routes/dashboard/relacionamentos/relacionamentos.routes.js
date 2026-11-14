import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { comFlags } from 'dashboard/helper/comFlags';
import { QUEM_TRAZ_LISTA } from './trazer/quemTraz';

const FichaDaPessoaPage = () => import('./pages/FichaDaPessoaPage.vue');
const FichaDaEmpresaPage = () => import('./pages/FichaDaEmpresaPage.vue');
const TrazerListaPage = () => import('./pages/TrazerListaPage.vue');
const AjustarRenovacoesPage = () => import('./pages/AjustarRenovacoesPage.vue');
const ResultadosDasRenovacoesPage = () =>
  import('./pages/ResultadosDasRenovacoesPage.vue');

// #2894 — as telas novas de Relacionamentos, atrás de relacionamentos_novo. A
// lista não ganha rota: ela é a própria `relationships_home` (ver
// relationships/routes.js), que escolhe a tela pela flag. Mesmas permissões da
// página de hoje; "Trazer minha lista" (#2896) é só de quem pode importar
// contato.
// #2898 — "Ajustar renovações" e "Resultados das renovações" são da carteira
// de seguros: a conta sem ela, se chegar pelo endereço, volta para a lista sem
// chamar rota nenhuma (a própria página decide, com useContaDeSeguros).
const PERMISSIONS = [
  'administrator',
  'agent',
  'contact_view',
  'contact_manage',
  'attribute_manage',
];
// #2898 — as duas telas da renovação pedem o que o servidor pede, para a
// pessoa nem chegar a elas sem poder. `meta.permissions` é "uma destas":
// - Resultados: ver contatos, como a carteira inteira (o administrador, o
//   agente sem função e a função com `contact_view` ou `contact_manage`). São
//   as da lista, menos quem só mexe em campos, que não lê a carteira;
// - Ajustar renovações: salvar pede editar contatos E uma chave de funil. A
//   rota pede a chave de funil; quem a tem sem editar contatos lê a escolha de
//   hoje, sem o Salvar (a própria página decide, e o servidor confirma).
export const PERMISSOES_DOS_RESULTADOS = PERMISSIONS.filter(
  permissao => permissao !== 'attribute_manage'
);
export const PERMISSOES_DOS_AJUSTES = [
  'administrator',
  'crm_manage_pipelines',
  'crm_admin',
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
  rota('trazer', 'relacionamentos_trazer', TrazerListaPage, QUEM_TRAZ_LISTA),
  rota(
    'seguros/renovacoes',
    'relacionamentos_renovacoes',
    AjustarRenovacoesPage,
    PERMISSOES_DOS_AJUSTES
  ),
  rota(
    'seguros/resultados',
    'relacionamentos_resultados',
    ResultadosDasRenovacoesPage,
    PERMISSOES_DOS_RESULTADOS
  ),
];
