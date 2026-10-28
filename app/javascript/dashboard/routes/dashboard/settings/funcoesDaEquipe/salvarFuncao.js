import authAPI from 'dashboard/api/auth';
import { clearCookiesOnLogout } from 'dashboard/store/utils/api';
import { reachesKeys } from 'dashboard/helper/peopleAccess';
import { comImplicadas } from './comImplicadas';
import { nomeEmUso, primeiroNomeLivre } from './nomeDisponivel';

// Salvar uma função guiada (#2308, especificação 14 › Salvar). Devolve { funcao } ou o erro como chave de
// FUNCOES_EQUIPE.SALVAR; `sugestao` vai para o campo do nome. Nunca reenvia sozinho.
const NAO_AUTORIZADO = 401;

// Código que o servidor manda no corpo do 401 (decisão 11, custom_roles_controller.rb) → frase.
const FRASE_DO_401 = {
  out_of_reach: 'FORA_DO_ALCANCE',
  feature_off: 'INDISPONIVEL',
  own_role: 'PROPRIA_FUNCAO',
};

// O 401 só diz que algo foi recusado. Quem decide se a sessão venceu é o /auth/validate_token: com ela boa, o 401
// veio do alcance, da flag ou da própria função; vencida, o app vai para o login sem mensagem. O validityCheck da
// store engole o erro e não zera isLoggedIn, então não serve para decidir.
export const explicar401 = async codigo => {
  try {
    await authAPI.validityCheck();
    return { erro: FRASE_DO_401[codigo] || 'INDISPONIVEL' };
  } catch (error) {
    if (error?.response?.status === NAO_AUTORIZADO) {
      clearCookiesOnLogout();
      return { erro: null };
    }
    return { erro: 'REDE' };
  }
};

// 422 de nome: a lista recarregada diz se é uma função que ela mostra; senão é de uma integração, e a tela sugere
// o primeiro nome livre.
const explicarNome = async (store, nome, id) => {
  await store.dispatch('customRole/getCustomRole');
  const funcoes = store.getters['customRole/getCustomRoles'];
  if (nomeEmUso(nome, funcoes, id)) return { erroDoNome: 'NOME_REPETIDO' };
  const sugestao = primeiroNomeLivre(nome, funcoes, [nome]);
  return { erroDoNome: 'NOME_DE_INTEGRACAO', sugestao };
};

const gravar = (store, id, dados) =>
  id
    ? store.dispatch('customRole/updateCustomRole', { id, ...dados })
    : store.dispatch('customRole/createCustomRole', dados);

export const salvarFuncao = async ({ store, giver, id = null, dados }) => {
  if (!reachesKeys(giver, comImplicadas(dados.permissions)))
    return { erro: 'TRAVA' };
  try {
    return { funcao: await gravar(store, id, dados) };
  } catch (error) {
    if (error?.status === NAO_AUTORIZADO) return explicar401(error.code);
    if (error?.attributes?.includes('name'))
      return explicarNome(store, dados.name, id);
    return { erro: 'REDE' };
  }
};
