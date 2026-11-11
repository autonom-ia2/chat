// #2897 — a frase do herói da aba Seguros, escolhida pela ordem do BLOCO-B: sem
// seguro, depois quem vence em até 7 dias, depois quem está em renovação, depois
// o resumo. A frase fala só do grupo para onde o botão leva. Função pura: recebe
// o `resumo()` da fonte e devolve chaves do catálogo e números.
const HEROI = 'RELACIONAMENTOS_CARTEIRA.HEROI';

export const ACOES_DO_HEROI_DE_SEGUROS = {
  TRAZER: 'trazer',
  VER_GRUPO: 'ver_grupo',
};

const verGrupo = (rotulo, grupo) => ({
  rotulo: `${HEROI}.${rotulo}`,
  acao: ACOES_DO_HEROI_DE_SEGUROS.VER_GRUPO,
  grupo,
});

export const fraseDoHeroiDeSeguros = (resumo = {}) => {
  const {
    total = 0,
    vence7 = 0,
    vence7EmRenovacao = 0,
    emRenovacao = 0,
  } = resumo;
  if (total === 0) {
    return {
      id: 'sem_seguro',
      frase: { chave: `${HEROI}.SEM_SEGURO` },
      apoio: { chave: `${HEROI}.SEM_SEGURO_APOIO` },
      principal: {
        rotulo: `${HEROI}.TRAZER_MEUS_SEGUROS`,
        acao: ACOES_DO_HEROI_DE_SEGUROS.TRAZER,
      },
      mostraTrazerDiscreto: false,
    };
  }
  if (vence7 > 0) {
    return {
      id: 'vence_7',
      frase: { chave: `${HEROI}.VENCE_7`, count: vence7 },
      apoio:
        vence7EmRenovacao === vence7
          ? { chave: `${HEROI}.TODOS_EM_RENOVACAO`, count: vence7 }
          : null,
      principal: verGrupo('VER_QUAIS', 'vence_7_dias'),
      mostraTrazerDiscreto: true,
    };
  }
  if (emRenovacao > 0) {
    return {
      id: 'em_renovacao',
      frase: { chave: `${HEROI}.EM_RENOVACAO`, count: emRenovacao },
      apoio: null,
      principal: verGrupo('VER_QUAIS', 'em_renovacao'),
      mostraTrazerDiscreto: true,
    };
  }
  return {
    id: 'resumo',
    frase: { chave: `${HEROI}.RESUMO`, count: total },
    apoio: null,
    principal: verGrupo('VER_TODOS', 'todos'),
    mostraTrazerDiscreto: true,
  };
};
