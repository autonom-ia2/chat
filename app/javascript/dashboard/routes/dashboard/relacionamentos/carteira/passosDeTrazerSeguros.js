// #2897 — os passos de "trazer seguros", em funções puras. Primeiro a escolha
// de como trazer (planilha, PDFs ou Agger); depois cada jeito tem o seu começo
// e todos terminam igual: conferir -> trazendo -> pronto. Ler os PDFs e buscar
// no Agger acontecem dentro do primeiro passo de cada um (enviar e ligar).
import { ETAPAS } from '../trazer/etapas';

export const COMO = { PLANILHA: 'planilha', PDFS: 'pdfs', AGGER: 'agger' };
const JEITOS = Object.values(COMO);

export const comoValido = valor => (JEITOS.includes(valor) ? valor : '');

export const PASSOS = {
  COMO: 'como',
  ENVIAR: 'enviar',
  PERGUNTA: 'pergunta',
  LIGAR: 'ligar',
  CONFERIR: 'conferir',
  TRAZENDO: 'trazendo',
  PRONTO: 'pronto',
};

const PRIMEIRO = {
  [COMO.PLANILHA]: PASSOS.ENVIAR,
  [COMO.PDFS]: PASSOS.ENVIAR,
  [COMO.AGGER]: PASSOS.LIGAR,
};

export const primeiroPasso = como => PRIMEIRO[como] ?? PASSOS.COMO;

// De onde o Voltar de cada passo leva; o que não está aqui volta à escolha.
const ANTES = {
  [COMO.PLANILHA]: {
    [PASSOS.PERGUNTA]: PASSOS.ENVIAR,
    [PASSOS.CONFERIR]: PASSOS.PERGUNTA,
  },
  [COMO.PDFS]: { [PASSOS.CONFERIR]: PASSOS.ENVIAR },
  [COMO.AGGER]: { [PASSOS.CONFERIR]: PASSOS.LIGAR },
};

export const passoAnterior = (como, passo) =>
  ANTES[como]?.[passo] ?? PASSOS.COMO;

// Enviar -> Conferir -> Pronto, no topo. Na escolha as etapas ainda não
// aparecem.
const NO_FIM = [PASSOS.TRAZENDO, PASSOS.PRONTO];

export const etapaDoTopoDe = passo => {
  if (passo === PASSOS.COMO) return null;
  if (passo === PASSOS.CONFERIR) return ETAPAS.CONFERIR;
  return NO_FIM.includes(passo) ? ETAPAS.PRONTO : ETAPAS.ENVIAR;
};
