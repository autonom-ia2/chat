// Roteiro do vídeo de trajeto do artigo 00.01 — "Seu primeiro acesso e a tela
// Primeiros passos". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/{settings,onboardingTrail}.json.
//
// Trajeto: menu lateral → Primeiros passos → o painel "Seu próximo passo" →
// o botão azul do passo (abre a tela daquele passo) → a lista por etapa.

export const id = '00.01';

export const login = {
  contaId: 9,
  usuarioNome: 'Rita Admin',
};

export const baseUrl = 'http://localhost:3000';

// Nada a preparar: o painel e a lista refletem o estado real da conta, que é
// exatamente o que o artigo mostra (o primeiro passo pendente no painel). Este
// vídeo não cria nem apaga nada.

export const cenas = [
  {
    legenda: 'Ver seus primeiros passos',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 3000,
  },
  {
    legenda: 'Abra Primeiros passos no menu lateral',
    acao: 'mover e clicar',
    alvo: { texto: 'Primeiros passos' },
    zoom: 1.8,
  },
  {
    legenda: 'Veja quanto falta e as três etapas',
    acao: 'parar',
    alvo: { seletor: 'h1' },
    zoom: 1.3,
    duracaoMs: 2400,
  },
  {
    legenda: 'Comece pelo seu próximo passo',
    acao: 'parar',
    // O selo diz "Seu próximo passo · N de 9"; o título do passo no painel é o
    // alvo estável.
    alvo: { seletor: 'article h2', blocoRolagem: 'center' },
    zoom: 1.4,
    duracaoMs: 2400,
  },
  {
    // Não navega: o texto e o destino do botão mudam com o passo do painel (é
    // a tela de outro artigo, não deste). Por isso o alvo é o primeiro botão do
    // painel, não um rótulo fixo.
    legenda: 'O botão azul abre a tela do passo',
    acao: 'passar o mouse',
    alvo: { seletor: 'article button' },
    zoom: 1.6,
    duracaoMs: 2600,
  },
  {
    legenda: 'Os outros passos ficam na lista, por etapa',
    acao: 'parar',
    alvo: { texto: 'Montar o primeiro funil', blocoRolagem: 'center' },
    zoom: 1.3,
    duracaoMs: 2600,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 3000,
  },
];
