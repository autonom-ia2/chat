// #2084/#2085 — "Este contato é": Interessado, Parceiro do mercado ou Não é negócio.
//   ler(contactId)                      -> { relacao, cardsAbertos, podeEditar }
//   gravar(contactId, relacao, opcoes)  -> { relacao, cardsArquivados, cardsNaoArquivados }
//     opcoes.arquivarCards: arquiva os cards abertos que a pessoa pode arquivar (o mesmo arquivamento do CRM).
import CrmContatoRelacaoAPI from 'dashboard/api/crmContatoRelacao';

export const RELACAO = Object.freeze({
  INTERESSADO: 'interessado',
  PARCEIRO: 'parceiro',
  NAO_E_NEGOCIO: 'nao_e_negocio',
});

export const RELACOES = Object.values(RELACAO);

// O rótulo e a dica de cada uma: PAINEL_DO_CONTATO.RELACAO.OPCOES.<chave>.ROTULO | DICA.
const CHAVE_I18N = {
  [RELACAO.INTERESSADO]: 'INTERESSADO',
  [RELACAO.PARCEIRO]: 'PARCEIRO',
  [RELACAO.NAO_E_NEGOCIO]: 'NAO_E_NEGOCIO',
};
export const chaveDoTexto = (relacao, parte) =>
  `PAINEL_DO_CONTATO.RELACAO.OPCOES.${CHAVE_I18N[relacao]}.${parte}`;

// Fora do funil: não vira card sozinho e não conta nos Números.
export const foraDoFunil = relacao => relacao !== RELACAO.INTERESSADO;

export async function ler(contactId) {
  const { data } = await CrmContatoRelacaoAPI.show(contactId);
  return data;
}

export async function gravar(
  contactId,
  relacao,
  { arquivarCards = false } = {}
) {
  const { data } = await CrmContatoRelacaoAPI.update(contactId, {
    relacao,
    arquivarCards,
  });
  return data;
}
