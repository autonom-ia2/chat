// Roteiro do vídeo de trajeto do artigo 02.08 — "Referência: token de
// acesso, atalhos e sair com segurança". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/settings.json
// (PROFILE_SETTINGS.FORM.ACCESS_TOKEN.*) e no componente
// app/javascript/dashboard/routes/dashboard/settings/profile/AccessToken.vue.
//
// Trajeto: foto no rodapé da barra lateral → Configurações do Perfil →
// rolar até Token de acesso → ver o campo escondido → Copiar. Este é o
// "me_leve_ate_la" do artigo (rota profile_settings_index, destaque
// profile-copy-access-token) — o vídeo cobre só esse trecho de referência;
// os outros dois (Atalhos do teclado, Encerrar sessão) o texto do artigo já
// cobre, e Atalhos do teclado tem vídeo próprio no artigo 08.14.
//
// CUIDADO DO PEDIDO (P3): o valor do token nunca aparece legível. O campo
// nasce como <input type="password"> em AccessToken.vue (inputType inicial
// = 'password') — o vídeo NUNCA clica no ícone de olho (que alterna pra
// type="text"), só mostra o campo mascarado e clica em Copiar (que só
// copia pra área de transferência, não revela nada na tela).
//
// Seletor do campo: `name="access_token"` não é prop declarada em
// WootInput (app/javascript/dashboard/components/widgets/forms/Input.vue)
// — cai por fallthrough no <label> que envolve o <input>, não no <input>
// em si. Por isso o alvo é `label[name="access_token"] input`, não
// `input[name="access_token"]`.

export const id = '02.08';

export const login = {
  contaId: 9,
  usuarioNome: 'Rita Admin',
};

export const baseUrl = 'http://localhost:3000';

// Nada a preparar: token de acesso já existe (todo usuário tem um), o
// campo já nasce escondido por padrão, e o vídeo não muda nada na conta.

export const cenas = [
  {
    legenda: 'Ver o token de acesso',
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
    legenda: 'Abra Configurações do Perfil',
    acao: 'mover e clicar',
    alvo: { texto: 'Configurações do Perfil' },
    aguardarTextoDepois: 'Seu nome completo',
    zoom: 2.5,
  },
  {
    legenda: 'Vá até Token de acesso',
    acao: 'parar',
    alvo: { texto: 'Token de acesso', blocoRolagem: 'start' },
    zoom: 1.5,
    duracaoMs: 1600,
  },
  {
    legenda: 'O token vem escondido',
    acao: 'parar',
    alvo: { seletor: 'label[name="access_token"] input' },
    zoom: 1.8,
    duracaoMs: 2600,
  },
  {
    legenda: 'Clique em Copiar',
    acao: 'mover e clicar',
    alvo: { texto: 'Copiar' },
    zoom: 1.8,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 2400,
  },
];
