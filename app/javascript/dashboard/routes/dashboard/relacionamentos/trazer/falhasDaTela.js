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
  // A conta está desfazendo uma lista: trazer agora completaria quem está de
  // saída. É só esperar o desfazer terminar e trazer de novo.
  DESFAZER_EM_CURSO: 'desfazer_em_curso',
  ANDAMENTO: 'andamento',
};

export const NOMES = {
  LEITURA_PENDENTE: 'LEITURA_PENDENTE',
  LEITURA_NAO_ENCONTRADA: 'LEITURA_NAO_ENCONTRADA',
  LEITURA_INTERROMPIDA: 'LEITURA_INTERROMPIDA',
  TELA_DESATUALIZADA: 'TELA_DESATUALIZADA',
  NADA_PARA_TRAZER: 'NADA_PARA_TRAZER',
  // E3 — o servidor não trouxe porque falta dizer quais valores da coluna
  // querem dizer cliente.
  FALTA_VALORES_CLIENTE: 'FALTA_VALORES_CLIENTE',
  CONFERENCIA_VENCIDA: 'CONFERENCIA_VENCIDA',
  DESFAZER_EM_CURSO: 'DESFAZER_EM_CURSO',
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
const AVISO_DESFAZER_EM_CURSO =
  'RELACIONAMENTOS_TRAZER.ERROS.DESFAZER_EM_CURSO';

// O trazer que o servidor recusa com frase própria, que diz o que fazer: não
// tem "tentar de novo" (repetir na hora dá na mesma). O resto é "não consegui
// trazer", com "tentar de novo".
const RECUSAS_DO_TRAZER = new Map([
  [NOMES.NADA_PARA_TRAZER, ERROS.NADA_PARA_TRAZER],
  [NOMES.DESFAZER_EM_CURSO, ERROS.DESFAZER_EM_CURSO],
]);

export const erroDoTrazer = falha =>
  RECUSAS_DO_TRAZER.get(falha?.name) ?? ERROS.TRAZER;

// O aviso do "Tentar de novo" do histórico que não deu certo.
export const avisoDoTentarDeNovo = falha =>
  falha?.name === NOMES.DESFAZER_EM_CURSO
    ? AVISO_DESFAZER_EM_CURSO
    : AVISO_ERRO_TRAZER;
const AVISO_ERRO_GUARDAR = 'RELACIONAMENTOS_TRAZER.ERROS.GUARDAR';
// O que a pergunta dos valores diz a quem tentou trazer sem respondê-la.
export const FRASE_FALTA_VALORES =
  'RELACIONAMENTOS_TRAZER.ERROS.FALTA_VALORES_CLIENTE';
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
