// #2692 — as faixas de chance da tela nova. As fronteiras são as do motor de hoje
// (prospectingPriority.js: 50 e 25), sem backend novo; "muito quente" e "quente"
// viram uma faixa só, "Boa chance". O 1º da lista ganha "Chame primeiro".
export const CHANCES = ['boa', 'media', 'pouca'];

const BOA = 50;
const MEDIA = 25;

export const chanceDe = prioridade => {
  if (prioridade === null || prioridade === undefined) return 'pouca';
  if (prioridade >= BOA) return 'boa';
  if (prioridade >= MEDIA) return 'media';
  return 'pouca';
};

const SELOS = {
  primeiro: {
    chave: 'PROSPECTING_ACHAR.CHANCE.PRIMEIRO',
    classe: 'bg-n-teal-3 text-n-teal-11',
    ponto: 'bg-n-teal-9',
  },
  boa: {
    chave: 'PROSPECTING_ACHAR.CHANCE.BOA',
    classe: 'bg-n-blue-3 text-n-blue-11',
    ponto: 'bg-n-blue-9',
  },
  media: {
    chave: 'PROSPECTING_ACHAR.CHANCE.MEDIA',
    classe: 'bg-n-amber-3 text-n-amber-11',
    ponto: 'bg-n-amber-9',
  },
  pouca: {
    chave: 'PROSPECTING_ACHAR.CHANCE.POUCA',
    classe: 'bg-n-slate-3 text-n-slate-11',
    ponto: 'bg-n-slate-8',
  },
};

export const seloDe = (chance, primeiro = false) =>
  primeiro ? SELOS.primeiro : SELOS[chance] || SELOS.pouca;
