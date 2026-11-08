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
// A frase que só diz o quê e o onde, sem ajuste nem ordem: o que a pessoa
// escolheu à mão antes fica.
export const FRASE_SEM_AJUSTE = {
  ...FRASE_ENTENDIDA,
  advanced_filters: {},
  left_out: null,
};

// A frase que não diz o lugar: "Onde?" fica com o que já estava escrito.
export const FRASE_SEM_ONDE = { ...FRASE_ENTENDIDA, where: null };

// Qual resposta cada estado da demonstração devolve; os outros, a entendida.
export const FRASE_POR_ESTADO = {
  'porta-frase-nao-entendeu': FRASE_NAO_ENTENDIDA,
  'porta-frase-ajuste-manual': FRASE_SEM_AJUSTE,
  'porta-frase-sem-onde': FRASE_SEM_ONDE,
};

// Os estados da porta do pedido em uma frase, sobre o preenchimento padrão.
// O campo aparece em todos os estados da porta, menos sem a IA da conta.
export const PORTA_DA_FRASE = padrao => ({
  'porta-sem-ia': padrao,
  'porta-frase-erro': padrao,
  'porta-frase-sem-ia': padrao,
  'porta-frase-nao-entendeu': padrao,
  'porta-frase-uma-sugestao': padrao,
  'porta-frase-sem-onde': { oQue: 'Escritórios', ondeTexto: 'centro' },
  'porta-frase-ajuste-manual': {
    ...padrao,
    primeiro: 'pouco',
    ajustes: { nota: 'n45' },
  },
});
