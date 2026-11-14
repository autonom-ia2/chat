// #2898 — os resultados das renovações: os períodos, o grupo de seguros de
// cada um e as contas que a tela faz. Funções puras.
import { MOTIVO_ESCRITO, motivoTemNome } from './situacaoDaRenovacao';

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

// A linha que o servidor manda junto com os motivos para quem não renovou e
// ninguém disse por quê. Não é um motivo: a tela a mostra por último.
export const SEM_MOTIVO = 'sem_motivo';

// O motivo que a tela ainda não conhece entra em "Outro motivo": o nome dele
// nunca aparece cru.
const motivoDaBarra = motivo =>
  motivoTemNome(motivo) ? motivo : MOTIVO_ESCRITO;

const somados = motivos =>
  motivos.reduce(
    (soma, { motivo, quantos }) =>
      soma.set(
        motivoDaBarra(motivo),
        (soma.get(motivoDaBarra(motivo)) ?? 0) + quantos
      ),
    new Map()
  );

// Os motivos que alguém escolheu no período: quem não tem nenhum seguro não
// vira uma barra vazia. Do mais citado ao menos citado.
export const motivosCitados = (motivos = []) =>
  [...somados(motivos.filter(({ motivo }) => motivo !== SEM_MOTIVO))]
    .map(([motivo, quantos]) => ({ motivo, quantos }))
    .filter(({ quantos }) => quantos > 0)
    .sort((a, b) => b.quantos - a.quantos);

// Seguros que não renovaram e ficaram sem motivo (a renovação foi fechada pelo
// quadro do funil, que não pergunta o motivo, ou o seguro só venceu). O
// servidor manda a conta pronta; sem ela, é o que sobra de quem não renovou.
export const semMotivo = ({ naoRenovou = 0, motivos = [] } = {}) => {
  const pronta = motivos.find(({ motivo }) => motivo === SEM_MOTIVO);
  return pronta
    ? pronta.quantos
    : Math.max(
        0,
        naoRenovou - motivos.reduce((soma, m) => soma + m.quantos, 0)
      );
};

// As linhas de um recorte que têm o que mostrar (alguém venceu no período).
export const linhasDoRecorte = (recortes = {}, recorte = RECORTES[0]) =>
  (recortes[recorte] ?? []).filter(linha => linha.venceram > 0);

// Os recortes que têm ao menos uma linha: os outros nem viram pílula.
export const recortesComLinhas = (recortes = {}) =>
  RECORTES.filter(recorte => linhasDoRecorte(recortes, recorte).length > 0);
