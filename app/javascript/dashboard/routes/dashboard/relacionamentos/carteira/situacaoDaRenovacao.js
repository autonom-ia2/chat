// #2897 — em que pé está a renovação de um seguro, em palavras de gente: o que
// já foi feito e o que falta (nunca o nome do mecanismo). Função pura: devolve
// o nome da frase; quem desenha traduz. A etapa só decide quando é uma das que
// a casa cria; etapa com o nome trocado por quem usa cai em `EM_ETAPA`, que
// repete o nome que a pessoa deu.
export const DESFECHOS = { NAO_RENOVOU: 'nao_renovou' };

const POR_ETAPA = {
  'A vencer': 'NAO_COMECOU',
  Cotando: 'COTANDO',
  'Opções enviadas': 'OPCOES_ENVIADAS',
  Negociação: 'NEGOCIACAO',
  Renovado: 'RENOVOU',
};
// Antes de a proposta sair, quem manda é a cotação e não o nome da etapa.
const ANTES_DE_ENVIAR = ['NAO_COMECOU', 'COTANDO'];

export const situacaoDaRenovacao = (renovacao = {}) => {
  if (renovacao.desfecho === DESFECHOS.NAO_RENOVOU) {
    return { id: 'NAO_RENOVOU' };
  }
  const id = POR_ETAPA[renovacao.etapa];
  if (!id) return { id: 'EM_ETAPA', etapa: renovacao.etapa };
  if (!ANTES_DE_ENVIAR.includes(id)) return { id };
  const { proposta, cotando } = renovacao;
  if (proposta) {
    return { id: proposta.enviadaEm ? 'OPCOES_ENVIADAS' : 'COTACAO_PRONTA' };
  }
  return { id: cotando ? 'COTANDO' : id };
};
