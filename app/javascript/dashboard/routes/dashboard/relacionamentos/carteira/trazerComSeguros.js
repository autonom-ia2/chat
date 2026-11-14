// #2897 — tudo o que "Trazer minha lista" ganha na conta que tem a carteira de
// seguros, num módulo só: a fonte com os seguros por cima, quem decide quando a
// tela é a da carteira e as telas dela. A página o baixa à parte, e só nessa
// conta (pages/TrazerPage.vue): quem não tem a carteira não recebe este código.
export { trazerSegurosFonte } from '../fonte/trazerSegurosFonte';
export { useTrazerSeguros } from './useTrazerSeguros';
export { default as TrazerSeguros } from '../components/carteira/trazer/TrazerSeguros.vue';

// #2899 (E6.4) — "Trazer por PDFs", na conta que lê PDF: a tela e quem diz se
// a conta lê (o resumo da carteira, `leituraDePdf`). A demonstração não lê.
export { default as TrazerPdfs } from '../components/carteira/trazer/pdfs/TrazerPdfs.vue';
export { default as ComoTrazer } from '../components/carteira/trazer/pdfs/ComoTrazer.vue';
export { leituraDePdf } from './leituraDePdf';
