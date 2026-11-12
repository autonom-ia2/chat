// #2897 — a situação de um seguro na gaveta: qual frase vai no topo e qual é o
// próximo passo (um só por vez). Função pura; a tela traduz e formata.
import {
  SELOS,
  seloDoSeguro,
  temParcelaAtrasada,
} from '../fonte/selosDoSeguro';

export const ACOES_DO_SEGURO = {
  ABRIR_RENOVACAO: 'ABRIR_RENOVACAO',
  VER_PDF: 'VER_PDF',
  ANEXAR_PDF: 'ANEXAR_PDF',
  AVISAR: 'AVISAR',
  ANEXAR_APOLICE_NOVA: 'ANEXAR_APOLICE_NOVA',
  CONVERSAR_COM: 'CONVERSAR_COM',
};

export const SITUACOES = {
  EM_RENOVACAO: 'em_renovacao',
  ATIVO: 'ativo',
  PARCELA: 'parcela',
  RENOVADO: 'renovado',
  VENCIDO: 'vencido',
  CANCELADO: 'cancelado',
};

const pdfOuAnexar = seguro =>
  seguro.temPdf ? ACOES_DO_SEGURO.VER_PDF : ACOES_DO_SEGURO.ANEXAR_PDF;

export const situacaoDoSeguro = (seguro, agora = Date.now()) => {
  const selo = seloDoSeguro(seguro, agora);
  if (selo === SELOS.CANCELADO) {
    return { id: SITUACOES.CANCELADO, acao: pdfOuAnexar(seguro) };
  }
  if (selo === SELOS.RENOVADO) {
    return {
      id: SITUACOES.RENOVADO,
      acao: ACOES_DO_SEGURO.ANEXAR_APOLICE_NOVA,
    };
  }
  if (selo === SELOS.VENCIDO) {
    return { id: SITUACOES.VENCIDO, acao: ACOES_DO_SEGURO.CONVERSAR_COM };
  }
  if (temParcelaAtrasada(seguro)) {
    return { id: SITUACOES.PARCELA, acao: ACOES_DO_SEGURO.AVISAR };
  }
  if (selo === SELOS.EM_RENOVACAO) {
    return {
      id: SITUACOES.EM_RENOVACAO,
      acao: ACOES_DO_SEGURO.ABRIR_RENOVACAO,
    };
  }
  return { id: SITUACOES.ATIVO, acao: pdfOuAnexar(seguro) };
};

// A proposta em relação ao ano passado: SUBIU, BAIXOU ou IGUAL, com o número.
// Só compara quando a cobertura é a mesma do ano passado: com cobertura
// diferente, "baixou 3%" engana.
export const variacaoDaProposta = proposta => {
  if (!proposta?.mesmaCobertura) return null;
  const { variacao = 0 } = proposta;
  if (variacao > 0) return { id: 'SUBIU', count: variacao };
  return variacao < 0 ? { id: 'BAIXOU', count: -variacao } : { id: 'IGUAL' };
};
