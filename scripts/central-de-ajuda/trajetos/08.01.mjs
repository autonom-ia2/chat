// Roteiro do vídeo de trajeto do artigo 08.01 — "Abrir a tela de Conversas:
// áreas, cards e layout". Seletores conferidos direto no DOM renderizado
// (login manual de exploração) e no código-fonte:
// app/javascript/dashboard/components-next/Conversation/SidepanelSwitch.vue
// (ícone i-ph-user-bold do botão Contatos) e
// app/javascript/dashboard/routes/dashboard/conversation/search/SwitchLayout.vue
// (ícone i-lucide-arrow-right-to-line do botão de trocar layout).
//
// Trajeto: tela de Conversas → clique num card → abre a conversa → clique em
// Contatos → abre o painel lateral → clique no botão de setas → troca o
// layout da lista.

export const id = '08.01';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3000';

// Roda antes de gravar (não entra no vídeo). Garante que o painel de
// contato comece fechado e a lista comece no layout estreito (padrão), para
// os dois cliques do vídeo terem efeito visível.
export async function preparar({ rodarRails }) {
  await rodarRails(`
usuaria = Account.find(${login.contaId}).users.find_by(name: ${JSON.stringify(login.usuarioNome)})
raise "usuária não encontrada" unless usuaria
config = (usuaria.ui_settings || {}).merge(
  "is_contact_sidebar_open" => false,
  "is_copilot_panel_open" => false,
  "is_autonomia_copilot_panel_open" => false,
  "conversation_display_type" => "condensed"
)
usuaria.update!(ui_settings: config)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Abrir a tela de Conversas',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
  {
    // A aba "Minhas" começa vazia (Lia Admin não tem conversa atribuída
    // nesta conta de teste) — clicar em "Todos" é o que revela a lista de
    // cards, e as abas fazem parte do "layout" que o artigo descreve.
    legenda: 'Clique na aba Todos',
    acao: 'mover e clicar',
    alvo: { seletor: 'li:last-child > a.text-button' },
    zoom: 1.5,
  },
  {
    legenda: 'Clique em um card da lista',
    acao: 'mover e clicar',
    alvo: { seletor: '.conversation' },
    zoom: 1.6,
  },
  {
    legenda: 'Veja a conversa no meio da tela',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 1400,
  },
  {
    legenda: 'Clique no botão Contatos',
    acao: 'mover e clicar',
    alvo: { seletor: '.i-ph-user-bold' },
    zoom: 1.8,
  },
  {
    legenda: 'Veja os dados do contato',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 1400,
  },
  {
    legenda: 'Clique no botão de setas',
    acao: 'mover e clicar',
    alvo: { seletor: '.i-lucide-arrow-right-to-line' },
    zoom: 1.6,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
