// #2897 — o selo de um seguro: Ativo, Vencido ou Cancelado. O servidor manda o
// selo e os dias que faltam já prontos (`selo`, `dias`), no dia de hoje da
// conta, e a tela usa o que veio: a hora do navegador não muda o selo. Só
// quando eles não vêm (a demonstração e as linhas de exemplo da conta sem
// seguro) a conta é feita aqui, pela data de hoje do navegador.
// #2898 — a renovação soma dois selos: Em renovação (a renovação do seguro
// está aberta no funil e ele ainda vale) e Renovado (a renovação fechou como
// renovada). A regra é a do servidor: cancelado, renovado, vencido, em
// renovação e, sem nada disso, ativo.
import { DIA_EM_MS } from './grupos';

export const SELOS = {
  ATIVO: 'ativo',
  EM_RENOVACAO: 'em_renovacao',
  RENOVADO: 'renovado',
  VENCIDO: 'vencido',
  CANCELADO: 'cancelado',
};

const MS_POR_SEGUNDO = 1000;

// Dias até o seguro terminar; negativo quando já terminou.
export const diasParaTerminar = (seguro, agora = Date.now()) =>
  Number.isInteger(seguro.dias)
    ? seguro.dias
    : Math.round((seguro.termina * MS_POR_SEGUNDO - agora) / DIA_EM_MS);

// A renovação do seguro existe e ainda não terminou (nem renovou, nem não
// renovou).
export const renovacaoAberta = seguro =>
  Boolean(seguro.renovacao) && !seguro.renovacao.desfecho;

const seloPelaData = (seguro, agora) => {
  if (seguro.canceladoEm) return SELOS.CANCELADO;
  if (seguro.renovadoEm) return SELOS.RENOVADO;
  if (diasParaTerminar(seguro, agora) < 0) return SELOS.VENCIDO;
  return renovacaoAberta(seguro) ? SELOS.EM_RENOVACAO : SELOS.ATIVO;
};

export const seloDoSeguro = (seguro, agora = Date.now()) =>
  seguro.selo ?? seloPelaData(seguro, agora);

// Conta como "na carteira, valendo": entra nos grupos de vencimento. O seguro
// em renovação ainda vale; o renovado já tem (ou espera) a apólice nova.
const VALENDO = [SELOS.ATIVO, SELOS.EM_RENOVACAO];
export const estaValendo = (seguro, agora = Date.now()) =>
  VALENDO.includes(seloDoSeguro(seguro, agora));

// A ordem do bloco Seguros da ficha, a mesma do servidor: o que pede atenção
// primeiro, o cancelado por último; no empate, quem termina antes.
const URGENCIA = [
  SELOS.VENCIDO,
  SELOS.EM_RENOVACAO,
  SELOS.RENOVADO,
  SELOS.ATIVO,
  SELOS.CANCELADO,
];

export const porUrgencia = (seguros = [], agora = Date.now()) =>
  [...seguros].sort(
    (a, b) =>
      URGENCIA.indexOf(seloDoSeguro(a, agora)) -
        URGENCIA.indexOf(seloDoSeguro(b, agora)) ||
      a.termina - b.termina ||
      a.id - b.id
  );
