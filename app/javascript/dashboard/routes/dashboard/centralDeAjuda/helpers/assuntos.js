// As famílias da tela inicial: o capítulo vira um assunto de nome curto, agrupado pelo que a pessoa
// quer fazer. A ordem aqui é a ordem na tela. O nome curto é chave de i18n (HELP_CENTER.CENTRAL_DE_AJUDA
// .POR_ASSUNTO.NOMES.<chave>); o título longo continua vindo da API.
export const FAMILIAS = [
  {
    id: 'ATENDER',
    assuntos: [
      ['07', 'CANAIS'],
      ['08', 'CONVERSAS'],
      ['09', 'CONTATOS'],
      ['05', 'TIMES'],
    ],
  },
  {
    id: 'VENDER',
    assuntos: [
      ['10', 'CRM'],
      ['13', 'CAMPANHAS'],
      ['16', 'PROSPECCAO'],
      ['14', 'RELATORIOS'],
      ['15', 'SEGUROS'],
      ['17', 'FINANCEIRO'],
    ],
  },
  {
    id: 'AUTOMATIZAR',
    assuntos: [
      ['11', 'AGENTES_IA'],
      ['12', 'AUTOMACOES'],
      ['06', 'INTEGRACOES'],
    ],
  },
  {
    id: 'CONTA',
    assuntos: [
      ['00', 'PRIMEIROS_PASSOS'],
      ['02', 'PERFIL'],
      ['04', 'EQUIPE'],
      ['03', 'EMPRESA'],
      ['01', 'MAPA'],
      ['18', 'CONCEITOS'],
    ],
  },
];

// Capítulo que surgir depois desta lista cai aqui, com o título da API: assunto novo nunca some.
export const FAMILIA_OUTROS = 'OUTROS';

const conhecidos = new Map(
  FAMILIAS.flatMap(familia =>
    familia.assuntos.map(([id, nome]) => [id, { familia: familia.id, nome }])
  )
);

const assuntoDe = (capitulo, nome) => ({
  id: capitulo.id,
  titulo: capitulo.titulo,
  nome,
  artigos: capitulo.artigos,
  videos: capitulo.artigos.filter(artigo => artigo.video === true).length,
});

// Monta as famílias com o que a API devolveu para a conta. Assunto sem artigo visível não aparece,
// e família que ficou vazia também não.
export const agruparPorFamilia = capitulos => {
  const visiveis = capitulos.filter(capitulo => capitulo.artigos?.length);
  const porId = new Map(visiveis.map(capitulo => [capitulo.id, capitulo]));

  const familias = FAMILIAS.map(familia => ({
    id: familia.id,
    assuntos: familia.assuntos
      .filter(([id]) => porId.has(id))
      .map(([id, nome]) => assuntoDe(porId.get(id), nome)),
  }));

  const outros = {
    id: FAMILIA_OUTROS,
    assuntos: visiveis
      .filter(capitulo => !conhecidos.has(capitulo.id))
      .map(capitulo => assuntoDe(capitulo, null)),
  };

  return [...familias, outros].filter(familia => familia.assuntos.length);
};
