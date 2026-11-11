// #2897 — os resultados das renovações da conta fictícia (Tela 14). Só é
// carregado no ambiente de desenvolvimento. Quantos venceram e quantos
// renovaram, por período e por recorte, são números inventados e sempre iguais.
// Quem NÃO renovou sai da própria carteira (os vencidos de demo/carteira.js),
// para a tela e a lista "Não renovaram" mostrarem os mesmos seguros.
import { EQUIPE, MOTIVOS, SEGURADORAS } from './carteiraPlano';
import { seguroPertenceAoGrupo } from '../fonte/gruposDeSeguros';
import { PERIODOS, grupoDosQueNaoRenovaram } from '../carteira/resultados';

const TIPOS = ['auto', 'residencial', 'vida', 'empresarial'];

// Por período: [venceram, renovou] do total e de cada recorte, na ordem de
// TIPOS, SEGURADORAS e EQUIPE.
const TABELA = {
  30: {
    total: [19, 14],
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
    total: [52, 41],
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
    total: [190, 151],
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
  const { total, tipo, seguradora, cuida } = TABELA[dias];
  const perdidos = carteira.filter(seguro =>
    seguroPertenceAoGrupo(seguro, grupoDosQueNaoRenovaram(dias), agora)
  );
  return {
    dias,
    venceram: total[0],
    renovou: total[1],
    naoRenovou: perdidos.length,
    motivos: MOTIVOS.map(motivo => ({
      motivo,
      quantos: perdidos.filter(seguro => seguro.motivo === motivo).length,
    })),
    recortes: {
      tipo: linhas(TIPOS, tipo, 'tipo'),
      seguradora: linhas(SEGURADORAS, seguradora, 'nome'),
      cuida: linhas(EQUIPE, cuida, 'nome'),
    },
  };
};

const VAZIO = dias => ({
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
    carteira.length ? periodo(dias, carteira, agora) : VAZIO(dias)
  ),
  vencem30: carteira.filter(seguro =>
    seguroPertenceAoGrupo(seguro, 'vence_30_dias', agora)
  ).length,
});
