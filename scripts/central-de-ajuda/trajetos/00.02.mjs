// Roteiro do vídeo de trajeto do artigo 00.02 — "Passo 1 — Seu perfil e seus
// avisos". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/{onboardingTrail,settings}.json
// (PROFILE_SETTINGS.FORM.NOTIFICATIONS) e config/onboarding/trilha.yml (passo
// "perfil", acao "Ajustar meu perfil").
//
// Trajeto: Primeiros passos → o painel com o passo do perfil → botão azul
// "Ajustar meu perfil" → Preferências de notificação → aviso do navegador.

export const id = '00.02';

export const login = {
  contaId: 9,
  usuarioNome: 'Rita Admin',
};

export const baseUrl = 'http://localhost:3000';

// O passo do perfil só aparece no painel enquanto está pendente, e ele fica
// feito quando a usuária tem aviso do navegador ligado
// (Onboarding::Progress#perfil_configurado). O preparar apaga só os avisos do
// navegador da usuária de teste desta conta, para o passo voltar a pendente.
// Não toca em outra usuária nem em outra conta.
export async function preparar({ rodarRails }) {
  await rodarRails(`
account = Account.find(${login.contaId})
usuaria = account.users.find_by(name: ${JSON.stringify(login.usuarioNome)})
raise "usuária não encontrada" unless usuaria
usuaria.notification_subscriptions.destroy_all
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Passo 1 — Seu perfil e seus avisos',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/primeiros-passos`,
    aguardarTexto: 'Seu perfil e seus avisos',
    zoom: 1,
    duracaoMs: 2600,
  },
  {
    // O selo diz "Seu próximo passo · N de 9"; o título do passo no painel é o
    // alvo estável.
    legenda: 'O passo aparece no painel',
    acao: 'parar',
    alvo: { seletor: 'article h2', blocoRolagem: 'center' },
    zoom: 1.4,
    duracaoMs: 2200,
  },
  {
    legenda: 'Clique em Ajustar meu perfil',
    acao: 'mover e clicar',
    alvo: { seletor: 'article button' },
    // Espera a tela de perfil carregar antes do desfoque de marca: ela tem
    // "...painel do <nome da instalação>" logo no topo.
    aguardarTextoDepois: 'Preferências de notificação',
    zoom: 1.6,
  },
  {
    legenda: 'Escolha os avisos que você quer receber',
    acao: 'parar',
    alvo: { texto: 'Preferências de notificação', blocoRolagem: 'start' },
    zoom: 1.4,
    duracaoMs: 2600,
  },
  {
    legenda: 'Ligue a notificação do navegador',
    acao: 'parar',
    alvo: {
      texto: 'Ative notificações push em seu navegador para poder recebê-las',
      blocoRolagem: 'center',
    },
    zoom: 1.6,
    duracaoMs: 2800,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 2400,
  },
];
