// #2226 v2 — a cor de cada série do painel de desempenho. A mesma série tem a mesma cor em todo lugar
// (KPI, legenda, linha do gráfico, faixa de evento, ranking, tabela) e também no PDF e no Excel.
// As classes ficam escritas por extenso (o Tailwind lê o arquivo como texto e não enxerga classe
// montada); nada de hex fixo.
export const COR = {
  volume: {
    fundo: 'bg-n-blue-9',
    fundoSuave: 'bg-n-blue-3',
    texto: 'text-n-blue-11',
    fill: 'fill-n-blue-9',
    stroke: 'stroke-n-blue-9',
    trilho: 'fill-n-blue-3',
    borda: 'border-n-blue-9',
  },
  preparo: {
    fundo: 'bg-n-violet-9',
    fundoSuave: 'bg-n-violet-3',
    texto: 'text-n-violet-11',
    fill: 'fill-n-violet-9',
    stroke: 'stroke-n-violet-9',
    trilho: 'fill-n-violet-3',
    borda: 'border-n-violet-9',
  },
  resultado: {
    fundo: 'bg-n-teal-9',
    fundoSuave: 'bg-n-teal-3',
    texto: 'text-n-teal-11',
    fill: 'fill-n-teal-9',
    stroke: 'stroke-n-teal-9',
    trilho: 'fill-n-teal-3',
    borda: 'border-n-teal-9',
  },
  alerta: {
    fundo: 'bg-n-ruby-9',
    fundoSuave: 'bg-n-ruby-3',
    texto: 'text-n-ruby-11',
    fill: 'fill-n-ruby-9',
    stroke: 'stroke-n-ruby-9',
    trilho: 'fill-n-ruby-3',
    borda: 'border-n-ruby-9',
  },
  tempo: {
    fundo: 'bg-n-amber-9',
    fundoSuave: 'bg-n-amber-3',
    texto: 'text-n-amber-11',
    fill: 'fill-n-amber-9',
    stroke: 'stroke-n-amber-9',
    trilho: 'fill-n-amber-3',
    borda: 'border-n-amber-9',
  },
  neutro: {
    fundo: 'bg-n-slate-9',
    fundoSuave: 'bg-n-slate-3',
    texto: 'text-n-slate-11',
    fill: 'fill-n-slate-9',
    stroke: 'stroke-n-slate-9',
    trilho: 'fill-n-slate-3',
    borda: 'border-n-slate-9',
  },
  // Séries só dos números do topo e das etapas do funil, para cada número ter a sua cor.
  duvidas: {
    fundo: 'bg-n-iris-9',
    fundoSuave: 'bg-n-iris-3',
    texto: 'text-n-iris-11',
    fill: 'fill-n-iris-9',
    stroke: 'stroke-n-iris-9',
    trilho: 'fill-n-iris-3',
    borda: 'border-n-iris-9',
  },
  perda: {
    fundo: 'bg-n-amber-9',
    fundoSuave: 'bg-n-amber-3',
    texto: 'text-n-amber-11',
    fill: 'fill-n-amber-9',
    stroke: 'stroke-n-amber-9',
    trilho: 'fill-n-amber-3',
    borda: 'border-n-amber-9',
  },
  demora: {
    fundo: 'bg-n-gray-9',
    fundoSuave: 'bg-n-gray-3',
    texto: 'text-n-gray-11',
    fill: 'fill-n-gray-9',
    stroke: 'stroke-n-gray-9',
    trilho: 'fill-n-gray-3',
    borda: 'border-n-gray-9',
  },
};

export const SERIES = Object.keys(COR);

// Uma série que não existe cai no neutro: cor nunca some, e nunca vira classe quebrada.
export const corDe = nome => COR[nome] || COR.neutro;

// Cada número do topo com a sua cor (a referência dá uma cor por marco). A cor que vem nos dados
// (`kpi.cor`) vale só para id que não está aqui. Fecharam e Ficaram sem pessoa usam as mesmas séries
// do gráfico de movimento (resultado e alerta).
export const SERIE_DO_KPI = {
  procuras: 'volume',
  conversas: 'neutro',
  compra: 'preparo',
  fecharam: 'resultado',
  duvidas_resolvidas: 'duvidas',
  sem_pessoa: 'alerta',
  perdas_evitaveis: 'perda',
  tempo_resposta: 'demora',
};
export const serieDoKpi = kpi => SERIE_DO_KPI[kpi?.id] || kpi?.cor || 'neutro';

