// Roteiro do vídeo de trajeto do artigo 02.01 — "Onde ficam suas
// configurações pessoais". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/settings.json e no roteiro
// modelo trajetos/02.04.mjs (mesmo menu da foto).
//
// Trajeto: foto no rodapé da barra lateral → menu (Disponibilidade, Marcar
// offline automaticamente, atalhos, Configurações do Perfil) →
// Configurações do Perfil.

export const id = '02.01';

export const login = {
  contaId: 9,
  usuarioNome: 'Rita Admin',
};

export const baseUrl = 'http://localhost:3000';

// Nada a preparar: só navega e olha, não muda nada.

export const cenas = [
  {
    legenda: 'Onde ficam suas configurações pessoais',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 3000,
  },
  {
    legenda: 'Clique na sua foto',
    acao: 'mover e clicar',
    alvo: { seletor: '.border-t.border-n-weak button' },
    zoom: 1.8,
  },
  {
    legenda: 'Veja Disponibilidade e o menu',
    acao: 'parar',
    alvo: { texto: 'Disponibilidade' },
    zoom: 1.6,
    duracaoMs: 1800,
  },
  {
    legenda: 'Clique em Configurações do Perfil',
    acao: 'mover e clicar',
    alvo: { texto: 'Configurações do Perfil' },
    aguardarTextoDepois: 'Seu nome completo',
    zoom: 1.8,
  },
  {
    legenda: 'Aqui ficam seus dados pessoais',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 2200,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 2800,
  },
];
