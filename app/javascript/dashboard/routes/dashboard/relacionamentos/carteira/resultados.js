// #2898 — os resultados das renovações: os períodos, o grupo de seguros de
// cada um e as contas que a tela faz. Funções puras.
export const PERIODOS = [30, 90, 365];
export const PERIODO_PADRAO = 30;
export const RECORTES = ['tipo', 'seguradora', 'cuida'];

// O grupo temporário da aba Seguros que mostra quem não renovou no período.
export const grupoDosQueNaoRenovaram = dias => `nao_renovaram_${dias}`;

const INTEIRO = 100;
// A largura da barra: quanto de `total` é `parte`, de 0 a 100.
export const porcentagem = (parte, total) =>
  total > 0 ? Math.round((parte / total) * INTEIRO) : 0;

export const periodoEscolhido = (periodos = [], dias = PERIODO_PADRAO) =>
  periodos.find(periodo => periodo.dias === dias) ?? null;

// Os motivos que alguém escolheu no período: quem não tem nenhum seguro não
// vira uma barra vazia. Do mais citado ao menos citado.
export const motivosCitados = (motivos = []) =>
  motivos
    .filter(({ quantos }) => quantos > 0)
    .sort((a, b) => b.quantos - a.quantos);

// Seguros que não renovaram e ficaram sem motivo (a renovação foi fechada pelo
// quadro do funil, que não pergunta o motivo).
export const semMotivo = ({ naoRenovou = 0, motivos = [] } = {}) =>
  Math.max(0, naoRenovou - motivos.reduce((soma, m) => soma + m.quantos, 0));

// As linhas de um recorte que têm o que mostrar (alguém venceu no período).
export const linhasDoRecorte = (recortes = {}, recorte = RECORTES[0]) =>
  (recortes[recorte] ?? []).filter(linha => linha.venceram > 0);

// Os recortes que têm ao menos uma linha: os outros nem viram pílula.
export const recortesComLinhas = (recortes = {}) =>
  RECORTES.filter(recorte => linhasDoRecorte(recortes, recorte).length > 0);
