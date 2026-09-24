// Roteiro do vídeo de trajeto do artigo 02.05 — "Como você escreve e como o
// painel aparece". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/settings.json
// (SEND_MESSAGE.CARD, INTERFACE_SECTION.FONT_SIZE, SIDEBAR_ITEMS.APPEARANCE)
// e generalSettings.json (COMMAND_BAR.COMMANDS.LIGHT_MODE).
//
// Escolhe "Claro" no tema (não "Escuro"): o motor grava sempre em tema claro
// — trocar para escuro de verdade quebraria essa regra para as cenas
// seguintes. Não clica no seletor de Idioma preferido (só mostra a seção):
// trocar o idioma de verdade mudaria o texto de toda a tela pro resto da
// gravação.
//
// Trajeto: Configurações do Perfil → Tecla de atalho (Cmd/Ctrl+Enter) →
// Idioma preferido (só mostrar) → Tamanho da fonte (Grande) → menu da foto →
// Alterar Tema → Claro.

export const id = '02.05';

export const login = {
  contaId: 9,
  usuarioNome: 'Duda Admin',
};

export const baseUrl = 'http://localhost:3000';

// Garante um ponto de partida limpo e sempre igual: tecla Enter, fonte
// Padrão, idioma da conta.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
usuaria = conta.users.find_by(name: ${JSON.stringify(login.usuarioNome)})
raise "usuária não encontrada" unless usuaria
config = (usuaria.ui_settings || {}).except("editor_message_key", "font_size", "locale")
usuaria.update!(ui_settings: config)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Como você escreve e como o painel aparece',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2800,
  },
  {
    legenda: 'Abra Configurações do Perfil',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/profile/settings`,
    aguardarTexto: 'Tecla de atalho para enviar mensagens',
    zoom: 1.2,
    duracaoMs: 1200,
  },
  {
    legenda: 'Escolha Cmd/Ctrl + Enter',
    acao: 'mover e clicar',
    alvo: { texto: 'Cmd/Ctrl + Enter (⌘ + ↵)' },
    pausaDepoisMs: 1400,
    zoom: 1.6,
  },
  {
    legenda: 'Vá até Idioma preferido',
    acao: 'parar',
    alvo: { texto: 'Idioma preferido', blocoRolagem: 'start' },
    zoom: 1.4,
    duracaoMs: 1400,
  },
  {
    legenda: 'Abra o Tamanho da fonte',
    acao: 'mover e clicar',
    alvo: { seletor: '[aria-label="Tamanho da fonte"]' },
    zoom: 1.6,
  },
  {
    legenda: 'Escolha Grande',
    acao: 'mover e clicar',
    alvo: { texto: 'Grande' },
    zoom: 1.6,
  },
  {
    legenda: 'A tela muda na hora',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 1400,
  },
  {
    legenda: 'Clique na sua foto',
    acao: 'mover e clicar',
    alvo: { seletor: '.border-t.border-n-weak button' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Alterar Tema',
    acao: 'mover e clicar',
    alvo: { texto: 'Alterar Tema' },
    zoom: 1.8,
  },
  {
    // PRECISA DE MOTOR: a busca do ninja-keys roda em Shadow DOM
    // (@chatwoot/ninja-keys usa attachShadow) — window.__gravacao.achar
    // percorre só a árvore normal do documento
    // (document.querySelectorAll('*')), então não enxerga nem "Claro" nem
    // qualquer outro texto dentro da paleta pra clicar. Visualmente a
    // paleta aparece na gravação (Shadow DOM não afeta o que a tela
    // desenha) — o vídeo termina aqui, mostrando-a aberta, sem clicar.
    legenda: 'Escolha Claro, Escuro ou Sistema',
    acao: 'parar',
    zoom: 1.4,
    duracaoMs: 2200,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 2200,
  },
];
