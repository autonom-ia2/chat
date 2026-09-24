// Roteiro do vídeo de trajeto do artigo 02.03 — "Seu e-mail, sua senha e o
// login único". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/settings.json
// (PROFILE_SETTINGS.FORM.EMAIL / CURRENT_PASSWORD / PASSWORD /
// PASSWORD_CONFIRMATION / PASSWORD_SECTION).
//
// REGRA DO PEDIDO (P2): não troca a senha nem o e-mail — mostra até o
// formulário preenchido e NUNCA clica em "Mudar Senha" nem em
// "Atualizar o Perfil" depois de mexer no e-mail. Os valores digitados nos
// campos de senha são texto de exemplo, óbvios como tal
// ("senha-exemplo-..."), nunca uma senha real.
//
// Trajeto: Configurações do Perfil → veja Seu e-mail → role até Senha →
// preencha os três campos → aponte para Mudar Senha sem clicar.

export const id = '02.03';

export const login = {
  contaId: 9,
  usuarioNome: 'Duda Admin',
};

export const baseUrl = 'http://localhost:3000';

// Nada a preparar: só navega e preenche campos sem enviar o formulário.

export const cenas = [
  {
    legenda: 'Seu e-mail, sua senha e o login único',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2800,
  },
  {
    legenda: 'Abra Configurações do Perfil',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/profile/settings`,
    aguardarTexto: 'Seu nome completo',
    zoom: 1,
    duracaoMs: 1000,
  },
  {
    legenda: 'Seu e-mail fica aqui em cima',
    acao: 'parar',
    alvo: {
      seletor:
        'input[placeholder="Por favor, insira seu endereço de e-mail, que será exibido em conversas"]',
    },
    zoom: 1.6,
    duracaoMs: 1600,
  },
  {
    legenda: 'Role até a seção Senha',
    acao: 'parar',
    alvo: { texto: 'Senha atual' },
    zoom: 1.4,
    duracaoMs: 1600,
  },
  {
    legenda: 'Preencha Senha atual',
    acao: 'digitar',
    alvo: {
      seletor: 'input[placeholder="Por favor, digite a senha atual"]',
    },
    texto: ['senha-exemplo-atual'],
    zoom: 1.8,
  },
  {
    legenda: 'Preencha Nova senha',
    acao: 'digitar',
    alvo: {
      seletor: 'input[placeholder="Por favor, digite uma nova senha"]',
    },
    texto: ['senha-exemplo-nova'],
    zoom: 1.8,
  },
  {
    legenda: 'Confirme a nova senha',
    acao: 'digitar',
    alvo: {
      seletor: 'input[placeholder^="Por favor, digite sua nova senha"]',
    },
    texto: ['senha-exemplo-nova'],
    zoom: 1.8,
  },
  {
    legenda: 'A senha que vale é a do login único',
    acao: 'parar',
    alvo: { texto: 'Mudar Senha' },
    zoom: 1.6,
    duracaoMs: 1800,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 2400,
  },
];
