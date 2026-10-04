// #859/#982 — as automações prontas da tela de Automações. O texto (título,
// explicação, as linhas Quando/Faz e o pedido que vai para o Guia) mora no i18n,
// em AUTOMACOES.MODELOS.<chave>. As classes de cor ficam escritas por inteiro
// aqui para o Tailwind encontrá-las.
export const MODELOS = [
  {
    chave: 'AGRADECER',
    icone: 'i-lucide-heart-handshake',
    tom: 'bg-n-ruby-3 text-n-ruby-11',
  },
  {
    chave: 'BOAS_VINDAS',
    icone: 'i-lucide-message-circle-heart',
    tom: 'bg-n-blue-3 text-n-blue-11',
  },
  {
    chave: 'SINISTRO',
    icone: 'i-lucide-shield-alert',
    tom: 'bg-n-amber-3 text-n-amber-11',
  },
  {
    chave: 'COTACAO',
    icone: 'i-lucide-tag',
    tom: 'bg-n-teal-3 text-n-teal-11',
  },
  {
    chave: 'DIVIDIR_LEADS',
    icone: 'i-lucide-users-round',
    tom: 'bg-n-violet-3 text-n-violet-11',
  },
  {
    chave: 'FORA_DO_HORARIO',
    icone: 'i-lucide-moon-star',
    tom: 'bg-n-slate-3 text-n-slate-11',
  },
];

export const modeloExiste = chave =>
  MODELOS.some(modelo => modelo.chave === chave);
