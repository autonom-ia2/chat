// Roteiro do vídeo de trajeto do artigo 09.01 — "Onde ficam os contatos e
// como ler a lista". Rótulos conferidos ao vivo no painel local (login
// Rafa Admin, conta 9) em 2026-09-23.
//
// Trajeto: barra lateral → Contatos → visão Ativo (vazia) → volta para Todos
// os Contatos → rodapé com a contagem → ordenação (Classificar por).

export const id = '09.01';

export const login = {
  contaId: 9,
  usuarioNome: 'Rafa Admin',
};

export const baseUrl = 'http://localhost:3000';

// Este vídeo só lê telas que já existem (contatos reais da conta de teste,
// mantidos por outros vídeos) — não precisa preparar nada antes de gravar.

export const cenas = [
  {
    legenda: 'Onde ficam os contatos',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 1500,
  },
  {
    legenda: 'Abra Contatos',
    acao: 'mover e clicar',
    alvo: { seletor: 'nav a[name="Contacts"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Abra a visão Ativo',
    acao: 'mover e clicar',
    alvo: { texto: 'Ativo' },
    zoom: 1.8,
  },
  {
    legenda: 'Ativo mostra só quem está online',
    acao: 'parar',
    alvo: { texto: 'Nenhum contato está ativo no momento 🌙' },
    zoom: 1.3,
    duracaoMs: 1800,
  },
  {
    legenda: 'Volte para Todos os Contatos',
    acao: 'mover e clicar',
    alvo: { texto: 'Todos os Contatos' },
    zoom: 1.8,
  },
  {
    legenda: 'Veja quantos contatos a lista tem',
    acao: 'parar',
    alvo: { seletor: 'main footer' },
    zoom: 1.6,
    duracaoMs: 1800,
  },
  {
    legenda: 'Clique no ícone de ordenação',
    acao: 'mover e clicar',
    alvo: { seletor: '.i-lucide-arrow-down-up' },
    zoom: 1.8,
  },
  {
    legenda: 'Escolha o campo em Classificar por',
    acao: 'parar',
    alvo: { texto: 'Classificar por' },
    zoom: 1.4,
    duracaoMs: 1800,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 1800,
  },
];
