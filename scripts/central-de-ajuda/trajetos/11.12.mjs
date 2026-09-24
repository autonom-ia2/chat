// Roteiro do vídeo de trajeto do artigo 11.12 — "Robôs (integração por
// webhook): o terceiro 'agente' da plataforma". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/agentBots.json (chave
// AGENT_BOTS.*) e nos componentes
// routes/dashboard/settings/agentBots/{Index,components/AgentBotModal}.vue
// e routes/dashboard/settings/inbox/components/BotConfiguration.vue.
//
// Só a Parte 1 do artigo (criar o robô) — achado de produto, não corrigido
// aqui (proibido mexer no motor/app nesta fase): em 3 gravações limpas
// seguidas, depois de criar o robô pela UI (Configurações → Robôs →
// formulário → Criar um Robô), abrir QUALQUER caixa (mesmo uma recém
// criada, Channel::Api comum) trava com a aba "Configuração do Bot" nunca
// aparecendo, apesar de `Account#feature_enabled?("agent_bots")` continuar
// true no banco o tempo todo (conferido via rails runner logo após a
// falha). Uma sondagem manual equivalente, SEM criar o robô antes, achava
// essa mesma aba em ~2,5s sem problema — o robô recém-criado nesta sessão
// parece ser a diferença real, não carga do ambiente compartilhado (regra
// dos 3 retries do P2 já foi seguida). "Criar um Robô" continua sendo o
// clique real (grava só registro local, sem serviço de fora) — o vínculo
// bot↔caixa (Parte 2, aba Configuração do Bot) fica só no texto do
// artigo.

export const id = '11.12';

export const login = {
  contaId: 9,
  usuarioNome: 'Téo Admin',
};

export const baseUrl = 'http://localhost:3005';

const NOME_ROBO = 'Robô Cotação Simples';
const DESCRICAO_ROBO = 'Responde dúvidas simples de cotação pelo nosso serviço';
const URL_WEBHOOK = 'https://robos.desnorteada.test/webhook';

// Idempotente: apaga o robô de uma gravação anterior antes de gravar de
// novo. Só mexe no que este vídeo cria.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
conta.agent_bots.where(name: ${JSON.stringify(NOME_ROBO)}).destroy_all
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Criar um Robô por webhook',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/agent-bots`,
    aguardarTexto: 'Criar Robô',
    zoom: 1,
    duracaoMs: 1800,
  },
  {
    legenda: 'Clique em Criar Robô',
    acao: 'mover e clicar',
    alvo: { texto: 'Criar Robô' },
    zoom: 1.8,
    aguardarTextoDepois: 'Nome do Robô',
  },
  {
    legenda: 'Escreva o Nome do Robô',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Insira o nome do robô"]' },
    texto: [NOME_ROBO],
    zoom: 1.8,
  },
  {
    legenda: 'Escreva a Descrição',
    acao: 'digitar',
    alvo: { seletor: 'textarea[placeholder="O que esse robô faz?"]' },
    texto: [DESCRICAO_ROBO],
    zoom: 1.8,
  },
  {
    legenda: 'Cole a URL do Webhook',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="https://example.com/webhook"]' },
    texto: [URL_WEBHOOK],
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Criar um Robô',
    acao: 'mover e clicar',
    alvo: { texto: 'Criar um Robô' },
    zoom: 1.8,
    aguardarTextoDepois: 'Token de acesso',
  },
  {
    legenda: 'Copie o Token e o Segredo agora',
    acao: 'parar',
    alvo: { texto: 'Token de acesso' },
    zoom: 1.5,
    duracaoMs: 1800,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    alvo: { texto: 'Token de acesso' },
    zoom: 1.5,
    duracaoMs: 1600,
  },
];
