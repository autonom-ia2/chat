// #2897 — a cor e o nome (chave do catálogo) de cada selo da carteira.
import { SELOS, SELO_PARCELA_ATRASADA } from '../fonte/selosDoSeguro';

const TONS = {
  [SELOS.ATIVO]: 'verde',
  [SELOS.EM_RENOVACAO]: 'azul',
  [SELOS.RENOVADO]: 'verde_ok',
  [SELOS.VENCIDO]: 'vermelho',
  [SELOS.CANCELADO]: 'cinza',
  [SELOS.EM_OUTRA_CORRETORA]: 'azulado',
  [SELO_PARCELA_ATRASADA]: 'ambar',
};

export const tomDoSelo = selo => TONS[selo] ?? 'neutro';

export const chaveDoSelo = selo =>
  `RELACIONAMENTOS_CARTEIRA.SELOS.${String(selo).toUpperCase()}`;
