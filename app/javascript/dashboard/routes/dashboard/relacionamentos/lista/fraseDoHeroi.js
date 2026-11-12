// #2894 — a frase do dia do herói da lista, escolhida pela ordem do BLOCO-A:
// conta vazia, depois quem sumiu há 1 a 3 meses, depois o resumo de clientes.
// Função pura: recebe o `resumo()` da fonte e devolve só chaves de catálogo e
// números; quem desenha traduz (com o plural certo) e emite a ação.
const HEROI = 'RELACIONAMENTOS.LISTA.HEROI';

export const ACOES_DO_HEROI = { TRAZER: 'trazer', VER_GRUPO: 'ver_grupo' };

const trazer = () => ({
  rotulo: 'RELACIONAMENTOS.COMUM.TRAZER_MINHA_LISTA',
  acao: ACOES_DO_HEROI.TRAZER,
});

const verGrupo = (rotulo, grupo) => ({
  rotulo: `${HEROI}.${rotulo}`,
  acao: ACOES_DO_HEROI.VER_GRUPO,
  grupo,
});

// Aba Empresas: o herói fala de empresas. O número da frase é sempre o total do
// grupo para onde o botão leva.
const GRUPO_EMPRESAS_SEM_CONVERSA = 'sem_conversa_3_meses';

const escolherFraseDeEmpresas = ({
  total = 0,
  sem_conversa_3_meses: sem = 0,
}) =>
  sem > 0
    ? {
        id: 'empresas_sem_conversa',
        partes: [{ chave: `${HEROI}.EMPRESAS_SEM_CONVERSA`, count: sem }],
        principal: verGrupo('VER_EMPRESAS', GRUPO_EMPRESAS_SEM_CONVERSA),
        mostraTrazerDiscreto: true,
      }
    : {
        id: 'empresas_resumo',
        partes: [{ chave: `${HEROI}.EMPRESAS_AQUI`, count: total }],
        principal: null,
        mostraTrazerDiscreto: true,
      };

export const escolherFrase = (resumo = {}, aba = 'pessoas') => {
  if (aba === 'empresas' && resumo.empresas?.total > 0) {
    return escolherFraseDeEmpresas(resumo.empresas);
  }
  const { total = 0, clientes = 0, sumiu_1_a_3_meses: sumiram = 0 } = resumo;
  if (total === 0) {
    return {
      id: 'vazia',
      partes: [{ chave: `${HEROI}.VAZIA` }],
      principal: trazer(),
      mostraTrazerDiscreto: false,
    };
  }
  if (sumiram > 0) {
    return {
      id: 'sumiram',
      partes: [{ chave: `${HEROI}.SUMIRAM`, count: sumiram }],
      principal: verGrupo('VER_QUEM_SUMIU', 'sumiu_1_a_3_meses'),
      mostraTrazerDiscreto: true,
    };
  }
  const partes = [{ chave: `${HEROI}.PESSOAS_AQUI`, count: total }];
  if (clientes === 0) {
    // Sem cliente não há o que "ver": o convite volta a ser trazer gente.
    return {
      id: 'resumo',
      partes,
      principal: trazer(),
      mostraTrazerDiscreto: false,
    };
  }
  return {
    id: 'resumo',
    partes: [...partes, { chave: `${HEROI}.JA_SAO_CLIENTES`, count: clientes }],
    principal: verGrupo('VER_CLIENTES', 'clientes'),
    mostraTrazerDiscreto: true,
  };
};
