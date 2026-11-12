import {
  FRASE_MUITO_LONGO,
  MOTIVO_MUITO_LONGO,
  MOTIVO_NAO_SALVOU,
  MOTIVO_PLANILHA_APAGADA,
} from './recusaDoConserto';

// #2896 — o que deu errado em "Trazer minha lista", para a tela escolher a
// frase e o lugar dela. Aqui só há tabelas: o nome que a fonte dá a cada falha
// (fonte/trazerTraducao.js) vira o erro da tela, a frase da recusa ou o motivo
// que o cartão da linha mostra.
export const ERROS = {
  NENHUM: '',
  TIPO: 'tipo',
  GRANDE: 'grande',
  LEITURA: 'leitura',
  VAZIA: 'vazia',
  SEM_CONTATO: 'sem_contato',
  // A planilha está no servidor e ele ainda não terminou de ler.
  DEMOROU: 'demorou',
  // Depois de uma mudança, a planilha foi lida de novo e não sobrou ninguém.
  SEM_NINGUEM: 'sem_ninguem',
  // A leitura já virou lista (em outra aba, ou por outra pessoa da conta).
  JA_TRAZIDA: 'ja_trazida',
  // A planilha foi enviada há mais de 7 dias e já foi apagada do servidor.
  VENCIDA: 'vencida',
  TRAZER: 'trazer',
  NADA_PARA_TRAZER: 'nada_para_trazer',
  ANDAMENTO: 'andamento',
};

export const NOMES = {
  LEITURA_PENDENTE: 'LEITURA_PENDENTE',
  LEITURA_NAO_ENCONTRADA: 'LEITURA_NAO_ENCONTRADA',
  LEITURA_INTERROMPIDA: 'LEITURA_INTERROMPIDA',
  TELA_DESATUALIZADA: 'TELA_DESATUALIZADA',
  NADA_PARA_TRAZER: 'NADA_PARA_TRAZER',
  CONFERENCIA_VENCIDA: 'CONFERENCIA_VENCIDA',
};

// O envio e a leitura que não deram certo.
const ERROS_DA_LEITURA = new Map([
  ['PLANILHA_TIPO', ERROS.TIPO],
  ['PLANILHA_GRANDE', ERROS.GRANDE],
  ['PLANILHA_VAZIA', ERROS.VAZIA],
  ['PLANILHA_SEM_CONTATO', ERROS.SEM_CONTATO],
  [NOMES.LEITURA_PENDENTE, ERROS.DEMOROU],
  [NOMES.CONFERENCIA_VENCIDA, ERROS.VENCIDA],
]);

export const erroDaLeitura = falha =>
  ERROS_DA_LEITURA.get(falha?.name) ?? ERROS.LEITURA;

// A leitura que a tela foi buscar pelo id (a pessoa recarregou a página): a que
// o servidor não acha já foi trazida.
export const erroDaRetomada = falha =>
  falha?.name === NOMES.LEITURA_NAO_ENCONTRADA
    ? ERROS.JA_TRAZIDA
    : erroDaLeitura(falha);

// A lista que não foi trazida (o trazer que parou no meio, ou o "tentar de
// novo" do histórico que falhou).
export const AVISO_ERRO_TRAZER = 'RELACIONAMENTOS_TRAZER.ERROS.TRAZER';
const AVISO_ERRO_GUARDAR = 'RELACIONAMENTOS_TRAZER.ERROS.GUARDAR';
const AVISO_SEM_COLUNA_DE_CONTATO =
  'RELACIONAMENTOS_TRAZER.ERROS.SEM_COLUNA_DE_CONTATO';
// A escrita que a fonte recusa com nome e que tem frase própria: a que tira a
// última coluna de contato e o telefone da empresa numa leitura sem empresa.
const FRASES_DA_RECUSA = new Map([
  ['TROCA_SEM_CONTATO', AVISO_SEM_COLUNA_DE_CONTATO],
  ['SEM_EMPRESA', 'RELACIONAMENTOS_TRAZER.ERROS.SEM_EMPRESA'],
]);
const VALOR_INVALIDO = 'VALOR_INVALIDO';
const PLANILHA_APAGADA = 'PLANILHA_APAGADA';

// A frase de uma escrita que falhou (a troca de uma coluna, a resposta de uma
// pergunta). O texto longo demais (o nome da informação nova ou o "para que
// serve") tem frase própria; o resto, a da recusa que tem nome ou "não
// consegui salvar".
export const fraseDaEscrita = falha =>
  falha?.name === VALOR_INVALIDO && falha.motivo === MOTIVO_MUITO_LONGO
    ? FRASE_MUITO_LONGO
    : (FRASES_DA_RECUSA.get(falha?.name) ?? AVISO_ERRO_GUARDAR);

// O que o cartão da linha diz quando a escrita nela falha: o motivo do valor
// que não vale (no código do servidor), a planilha que já foi apagada ou, em
// qualquer outra falha (o servidor caiu, a rede caiu), que não salvou. Só a
// recusa do valor fala do valor (trazer/recusaDoConserto.js).
export const motivoDaRecusa = falha => {
  if (falha?.name === VALOR_INVALIDO) return falha.motivo ?? '';
  if (falha?.name === PLANILHA_APAGADA) return MOTIVO_PLANILHA_APAGADA;
  return MOTIVO_NAO_SALVOU;
};
