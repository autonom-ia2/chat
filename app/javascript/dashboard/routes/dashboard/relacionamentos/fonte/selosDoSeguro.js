// #2897 — o selo de um seguro: Ativo, Vencido ou Cancelado. O servidor manda o
// selo e os dias que faltam já prontos (`selo`, `dias`), no dia de hoje da
// conta, e a tela usa o que veio: a hora do navegador não muda o selo. Só
// quando eles não vêm (a demonstração e as linhas de exemplo da conta sem
// seguro) a conta é feita aqui, pela data de hoje do navegador.
import { DIA_EM_MS } from './grupos';

export const SELOS = {
  ATIVO: 'ativo',
  VENCIDO: 'vencido',
  CANCELADO: 'cancelado',
};

const MS_POR_SEGUNDO = 1000;

// Dias até o seguro terminar; negativo quando já terminou.
export const diasParaTerminar = (seguro, agora = Date.now()) =>
  Number.isInteger(seguro.dias)
    ? seguro.dias
    : Math.round((seguro.termina * MS_POR_SEGUNDO - agora) / DIA_EM_MS);

const seloPelaData = (seguro, agora) => {
  if (seguro.canceladoEm) return SELOS.CANCELADO;
  return diasParaTerminar(seguro, agora) < 0 ? SELOS.VENCIDO : SELOS.ATIVO;
};

export const seloDoSeguro = (seguro, agora = Date.now()) =>
  seguro.selo ?? seloPelaData(seguro, agora);

// Conta como "na carteira, valendo": entra nos grupos de vencimento.
export const estaValendo = (seguro, agora = Date.now()) =>
  seloDoSeguro(seguro, agora) === SELOS.ATIVO;

// A ordem do bloco Seguros da ficha, a mesma do servidor: o que pede atenção
// primeiro, o cancelado por último; no empate, quem termina antes.
const URGENCIA = [SELOS.VENCIDO, SELOS.ATIVO, SELOS.CANCELADO];

export const porUrgencia = (seguros = [], agora = Date.now()) =>
  [...seguros].sort(
    (a, b) =>
      URGENCIA.indexOf(seloDoSeguro(a, agora)) -
        URGENCIA.indexOf(seloDoSeguro(b, agora)) ||
      a.termina - b.termina ||
      a.id - b.id
  );
