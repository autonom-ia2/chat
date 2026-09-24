// Roteiro do vídeo de trajeto do artigo 06.05 — "Webhooks e Painel de
// Aplicativos". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/integrations.json (chave
// INTEGRATION_SETTINGS.WEBHOOK.* e INTEGRATION_SETTINGS.DASHBOARD_APPS.*)
// e no componente
// routes/dashboard/settings/integrations/Webhooks/WebhookForm.vue.
//
// "Criar webhook" só grava a URL na própria conta (Webhook#save!,
// app/controllers/api/v1/accounts/webhooks_controller.rb) — o endereço só é
// chamado de verdade quando um evento de conversa acontecer, o que não
// ocorre nesta gravação. Sem serviço de fora — o clique final acontece de
// verdade, como o artigo pede ("copie agora" o Segredo).
//
// Trajeto: Integrações → Webhooks → Adicionar novo Webhook → URL + nome +
// evento → Criar webhook → Segredo → Concluído → Painel de Aplicativos (o
// caminho até a tela certa, com o botão de criar em destaque — sem abrir o
// formulário, pra caber no tempo).

export const id = '06.05';

export const login = {
  contaId: 9,
  usuarioNome: 'Téo Admin',
};

export const baseUrl = 'http://localhost:3005';

const URL_WEBHOOK = 'https://webhook.desnorteada.test/eventos';
const NOME_WEBHOOK = 'Notificações CRM';

// Idempotente: apaga um webhook anterior deste vídeo pela URL (única por
// conta) antes de gravar de novo. Só mexe no que este vídeo cria.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
conta.webhooks.where(url: ${JSON.stringify(URL_WEBHOOK)}).destroy_all
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Webhooks e Painel de Aplicativos',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/integrations/webhook`,
    aguardarTexto: 'Adicionar novo Webhook',
    zoom: 1,
    duracaoMs: 1800,
  },
  {
    legenda: 'Clique em Adicionar novo Webhook',
    acao: 'mover e clicar',
    alvo: { texto: 'Adicionar novo Webhook' },
    zoom: 1.8,
    aguardarTextoDepois: 'URL do Webhook',
  },
  {
    legenda: 'Informe a URL do Webhook',
    acao: 'digitar',
    alvo: { seletor: 'input[name="url"]' },
    texto: [URL_WEBHOOK],
    zoom: 1.8,
  },
  {
    legenda: 'Dê um nome ao webhook',
    acao: 'digitar',
    alvo: { seletor: 'input[name="name"]' },
    texto: [NOME_WEBHOOK],
    zoom: 1.8,
  },
  {
    legenda: 'Marque os eventos que quer assinar',
    acao: 'mover e clicar',
    alvo: { seletor: '#conversation_created' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Criar webhook',
    acao: 'mover e clicar',
    alvo: { texto: 'Criar webhook' },
    zoom: 1.8,
    aguardarTextoDepois: 'Segredo',
  },
  {
    legenda: 'Copie o Segredo agora',
    acao: 'parar',
    alvo: { texto: 'Segredo' },
    zoom: 1.6,
    duracaoMs: 2000,
  },
  {
    legenda: 'Clique em Concluído',
    acao: 'mover e clicar',
    alvo: { texto: 'Concluído' },
    zoom: 1.6,
  },
  {
    legenda: 'Painel de Aplicativos mostra sua tela na conversa',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/integrations/dashboard_apps`,
    aguardarTexto: 'Painel de Aplicativos',
    zoom: 1,
    duracaoMs: 1600,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    alvo: { texto: 'Adicionar um novo aplicativo' },
    zoom: 1.8,
    duracaoMs: 2200,
  },
];
