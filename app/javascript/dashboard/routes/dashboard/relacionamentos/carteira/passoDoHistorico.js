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
];
export const PASSO_SEM_NOME = 'PASSO_SEM_NOME';
// Alguém desfez o "Renovou" ou o "Não renovou": `valores.anterior` diz qual.
const DESFEZ = 'desfez_desfecho';

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

export const fraseDoPasso = ({ tipo, valores }) => {
  if (!PASSOS_COM_FRASE.includes(tipo)) return semDetalhe(PASSO_SEM_NOME);
  const nome = tipo.toUpperCase();
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