// Uma cor por etapa do funil, na ordem: o começo em azul, o meio em violeta, âmbar e cinza, e a
// última (o resultado) sempre em verde-azulado.
const SERIES_DAS_ETAPAS = ['volume', 'duvidas', 'preparo', 'perda', 'demora'];
export const serieDaEtapa = (indice, total) =>
  indice === total - 1
    ? 'resultado'
    : SERIES_DAS_ETAPAS[Math.min(indice, SERIES_DAS_ETAPAS.length - 1)];

// Grupo do resultado (catálogo) → série.
export const COR_DO_GRUPO = {
  fechou: 'resultado',
  avancou: 'preparo',
  parou: 'alerta',
  resolveu: 'resultado',
  passou: 'tempo',
  sem_negocio: 'neutro',
};

// Frente da recomendação ("Do sinal à ação") → série.
export const COR_DA_FRENTE = {
  instrucao: 'volume',
  sistema: 'preparo',
  equipe: 'tempo',
  anuncio: 'resultado',
};

// Qualidade do agente (os 4 valores universais) → série.
export const COR_DA_QUALIDADE = {
  acertou: 'resultado',
  erro_leve: 'tempo',
  erro_grave: 'alerta',
  nao_atuou: 'neutro',
};

// Borda superior de 3px por série (cartões do funil, das ações e da origem).
export const BORDA_DE_CIMA = {
  volume: 'border-t-[3px] border-n-blue-9',
  preparo: 'border-t-[3px] border-n-violet-9',
  resultado: 'border-t-[3px] border-n-teal-9',
  alerta: 'border-t-[3px] border-n-ruby-9',
  tempo: 'border-t-[3px] border-n-amber-9',
  neutro: 'border-t-[3px] border-n-slate-9',
  duvidas: 'border-t-[3px] border-n-iris-9',
  perda: 'border-t-[3px] border-n-amber-9',
  demora: 'border-t-[3px] border-n-gray-9',
};

// Mapa de calor: 6 degraus. Zero tem tom próprio; os outros 5 sobem com a fração do máximo. No escuro
// os 2 primeiros degraus sobem um tom, para não sumirem contra a célula vazia.
export const TONS_DO_MAPA = [
  'bg-n-slate-2 text-n-slate-9',
  'bg-n-blue-3 dark:bg-n-blue-5 text-n-blue-11',
  'bg-n-blue-5 dark:bg-n-blue-7 text-n-blue-12',
  'bg-n-blue-7 dark:bg-n-blue-8 text-n-blue-12',
  'bg-n-blue-9 text-white',
  'bg-n-blue-11 text-white dark:text-n-slate-1',
];

// O mesmo mapa em tom de alerta (quem ficou sem uma pessoa da equipe).
export const TONS_DO_MAPA_ALERTA = [
  'bg-n-slate-2 text-n-slate-9',
  'bg-n-ruby-3 dark:bg-n-ruby-5 text-n-ruby-11',
  'bg-n-ruby-5 dark:bg-n-ruby-7 text-n-ruby-12',
  'bg-n-ruby-7 dark:bg-n-ruby-8 text-n-ruby-12',
  'bg-n-ruby-9 text-white',
  'bg-n-ruby-11 text-white dark:text-n-slate-1',
];

export const degrauDoMapa = (valor, maximo) => {
  if (!valor || !maximo) return 0;
  const fracao = Math.min(1, Math.max(0, valor / maximo));
  return Math.max(1, Math.ceil(fracao * (TONS_DO_MAPA.length - 1)));
};

export const tonsDoMapa = tom =>
  tom === 'alerta' ? TONS_DO_MAPA_ALERTA : TONS_DO_MAPA;

export const tomDoMapa = (valor, maximo, tom = 'volume') =>
  tonsDoMapa(tom)[degrauDoMapa(valor, maximo)];
