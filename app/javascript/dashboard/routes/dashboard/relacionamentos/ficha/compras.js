// #3097 — o resumo de compras da ficha: valores por moeda (moedas diferentes não
// se somam), o ticket médio e o tom do grupo de compra.
import { GRUPOS_DE_COMPRA_IDS } from '../fonte/gruposDeCompra';

const formatadores = new Map();
const formatador = (idioma, moeda) => {
  const chave = `${idioma}|${moeda}`;
  if (!formatadores.has(chave)) {
    formatadores.set(
      chave,
      new Intl.NumberFormat(idioma, {
        style: 'currency',
        currency: moeda,
        maximumFractionDigits: 0,
      })
    );
  }
  return formatadores.get(chave);
};

// "há 47 dias" até 3 meses; depois, em meses ou anos ("há 5 meses"). Para
// compra, dia conta mais que "mês passado".
const DIAS_EM_DIAS = 90;
const DIAS_POR_MES = 30;
const MESES_POR_ANO = 12;
export const quandoComprou = (segundos, agoraEmMs, idioma) => {
  const formato = new Intl.RelativeTimeFormat(idioma, { numeric: 'auto' });
  const dias = Math.max(0, Math.floor((agoraEmMs / 1000 - segundos) / 86400));
  if (dias < DIAS_EM_DIAS) return formato.format(-dias, 'day');
  const meses = Math.floor(dias / DIAS_POR_MES);
  if (meses < MESES_POR_ANO) return formato.format(-meses, 'month');
  return formato.format(-Math.floor(meses / MESES_POR_ANO), 'year');
};

export const formatarDinheiro = (valor, moeda, idioma) =>
  formatador(idioma, moeda || 'BRL').format(valor ?? 0);

// [{ moeda, total }] -> "R$ 4.820 · US$ 300".
export const totaisPorMoeda = (porMoeda, idioma, separador) =>
  (porMoeda || [])
    .map(({ moeda, total }) => formatarDinheiro(total, moeda, idioma))
    .join(separador);

// O ticket médio por moeda: o total da moeda dividido pelas compras nela.
export const ticketsPorMoeda = (porMoeda, idioma, separador) =>
  (porMoeda || [])
    .map(({ moeda, total, quantas }) =>
      formatarDinheiro(quantas ? total / quantas : 0, moeda, idioma)
    )
    .join(separador);

const { CAMPEOES, FIEIS, NOVOS, PASSOU_DA_HORA, EM_RISCO, PERDIDOS } =
  GRUPOS_DE_COMPRA_IDS;
const TONS_DO_GRUPO = {
  [CAMPEOES]: 'verde',
  [FIEIS]: 'verde',
  [NOVOS]: 'azul',
  [PASSOU_DA_HORA]: 'ambar',
  [EM_RISCO]: 'ambar',
  [PERDIDOS]: 'vermelho',
};
export const tomDoGrupo = grupoId => TONS_DO_GRUPO[grupoId] || 'neutro';
