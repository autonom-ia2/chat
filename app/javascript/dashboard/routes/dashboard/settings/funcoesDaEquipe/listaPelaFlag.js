import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { contaDaRota } from 'dashboard/routes/dashboard/autonomia/contaDaRota';

// Funções da equipe guiadas (#2308): a flag da conta escolhe qual lista abre. O menu e os editores de hoje
// apontam para custom_roles_list; com a flag ligada essa rota leva à lista nova, e a nova, com a flag
// desligada, volta para a de hoje. As duas condições são opostas, então nunca há ida e volta.
const guiadasLigadas = async to => {
  const conta = await contaDaRota(to);
  return Boolean(conta?.features?.[FEATURE_FLAGS.FUNCOES_GUIADAS]);
};

export const LISTA_NOVA = 'funcoes_equipe_list';
export const LISTA_ATUAL = 'custom_roles_list';

export const abrirListaNovaSeLigada = async to =>
  (await guiadasLigadas(to)) ? { name: LISTA_NOVA, params: to.params } : true;

export const voltarParaListaAtualSeDesligada = async to =>
  (await guiadasLigadas(to)) ? true : { name: LISTA_ATUAL, params: to.params };
