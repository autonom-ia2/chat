// Roteiro do vídeo de trajeto do artigo 01.07 — "Como usar a Central de
// Ajuda". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/helpCenter.json
// (HELP_CENTER.CENTRAL_DE_AJUDA), na tela nova do #977.
//
// Trajeto: menu lateral → Central de Ajuda → busca ("conectar o WhatsApp")
// → Por assunto → página do assunto Conversas e chamadas → abrir um artigo
// → Me leve até lá.

export const id = '01.07';

export const login = {
  contaId: 9,
  usuarioNome: 'Rita Admin',
};

export const baseUrl = 'http://localhost:3000';

// Nada a preparar: só navega e lê, não cria nem muda nada.

export const cenas = [
  {
    legenda: 'Como usar a Central de Ajuda',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
  },
  {
    legenda: 'Abra Central de Ajuda no menu lateral',
    acao: 'mover e clicar',
    alvo: { texto: 'Central de Ajuda' },
    // 'O que você quer fazer?' é só o placeholder do campo de busca —
    // texto de placeholder não entra em document.body.innerText. Espera
    // por 'Por assunto', que é texto de verdade na tela inicial.
    aguardarTextoDepois: 'Por assunto',
    zoom: 1.2,
  },
  {
    legenda: 'Escreva o que você quer fazer',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="O que você quer fazer?"]' },
    texto: ['conectar o WhatsApp'],
    zoom: 1.6,
  },
  {
    legenda: 'Os artigos aparecem enquanto digita',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 1800,
  },
  {
    // Limpar o campo é o que volta para a tela inicial: o caminho já está em
    // /central-de-ajuda, e um "ir para" a mesma rota não remonta a tela.
    legenda: 'Ou escolha um assunto em Por assunto',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="O que você quer fazer?"]' },
    limparAntes: true,
    texto: [],
    zoom: 1.1,
  },
  {
    legenda: 'Abra o assunto',
    acao: 'mover e clicar',
    alvo: { texto: 'Conversas e chamadas' },
    aguardarTextoDepois: 'Artigos deste assunto',
    zoom: 1.3,
  },
  {
    legenda: 'Cada artigo tem um vídeo curto; os que você já viu ficam marcados',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 2400,
  },
  {
    legenda: 'Abra o artigo',
    acao: 'mover e clicar',
    alvo: {
      texto:
        'Escolher a fila certa: Minhas, Não atribuídas, Todos e Não atendidas',
    },
    aguardarTextoDepois: 'Me leve até lá',
    zoom: 1.4,
  },
  {
    legenda: 'Clique em Me leve até lá',
    acao: 'mover e clicar',
    alvo: { texto: 'Me leve até lá' },
    zoom: 1.6,
  },
  {
    legenda: 'A tela certa abre, com o botão em destaque',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 1800,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 2200,
  },
];
