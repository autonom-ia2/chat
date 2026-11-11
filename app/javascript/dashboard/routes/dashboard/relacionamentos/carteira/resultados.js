// #2897 — os resultados das renovações (Tela 14): os períodos, o grupo de
// seguros de cada um e as contas que a tela faz. Funções puras.
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
