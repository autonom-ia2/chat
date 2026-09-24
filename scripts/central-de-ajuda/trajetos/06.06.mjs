// Roteiro do vídeo de trajeto do artigo 06.06 — "n8n e integrações de
// terceiros". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/integrations.json (chave
// INTEGRATION_SETTINGS.CRM_N8N.*) e nos componentes CrmN8n.vue e
// CrmIntegrationTokensPage.vue.
//
// CUIDADO DO P3 ("qualquer chave nunca aparece legível"): a página de
// tokens do CRM (CrmIntegrationTokensPage.vue) mostra o valor do token em
// TEXTO PURO dentro de um <code>, sem máscara — ao contrário do token de
// acesso pessoal (AccessToken.vue, que nasce type="password"). Por isso
// este vídeo NUNCA clica em "Criar" na tela de tokens: só mostra o
// formulário preenchido (nome + escopos marcados) e para antes do clique.
// Pelo mesmo motivo cautelar, a etapa de webhook também para antes do
// clique final em "Criar webhook" — o cadastro de webhook já mostra um
// "Segredo" em texto puro (WebhookForm.vue), e "qualquer chave" da regra
// do Rodrigo cobre isso também.
//
// Trajeto: Configurações → Integrações → n8n (Conexões do CRM) → cartão
// com os dois CTAs → Criar token de API do CRM (nome + escopos, sem
// clicar em Criar) → volta → Criar webhook para eventos do CRM (URL +
// evento, sem clicar em Criar webhook).

export const id = '06.06';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

export const baseUrl = 'http://localhost:3000';

const URL_WEBHOOK_N8N = 'https://n8n.desnorteada.test/webhook/crm-eventos';

// Só leitura na tela de n8n em si — não cria token nem webhook de
// verdade (o roteiro para antes de qualquer um dos dois cliques finais).
export const preparar = null;

export const cenas = [
  {
    legenda: 'n8n e integrações de terceiros',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/integrations/crm_n8n`,
    aguardarTexto: 'Criar token de API do CRM',
    zoom: 1,
    duracaoMs: 2000,
  },
  {
    legenda: 'Gere um token e crie um webhook',
    acao: 'parar',
    alvo: { texto: 'Criar token de API do CRM' },
    zoom: 1.6,
    duracaoMs: 1800,
  },
  {
    legenda: 'Clique em Criar token de API do CRM',
    acao: 'mover e clicar',
    alvo: { texto: 'Criar token de API do CRM' },
    zoom: 1.8,
    aguardarTextoDepois: 'Criar um token',
  },
  {
    legenda: 'Dê um nome ao token',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="ex.: n8n produção"]' },
    texto: ['Fluxo n8n comercial'],
    zoom: 1.8,
  },
  {
    legenda: 'Marque os escopos que o n8n vai usar',
    acao: 'mover e clicar',
    alvo: { seletor: 'input[type="checkbox"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Pare aqui, antes de criar o token',
    acao: 'parar',
    alvo: { texto: 'Criar token' },
    zoom: 1.6,
    duracaoMs: 2000,
  },
  {
    legenda: 'Volte para n8n e crie o webhook',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/integrations/webhook`,
    aguardarTexto: 'Adicionar novo Webhook',
    zoom: 1,
    duracaoMs: 1400,
  },
  {
    legenda: 'Clique em Adicionar novo Webhook',
    acao: 'mover e clicar',
    alvo: { texto: 'Adicionar novo Webhook' },
    zoom: 1.8,
    aguardarTextoDepois: 'URL do Webhook',
  },
  {
    legenda: 'Informe a URL do seu n8n',
    acao: 'digitar',
    alvo: { seletor: 'input[name="url"]' },
    texto: [URL_WEBHOOK_N8N],
    zoom: 1.8,
  },
  {
    legenda: 'Marque os eventos de card do CRM',
    acao: 'mover e clicar',
    alvo: { seletor: 'input[id="crm.card.created"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Pare aqui, antes de criar o webhook',
    acao: 'parar',
    alvo: { texto: 'Criar webhook' },
    zoom: 1.6,
    duracaoMs: 2000,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 1800,
  },
];
