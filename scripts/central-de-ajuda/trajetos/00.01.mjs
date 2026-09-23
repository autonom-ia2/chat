// Roteiro do vídeo de trajeto do artigo 00.01 — "Seu primeiro acesso e a tela
// Primeiros passos". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/{settings,onboardingTrail}.json.
//
// Trajeto: menu lateral → Primeiros passos → leia o passo em destaque →
// Fazer agora (abre a tela daquele passo).

export const id = '00.01';

export const login = {
  contaId: 9,
  usuarioNome: 'Rita Admin',
};

export const baseUrl = 'http://localhost:3000';

// Nada a preparar: a lista de passos reflete o estado real da conta, que é
// exatamente o que o artigo mostra (o passo pendente em foco). Este vídeo
// não cria nem apaga nada.

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
    legenda: 'Veja a lista dos passos',
    acao: 'parar',
    alvo: { seletor: 'h1' },
    zoom: 1.3,
    duracaoMs: 2200,
  },
  {
    legenda: 'Leia o passo em destaque',
    acao: 'parar',
    alvo: { texto: 'Fazer agora', blocoRolagem: 'center' },
    zoom: 1.4,
    duracaoMs: 2200,
  },
  {
    // Não navega: o destino de "Fazer agora" varia com o passo em foco (é a
    // tela de outro artigo, não deste). Este vídeo mostra o caminho até o
    // botão, sem sair da própria tela de Primeiros passos.
    legenda: 'Fazer agora abre a tela do passo',
    acao: 'passar o mouse',
    alvo: { texto: 'Fazer agora' },
    zoom: 1.6,
    duracaoMs: 2400,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 3000,
  },
];
