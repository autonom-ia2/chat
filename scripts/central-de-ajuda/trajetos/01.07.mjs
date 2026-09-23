// Roteiro do vídeo de trajeto do artigo 01.07 — "Como usar a Central de
// Ajuda". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/helpCenter.json
// (HELP_CENTER.CENTRAL_DE_AJUDA).
//
// Trajeto: menu lateral → Central de Ajuda → busca ("conectar o WhatsApp")
// → Comece por aqui → abrir um artigo → Me leve até lá.

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
    // por 'Comece por aqui', que é texto de verdade na tela inicial.
    aguardarTextoDepois: 'Comece por aqui',
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
    // Limpa a busca em vez de navegar: o caminho já está em
    // /central-de-ajuda, então um "ir para" para a mesma rota não recarrega
    // nada (Vue Router não remonta) e a tela ficava presa nos resultados
    // da busca anterior. Limpar o campo é o que de fato volta para "Comece
    // por aqui".
    legenda: 'Ou comece por Comece por aqui',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="O que você quer fazer?"]' },
    limparAntes: true,
    texto: [],
    zoom: 1.2,
  },
  {
    legenda: 'Abra o artigo',
    acao: 'mover e clicar',
    alvo: { texto: 'Seu primeiro acesso e a tela Primeiros passos' },
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
