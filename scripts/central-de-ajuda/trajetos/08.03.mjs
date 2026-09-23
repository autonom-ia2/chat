// Roteiro do vídeo de trajeto do artigo 08.03 — "Filtrar, ordenar e ver por
// canal, time ou etiqueta". Seletores conferidos no código-fonte:
// - ícone de ordenar: `.i-lucide-arrow-up-down`
//   (app/javascript/dashboard/components/widgets/conversation/ConversationBasicFilter.vue:149).
//   A barra lateral usa o MESMO ícone nos cabeçalhos de "Times"/"Canais"/
//   "Etiquetas" (ordenar aquelas listas) e vem antes no DOM — `querySelector`
//   pegaria o ícone errado. O alvo por isso ancora no botão de filtro
//   avançado (`#toggleConversationFilterButton`, ícone de funil, também em
//   ChatListHeader.vue), que fica imediatamente antes do ConversationBasicFilter
//   na mesma barra.
// - canal na barra lateral: o texto do link vem com o total de não lidas
//   colado (mesmo padrão de 08.02), por isso o alvo usa o href da rota do
//   inbox (`/app/accounts/9/inbox/7` = WhatsApp Comercial), estável.
//
// O painel de Status/Ordenar abre outro seletor aninhado (mostra o valor
// atual, ex. "Abertas") cujo texto colide com o rótulo que já fica fixo no
// topo da lista ("Conversas Abertas") — para não depender de um seletor
// frágil ali dentro, o vídeo mostra o painel aberto (cumpre "clique no
// ícone de setas") e deixa a escolha de cada opção só no texto do artigo.

export const id = '08.03';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3000';

export const cenas = [
  {
    legenda: 'Filtrar e ordenar as conversas',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2700,
  },
  {
    legenda: 'Clique no ícone de setas',
    acao: 'mover e clicar',
    alvo: {
      seletor:
        'div:has(> #toggleConversationFilterButton) + div .i-lucide-arrow-up-down',
    },
    zoom: 1.8,
  },
  {
    legenda: 'Escolha Status e Ordenar por',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 2800,
  },
  {
    legenda: 'Clique no item que você quer ver',
    acao: 'mover e clicar',
    alvo: { seletor: 'a[href="/app/accounts/9/inbox/7"]' },
    zoom: 1.6,
  },
  {
    legenda: 'O título muda para o nome',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 2200,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2700,
  },
];
