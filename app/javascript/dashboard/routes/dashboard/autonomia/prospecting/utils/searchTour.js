// Passos do tour guiado da busca (#682, ACAO-40 a 43), na ordem do BuscaTour
// do Orth. target é o data-tour do bloco destacado; needsForm abre o
// formulário de nova busca; waitFor segura o Próximo até a tela chegar lá
// ('location': local confirmado; 'results': busca terminada com leads).
// O texto de cada passo sai de PROSPECTING.TOUR.STEPS.<key>; os campos com
// sufixo _GBP/_GENERAL mudam com o modo de nota.

export const SEARCH_TOUR_SEEN_KEY = 'prospecting_search_tour_seen_at';
export const SEARCH_TOUR_AUTO_FINISH_MS = 3500;
export const SEARCH_TOUR_EXAMPLE_RADIUS_KM = 3;

export const SEARCH_TOUR_STEPS = [
  { key: 'WELCOME', target: null, byMode: ['BODY'] },
  { key: 'MODE', target: 'search-mode', byMode: ['TITLE', 'BODY'] },
  {
    key: 'PRESETS',
    target: 'search-presets',
    needsForm: true,
    byMode: ['BODY'],
  },
  {
    key: 'WHERE',
    target: 'search-where',
    needsForm: true,
    prefill: true,
    waitFor: 'location',
    byMode: [],
  },
  {
    key: 'DECISION_MAKER',
    target: 'search-decision-maker',
    needsForm: true,
    byMode: [],
  },
  {
    key: 'FILTERS',
    target: null,
    needsForm: true,
    openFilters: true,
    byMode: ['BODY'],
  },
  {
    key: 'SUBMIT',
    target: 'search-submit',
    needsForm: true,
    waitFor: 'results',
    byMode: [],
  },
  {
    key: 'RESULTS',
    target: 'search-results',
    autoFinishMs: SEARCH_TOUR_AUTO_FINISH_MS,
    byMode: ['BODY'],
  },
];

const modeSuffix = scoreMode => (scoreMode === 'gbp' ? 'GBP' : 'GENERAL');

// Chave de i18n de um campo (EYEBROW, TITLE, BODY) do passo no modo dado.
export const searchTourTextKey = (step, field, scoreMode) => {
  const base = `PROSPECTING.TOUR.STEPS.${step.key}.${field}`;
  return step.byMode.includes(field)
    ? `${base}_${modeSuffix(scoreMode)}`
    : base;
};
