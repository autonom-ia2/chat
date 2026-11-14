// #2897 — a cor e o nome (chave do catálogo) de cada selo da carteira. O
// seguro ativo que vence logo continua "Ativo", mas em âmbar: o verde diria
// que não há nada a fazer.
// #2898 — Em renovação vai em azul (alguém já está cuidando) e Renovado em
// verde.
import { SELOS } from '../fonte/selosDoSeguro';

const TONS = {
  [SELOS.ATIVO]: 'verde',
  [SELOS.EM_RENOVACAO]: 'azul',
  [SELOS.RENOVADO]: 'verde',
  [SELOS.VENCIDO]: 'vermelho',
  [SELOS.CANCELADO]: 'neutro',
};
const TOM_DE_QUEM_VENCE_LOGO = 'ambar';
const TOM_NEUTRO = 'neutro';
// O selo que a tela não conhece (o servidor ganha selos antes dela) ou que
// não veio: cor neutra e texto neutro, e a chave do catálogo nunca aparece
// crua.
const CONHECIDOS = Object.values(SELOS);
export const VENCE_LOGO_EM_DIAS = 30;

// `dias`: quantos faltam para o seguro terminar (sem isso, só o selo decide).
export const tomDoSelo = (selo, dias = null) => {
  const venceLogo =
    selo === SELOS.ATIVO && dias !== null && dias <= VENCE_LOGO_EM_DIAS;
  if (venceLogo) return TOM_DE_QUEM_VENCE_LOGO;
  return CONHECIDOS.includes(selo) ? TONS[selo] : TOM_NEUTRO;
};

const NEUTRO = 'DESCONHECIDO';
const nomeDoSelo = selo =>
  CONHECIDOS.includes(selo) ? selo.toUpperCase() : NEUTRO;

export const chaveDoSelo = selo =>
  `RELACIONAMENTOS_CARTEIRA.SELOS.${nomeDoSelo(selo)}`;

// Na lista de pessoas o selo diz o texto inteiro ("Seguro vencido").
export const chaveDoSeloDaPessoa = selo =>
  `RELACIONAMENTOS_CARTEIRA.PESSOAS.SELOS.${nomeDoSelo(selo)}`;
