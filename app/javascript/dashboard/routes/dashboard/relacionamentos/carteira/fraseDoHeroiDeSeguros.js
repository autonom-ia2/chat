// #2897 — a frase do herói da aba Seguros. A ordem é a da urgência: sem
// seguro; quem vence em até 7 dias; quem já venceu; e, sem nada disso, o
// resumo. A frase fala só do grupo para onde o botão leva; a carteira vazia
// não tem botão. Função pura: recebe o `resumo()` da fonte e quantos seguros
// estão vencidos (a contagem do grupo Vencido, que a barra de grupos já
// carrega) e devolve chaves do catálogo e números.
import { GRUPO_VENCIDO } from '../fonte/gruposDeSeguros';

const HEROI = 'RELACIONAMENTOS_CARTEIRA.HEROI';

const verGrupo = (rotulo, grupo) => ({ rotulo: `${HEROI}.${rotulo}`, grupo });

export const fraseDoHeroiDeSeguros = (resumo = {}, vencidos = 0) => {
  const { total = 0, vence7 = 0 } = resumo;
  if (total === 0) {
    return {
      id: 'sem_seguro',
      frase: { chave: `${HEROI}.SEM_SEGURO` },
      apoio: { chave: `${HEROI}.SEM_SEGURO_APOIO` },
      principal: null,
    };
  }
  if (vence7 > 0) {
    return {
      id: 'vence_7',
      frase: { chave: `${HEROI}.VENCE_7`, count: vence7 },
      apoio: null,
      principal: verGrupo('VER_QUAIS', 'vence_7_dias'),
    };
  }
  if (vencidos > 0) {
    return {
      id: 'vencidos',
      frase: { chave: `${HEROI}.VENCIDOS`, count: vencidos },
      apoio: null,
      principal: verGrupo('VER_VENCIDOS', GRUPO_VENCIDO),
    };
  }
  return {
    id: 'resumo',
    frase: { chave: `${HEROI}.RESUMO`, count: total },
    apoio: null,
    principal: verGrupo('VER_TODOS', 'todos'),
  };
};
