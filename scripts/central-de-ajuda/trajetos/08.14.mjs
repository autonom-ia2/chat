// Roteiro do vídeo de trajeto do artigo 08.14 — "Referência: limites por
// canal e atalhos de teclado". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/settings.json
// (SIDEBAR_ITEMS.KEYBOARD_SHORTCUTS, KEYBOARD_SHORTCUTS.TITLE.*) e em
// app/javascript/dashboard/components/widgets/modal/{constants,WootKeyShortcutModal.vue}.js.
//
// O artigo tem duas tabelas: limite de caracteres por canal (não tem tela
// própria no produto — é só consulta, o texto do artigo cobre) e atalhos de
// teclado (tem tela: a janela "Atalhos do teclado", aberta pelo menu da
// foto). O vídeo mostra só o que existe na tela: essa janela, com 3 dos
// atalhos que o artigo cita — Abrir conversa (Alt+J/Alt+K), Resolver
// Conversa (Alt+E) e Ir para Configurações (Alt+S) — nas mesmas palavras do
// artigo e da tela (SHORTCUT_KEYS em constants.js, 14 atalhos, cabem sem
// rolar dentro da janela "medium").
//
// Trajeto: foto no rodapé da barra lateral → Atalhos do teclado → janela
// com a lista.

export const id = '08.14';

export const login = {
  contaId: 9,
  usuarioNome: 'Rita Admin',
};

export const baseUrl = 'http://localhost:3000';

// Nada a preparar: janela de atalhos é estática (SHORTCUT_KEYS é uma
// constante do front, não dado de conta), e o vídeo não muda nada.

export const cenas = [
  {
    legenda: 'Ver os atalhos do teclado',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2800,
  },
  {
    legenda: 'Clique na sua foto',
    acao: 'mover e clicar',
    alvo: { seletor: '.border-t.border-n-weak button' },
    zoom: 1.8,
  },
  {
    legenda: 'Abra Atalhos do teclado',
    acao: 'mover e clicar',
    alvo: { texto: 'Atalhos do teclado' },
    aguardarTextoDepois: 'Abrir conversa',
    zoom: 1.8,
  },
  {
    legenda: 'Abra a conversa com Alt+J',
    acao: 'parar',
    alvo: { texto: 'Abrir conversa' },
    zoom: 1.6,
    duracaoMs: 2400,
  },
  {
    legenda: 'Resolva a conversa com Alt+E',
    acao: 'parar',
    alvo: { texto: 'Resolver Conversa' },
    zoom: 1.6,
    duracaoMs: 2400,
  },
  {
    legenda: 'Vá para Configurações com Alt+S',
    acao: 'parar',
    alvo: { texto: 'Ir para Configurações' },
    zoom: 1.6,
    duracaoMs: 2400,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 2600,
  },
];
