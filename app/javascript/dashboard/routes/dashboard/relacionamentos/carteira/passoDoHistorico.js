// #2898 — a frase de um passo do histórico do seguro. Função pura: devolve a
// chave do catálogo (dentro de RELACIONAMENTOS_CARTEIRA.HISTORIA) e, quando o
// passo traz um detalhe, qual é. Quatro passos da renovação têm detalhe: quem
// cuida da renovação que começou, o motivo de um toque, o motivo escrito e o
// número da apólice anterior. Sem o detalhe, vale a frase curta do passo ("Não
// renovou."), nunca uma frase com buraco. Do passo "a renovação começou" o
// servidor manda também o funil e o id de quem cuida: a tela usa só o nome, e
// quem não enxerga o card no quadro recebe o passo sem nada disso.
// O passo que a tela não conhece (o servidor ganha passos antes dela) vira uma
// frase neutra: o nome do passo nunca aparece cru.
// #3175 — o seguro do Agger: "Chegou pelo Agger." e, quando o Agger o traz de
// novo e muda algo, "Atualizado pelo Agger." (o passo é o mesmo da planilha,
// `chegou_de_novo`; o do Agger leva a busca em `valores.leitura`). A leitura do
// PDF que o Agger mandou (`pdf_lido`) diz se completou algo, se não havia o que
// completar ou se não deu para ler.
import { DESFECHOS, motivoTemNome } from './situacaoDaRenovacao';

export const DETALHES = {
  CUIDA: 'cuida',
  MOTIVO: 'motivo',
  TEXTO: 'texto',
  ANTERIOR: 'anterior',
};

// Os passos que têm frase em HISTORIA.TIPOS.
export const PASSOS_COM_FRASE = [
  'chegou_planilha',
  'chegou_de_novo',
  'corrigido',
  'cancelado',
  'voltou_a_ativo',
  'pdf_anexado',
  'pdf_tirado',
  'card_nasceu',
  'renovacao_card_nasceu',
  'renovou',
  'nao_renovou',
  'nao_renovou_outro',
  'apolice_nova',
  'desfez_desfecho',
  // #2899 — o seguro que chegou por PDF e o que um PDF atualizou.
  'chegou_pdf',
  'chegou_de_novo_pdf',
  // #2899 (E6.5 e E6.6) — o seguro de outra corretora guardado pelo PDF e o
  // seguro em palavras simples mandado ao cliente.
  'chegou_de_fora',
  'palavras_enviadas',
  // #2901 (E8) — a cotação da renovação: a pergunta "Algo mudou?" e a
  // resposta, a cotação, a proposta e o envio dela. O detalhe (o motivo, o
  // preço) fica na parte Cotação da gaveta: aqui vai só o que aconteceu.
  'cotacao_pedida',
  'algo_mudou_nao_saiu',
  'respondeu_algo_mudou',
  'cliente_respondeu',
  'proposta_pedida',
  'proposta_nao_saiu',
  'proposta_pronta',
  'proposta_enviada',
  'proposta_enviada_sozinha',
  // #3043 (E8.1) — a cotação leu o PDF guardado para achar os dados do
  // segurado. Nenhum valor lido vem no passo.
  'dados_lidos_pdf',
  // #3175 — o seguro que chegou pelo Agger e o PDF dele lido na chegada.
  'chegou_agger',
  'pdf_lido',
];
export const PASSO_SEM_NOME = 'PASSO_SEM_NOME';
// Alguém desfez o "Renovou" ou o "Não renovou": `valores.anterior` diz qual.
const DESFEZ = 'desfez_desfecho';
const DE_NOVO = 'chegou_de_novo';
const PDF_LIDO = 'pdf_lido';
const NAO_E_APOLICE = 'nao_e_apolice';

const DETALHE_DO_TIPO = {
  renovacao_card_nasceu: DETALHES.CUIDA,
  nao_renovou: DETALHES.MOTIVO,
  nao_renovou_outro: DETALHES.TEXTO,
  apolice_nova: DETALHES.ANTERIOR,
};
// O detalhe que a frase sabe escrever: o motivo precisa ter nome no catálogo.
const DETALHE_SERVE = {
  [DETALHES.CUIDA]: Boolean,
  [DETALHES.MOTIVO]: motivoTemNome,
  [DETALHES.TEXTO]: Boolean,
  [DETALHES.ANTERIOR]: Boolean,
};

const semDetalhe = chave => ({ chave, detalhe: null, valor: null });

const fraseDoPdfLido = ({ valores, mudancas }) => {
  if (valores?.recusa === NAO_E_APOLICE) return 'PDF_LIDO.NAO_E_APOLICE';
  if (valores?.recusa) return 'PDF_LIDO.NAO_DEU';
  if (mudancas?.length) return 'TIPOS.PDF_LIDO';
  // "Nada em branco" só quando a leitura terminou; o passo sem desfecho não diz isso.
  return valores?.lido ? 'PDF_LIDO.NADA' : 'PDF_LIDO.NAO_DEU';
};

export const fraseDoPasso = ({ tipo, valores, mudancas }) => {
  if (!PASSOS_COM_FRASE.includes(tipo)) return semDetalhe(PASSO_SEM_NOME);
  const nome = tipo.toUpperCase();
  if (tipo === PDF_LIDO) {
    return semDetalhe(fraseDoPdfLido({ valores, mudancas }));
  }
  if (tipo === DE_NOVO && valores?.leitura) {
    return semDetalhe('DO_AGGER.CHEGOU_DE_NOVO');
  }
  if (tipo === DESFEZ) {
    return Object.values(DESFECHOS).includes(valores?.anterior)
      ? semDetalhe(`DESFEZ.${valores.anterior.toUpperCase()}`)
      : semDetalhe(`TIPOS.${nome}`);
  }
  const detalhe = DETALHE_DO_TIPO[tipo];
  const valor = detalhe ? valores?.[detalhe] : null;
  return detalhe && DETALHE_SERVE[detalhe](valor)
    ? { chave: `TIPOS_COM.${nome}`, detalhe, valor }
    : semDetalhe(`TIPOS.${nome}`);
};
