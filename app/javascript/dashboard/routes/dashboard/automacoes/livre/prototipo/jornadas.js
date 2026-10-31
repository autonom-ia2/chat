// #2414 F0 — o mapa da jornada do protótipo. Cada etapa tem a própria URL
// (rota + query), para o kit tirar o print sozinho, e uma nota curta "o que muda
// em relação a hoje" em AUTOMACAO_LIVRE.JORNADA.<jornada>.<etapa>.
const LISTA = 'automacoes_livre_lista';
const COMECAR = 'automacoes_livre_comecar';
const RECEITAS = 'automacoes_livre_receitas';
const CONTE = 'automacoes_livre_conte';
const NOVA = 'automacoes_livre_nova';
const EDITAR = 'automacoes_livre_editar';
const FUNIL = 'automacoes_livre_funil';

const etapa = (chave, name, query = {}, params = {}) => ({
  chave,
  name,
  query,
  params,
});

export const JORNADAS = [
  {
    chave: 'COMECAR',
    etapas: [
      etapa('VAZIA', LISTA, { vazio: '1' }),
      etapa('PORTAS', COMECAR),
      etapa('RECEITAS', RECEITAS),
      etapa('CONFIRA', NOVA, { receita: 'ORCAMENTO_PARADO' }),
      etapa('ENSAIAR', NOVA, { receita: 'ORCAMENTO_PARADO', aba: 'ensaiar' }),
      etapa('LIGAR', NOVA, { receita: 'ORCAMENTO_PARADO', ligar: '1' }),
      etapa('LISTA', LISTA),
    ],
  },
  {
    chave: 'RENOVACAO',
    etapas: [
      etapa('RECEITA', RECEITAS, { destaque: 'RENOVACAO' }),
      etapa('CONFIRA', EDITAR, {}, { id: '1' }),
      etapa('SELETOR', EDITAR, { seletor: 'raiz@3' }, { id: '1' }),
      etapa('ALTERAR', EDITAR, { alterar: 'r3' }, { id: '1' }),
      etapa('ENSAIAR', EDITAR, { aba: 'ensaiar', alvo: '201' }, { id: '1' }),
      etapa('LIGAR', EDITAR, { ligar: '1' }, { id: '1' }),
    ],
  },
  {
    chave: 'LEAD',
    etapas: [
      etapa('CONFIRA', EDITAR, {}, { id: '3' }),
      etapa('TUDO', EDITAR, { tudo: '1' }, { id: '3' }),
      etapa('DADO', EDITAR, { aba: 'dado' }, { id: '3' }),
      etapa('ENSAIAR', EDITAR, { aba: 'ensaiar', alvo: '301' }, { id: '3' }),
      etapa('LIGAR', EDITAR, { ligar: '1' }, { id: '3' }),
    ],
  },
  {
    chave: 'ORCAMENTO',
    etapas: [
      etapa('CONFIRA', EDITAR, {}, { id: '2' }),
      etapa('HISTORICO', EDITAR, { aba: 'historico' }, { id: '2' }),
      etapa('NO_MEIO', EDITAR, { pessoas: '1' }, { id: '2' }),
    ],
  },
  {
    chave: 'FUNIL',
    etapas: [
      etapa('FUNIL', FUNIL),
      etapa('ETAPA', FUNIL, { etapa: 'orcamento_enviado' }),
      etapa('NOVA', NOVA, { etapa: 'orcamento_enviado' }),
      etapa('ANTIGA', FUNIL, { etapa: 'negociacao' }),
      etapa('CARTAO', FUNIL, { cartao: '101' }),
    ],
  },
  {
    chave: 'GUIA',
    etapas: [
      etapa('CONTE', CONTE),
      etapa('MONTOU', CONTE, { montou: '1' }),
      etapa('CONFIRA', NOVA, { receita: 'ORCAMENTO_PARADO', guia: '1' }),
    ],
  },
  {
    chave: 'ANTIGA',
    etapas: [
      etapa('ABRIR', EDITAR, {}, { id: '4' }),
      etapa('TRAZER', EDITAR, { trazer: '1' }, { id: '4' }),
    ],
  },
];

// A etapa que bate com a URL atual (rota, parâmetros e query iguais).
const mesmoObjeto = (a = {}, b = {}) => {
  const chavesA = Object.keys(a);
  return (
    chavesA.length === Object.keys(b).length &&
    chavesA.every(chave => String(a[chave]) === String(b[chave]))
  );
};

export const etapaAtual = route =>
  JORNADAS.flatMap(jornada =>
    jornada.etapas.map(item => ({ jornada: jornada.chave, ...item }))
  ).find(
    item =>
      item.name === route.name &&
      mesmoObjeto(item.query, route.query) &&
      Object.keys(item.params).every(
        chave => String(route.params[chave]) === item.params[chave]
      )
  ) || null;
