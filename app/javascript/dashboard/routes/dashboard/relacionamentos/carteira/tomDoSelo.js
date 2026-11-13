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
export const VENCE_LOGO_EM_DIAS = 30;

// `dias`: quantos faltam para o seguro terminar (sem isso, só o selo decide).
export const tomDoSelo = (selo, dias = null) => {
  const venceLogo =
    selo === SELOS.ATIVO && dias !== null && dias <= VENCE_LOGO_EM_DIAS;
  return venceLogo ? TOM_DE_QUEM_VENCE_LOGO : (TONS[selo] ?? 'neutro');
};

export const chaveDoSelo = selo =>
  `RELACIONAMENTOS_CARTEIRA.SELOS.${String(selo).toUpperCase()}`;
