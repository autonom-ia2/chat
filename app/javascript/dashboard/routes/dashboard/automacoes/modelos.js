// #859 — os três modelos prontos da tela vazia. O texto (título, explicação e o
// pedido que vai para o Guia) mora no i18n, em AUTOMACOES.MODELOS.<chave>.
export const MODELOS = [
  { chave: 'SINISTRO', icone: 'i-lucide-shield-alert' },
  { chave: 'BOAS_VINDAS', icone: 'i-lucide-hand' },
  { chave: 'AGRADECER', icone: 'i-lucide-heart-handshake' },
];

export const modeloExiste = chave =>
  MODELOS.some(modelo => modelo.chave === chave);
