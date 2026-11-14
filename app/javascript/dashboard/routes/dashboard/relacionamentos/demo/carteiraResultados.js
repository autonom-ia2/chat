// #2898 — os resultados das renovações da conta fictícia. Só é carregado no
// ambiente de desenvolvimento. Quantos renovaram, por período e por recorte,
// são números inventados e sempre iguais. Quem NÃO renovou sai da própria
// carteira (demo/carteira.js), para a tela e o grupo "Não renovaram" mostrarem
// os mesmos seguros.
import { EQUIPE, SEGURADORAS } from './carteira';
import {
  PERIODOS,
  SEM_MOTIVO,
  grupoDosQueNaoRenovaram,
} from '../carteira/resultados';
import {
  MOTIVOS,
  MOTIVO_DO_CANCELAMENTO,
  MOTIVO_ESCRITO,
} from '../carteira/situacaoDaRenovacao';
import { seguroPertenceAoGrupo } from '../fonte/gruposDeSeguros';

const TIPOS = ['auto', 'residencial', 'vida', 'empresarial'];

// Por período: quantos renovaram no total e [venceram, renovou] de cada
// recorte, na ordem de TIPOS, SEGURADORAS e EQUIPE.
const TABELA = {
  30: {
    renovou: 14,
    tipo: [
      [9, 7],
      [5, 4],
      [3, 2],
      [2, 1],
    ],
    seguradora: [
      [8, 6],
      [6, 5],
      [3, 2],
      [2, 1],
    ],
    cuida: [
      [11, 8],
      [8, 6],
    ],
  },
  90: {
    renovou: 41,
    tipo: [
      [24, 19],
      [14, 12],
      [8, 6],
      [6, 4],
    ],
    seguradora: [
      [20, 16],
      [16, 13],
      [10, 8],
      [6, 4],
    ],
    cuida: [
      [30, 24],
      [22, 17],
    ],
  },
  365: {
    renovou: 151,
    tipo: [
      [88, 70],
      [52, 43],
      [30, 23],
      [20, 15],
    ],
    seguradora: [
      [72, 58],
      [58, 46],
      [40, 32],
      [20, 15],
    ],
    cuida: [
      [108, 87],
      [82, 64],
    ],
  },
};

const linhas = (nomes, pares, chave) =>
  nomes.map((nome, indice) => ({
    [chave]: nome,
    venceram: pares[indice][0],
    renovou: pares[indice][1],
  }));

const periodo = (dias, carteira, agora) => {
  const { renovou, tipo, seguradora, cuida } = TABELA[dias];
  const perdidos = carteira.filter(seguro =>
    seguroPertenceAoGrupo(seguro, grupoDosQueNaoRenovaram(dias), agora)
  );
  return {
    dias,
    venceram: renovou + perdidos.length,
    renovou,
    naoRenovou: perdidos.length,
    // Como o servidor manda: todos os motivos, mais quem ficou sem motivo.
    motivos: [
      ...[...MOTIVOS, MOTIVO_DO_CANCELAMENTO, MOTIVO_ESCRITO].map(motivo => ({
        motivo,
        quantos: perdidos.filter(seguro => seguro.motivo === motivo).length,
      })),
      {
        motivo: SEM_MOTIVO,
        quantos: perdidos.filter(seguro => !seguro.motivo).length,
      },
    ],
    recortes: {
      tipo: linhas(TIPOS, tipo, 'tipo'),
      seguradora: linhas(SEGURADORAS, seguradora, 'nome'),
      cuida: linhas(EQUIPE, cuida, 'nome'),
    },
  };
};

const vazio = dias => ({
  dias,
  venceram: 0,
  renovou: 0,
  naoRenovou: 0,
  motivos: [],
  recortes: { tipo: [], seguradora: [], cuida: [] },
});

// `carteira`: os seguros da conta (vazia = conta sem seguro).
export const resultadosDaDemo = (carteira, agora = Date.now()) => ({
  periodos: PERIODOS.map(dias =>
    carteira.length ? periodo(dias, carteira, agora) : vazio(dias)
  ),
  vencem30: carteira.filter(seguro =>
    seguroPertenceAoGrupo(seguro, 'vence_30_dias', agora)
  ).length,
});
