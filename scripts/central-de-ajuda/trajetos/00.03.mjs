// Roteiro do vídeo de trajeto do artigo 00.03 — "Passo 2 — Conectar a
// chave da OpenAI". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/{onboardingTrail,integrations,integrationApps}.json
// e config/onboarding/trilha.yml (passo "chave_ia", acao "Conectar a chave").
//
// Trajeto: Primeiros passos → o painel com o passo da chave → botão azul
// "Conectar a chave" → cartão CRM Kanban IA, com o passo a passo para criar a
// chave e o botão Conectar. Não conecta nada: só mostra onde colar a chave.
//
// Servidor: precisa de CRM_AI_ENABLED para o cartão CRM Kanban IA aparecer.
// A conta de teste precisa estar SEM a chave conectada (sem o hook
// crm_kanban_ai): com a chave, o passo fica feito e o painel mostra o passo
// seguinte. O roteiro não cria nem apaga o hook, porque a chave da conta de
// teste pode ser usada por outras gravações e pelo Guia.

export const id = '00.03';

export const login = {
  contaId: 9,
  usuarioNome: 'Rita Admin',
};

export const baseUrl = 'http://localhost:3000';

// O painel mostra o primeiro passo pendente. Para ele ser a chave, o passo do
// perfil precisa estar feito: o preparar garante um aviso do navegador para a
// usuária de teste desta conta (Onboarding::Progress#perfil_configurado).
export async function preparar({ rodarRails }) {
  await rodarRails(`
account = Account.find(${login.contaId})
usuaria = account.users.find_by(name: ${JSON.stringify(login.usuarioNome)})
raise "usuária não encontrada" unless usuaria
raise "a conta de teste está com a chave conectada; grave numa conta sem o hook crm_kanban_ai" if account.hooks.exists?(app_id: 'crm_kanban_ai')
usuaria.notification_subscriptions.find_or_create_by!(identifier: 'gravacao-central') do |aviso|
  aviso.subscription_type = :browser_push
  aviso.subscription_attributes = { endpoint: 'https://gravacao.test/central', p256dh: 'teste', auth: 'teste' }
end
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Passo 2 — Conectar a chave da OpenAI',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/primeiros-passos`,
    aguardarTexto: 'Conectar a chave da OpenAI',
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
    legenda: 'Clique em Conectar a chave',
    acao: 'mover e clicar',
    alvo: { seletor: 'article button' },
    aguardarTextoDepois: 'Como criar sua chave da OpenAI',
    zoom: 1.6,
  },
  {
    legenda: 'Siga o passo a passo para criar a chave',
    acao: 'parar',
    alvo: { texto: 'Como criar sua chave da OpenAI', blocoRolagem: 'start' },
    zoom: 1.3,
    duracaoMs: 3000,
  },
  {
    legenda: 'Depois clique em Conectar e cole a chave',
    acao: 'passar o mouse',
    alvo: { texto: 'Conectar' },
    zoom: 1.6,
    duracaoMs: 3000,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 2400,
  },
];
