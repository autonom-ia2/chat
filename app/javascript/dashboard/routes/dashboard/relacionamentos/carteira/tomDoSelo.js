// #2897 — a cor e o nome (chave do catálogo) de cada selo da carteira.
// #2898 — Em renovação vai em azul (alguém já está cuidando) e Renovado em
// verde.
// #3057 — o seguro ativo que vence em até 30 dias diz "Vence logo", em âmbar
// (na lista de pessoas, "Seguro vence logo"): "Ativo" em âmbar não dizia por
// que pedia atenção, e o verde diria que não há nada a fazer. Vale em todo
// lugar que mostra o selo: a aba Seguros, a ficha, o painel da conversa e a
// gaveta.
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

// O seguro ativo que termina em até 30 dias. `dias`: quantos faltam para o
// seguro terminar (sem isso, só o selo decide, e ele não vence logo).
export const venceLogo = (selo, dias = null) =>
  selo === SELOS.ATIVO && Number.isFinite(dias) && dias <= VENCE_LOGO_EM_DIAS;

export const tomDoSelo = (selo, dias = null) => {
  if (venceLogo(selo, dias)) return TOM_DE_QUEM_VENCE_LOGO;
  return CONHECIDOS.includes(selo) ? TONS[selo] : TOM_NEUTRO;
};

const NEUTRO = 'DESCONHECIDO';
const VENCE_LOGO = 'VENCE_LOGO';
const nomeDoSelo = (selo, dias) => {
  if (venceLogo(selo, dias)) return VENCE_LOGO;
  return CONHECIDOS.includes(selo) ? selo.toUpperCase() : NEUTRO;
};

export const chaveDoSelo = (selo, dias = null) =>
  `RELACIONAMENTOS_CARTEIRA.SELOS.${nomeDoSelo(selo, dias)}`;

// Na lista de pessoas o selo diz o texto inteiro ("Seguro vencido").
export const chaveDoSeloDaPessoa = (selo, dias = null) =>
  `RELACIONAMENTOS_CARTEIRA.PESSOAS.SELOS.${nomeDoSelo(selo, dias)}`;
