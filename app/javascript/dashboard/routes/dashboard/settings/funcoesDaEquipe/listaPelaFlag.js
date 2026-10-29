import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { contaDaRota } from 'dashboard/routes/dashboard/autonomia/contaDaRota';

// Funções da equipe guiadas (#2308): a flag da conta escolhe qual tela abre. O menu e o editor de hoje apontam para
// custom_roles_*; com a flag ligada essas rotas levam às novas, e as novas, com a flag desligada, voltam para as de
// hoje. As duas condições são opostas, então nunca há ida e volta.
const guiadasLigadas = async to => {
  const conta = await contaDaRota(to);
  return Boolean(conta?.features?.[FEATURE_FLAGS.FUNCOES_GUIADAS]);
};

export const LISTA_NOVA = 'funcoes_equipe_list';
export const LISTA_ATUAL = 'custom_roles_list';
export const CRIAR_NOVA = 'funcoes_equipe_new';
export const ALTERAR_NOVA = 'funcoes_equipe_edit';
export const DUPLICAR_NOVA = 'funcoes_equipe_duplicate';
const CRIAR_ATUAL = 'custom_roles_new';
const ALTERAR_ATUAL = 'custom_roles_edit';

const NOVA_DA_ATUAL = {
  [LISTA_ATUAL]: LISTA_NOVA,
  [CRIAR_ATUAL]: CRIAR_NOVA,
  [ALTERAR_ATUAL]: ALTERAR_NOVA,
};
const ATUAL_DA_NOVA = {
  [LISTA_NOVA]: LISTA_ATUAL,
  [CRIAR_NOVA]: CRIAR_ATUAL,
  [ALTERAR_NOVA]: ALTERAR_ATUAL,
};

// O editor de hoje duplica por ?duplicate=<id>; o novo tem rota própria.
const paraNova = ({ name, params, query = {} }) => {
  if (name === CRIAR_ATUAL && query.duplicate)
    return {
      name: DUPLICAR_NOVA,
      params: { accountId: params.accountId, roleId: query.duplicate },
    };
  return { name: NOVA_DA_ATUAL[name], params };
};

const paraAtual = ({ name, params }) => {
  if (name === DUPLICAR_NOVA)
    return {
      name: CRIAR_ATUAL,
      params: { accountId: params.accountId },
      query: { duplicate: params.roleId },
    };
  return { name: ATUAL_DA_NOVA[name], params };
};

export const abrirNovaSeLigada = async to =>
  (await guiadasLigadas(to)) ? paraNova(to) : true;

export const voltarParaAtualSeDesligada = async to =>
  (await guiadasLigadas(to)) ? true : paraAtual(to);
