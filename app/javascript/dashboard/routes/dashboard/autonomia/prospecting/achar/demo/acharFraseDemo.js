// O que a IA da conta devolve para a frase, no formato do servidor
// (searches/interpret), na demonstração.
export const FRASE_ENTENDIDA = {
  status: 'understood',
  what: 'Padarias',
  where: 'centro',
  advanced_filters: { rating_min: '4', has_website: 'yes' },
  score_mode: 'general',
  left_out: 'Não dá para escolher pelo horário que abre.',
};
export const FRASE_NAO_ENTENDIDA = {
  status: 'not_understood',
  what: null,
  where: null,
  advanced_filters: {},
  score_mode: 'general',
  left_out: null,
};
