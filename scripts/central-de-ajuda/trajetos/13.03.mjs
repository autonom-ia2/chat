// Roteiro do vídeo de trajeto do artigo 13.03 — "Criar e acompanhar uma
// campanha de WhatsApp API". Gravado no servidor liberado pelo coordenador
// em http://localhost:3005 (mesmo banco, Vite compartilhado,
// WHATSAPP_API_CAMPAIGNS_ENABLED=true) — o servidor de
// http://localhost:3000 não tem esse recurso ligado.
//
// Para do jeito que a regra pede: preenche até o fim do formulário e NÃO
// clica em "Criar campanha" (isso agendaria um envio de verdade). Sem
// Sidekiq no ar, nada seria enviado mesmo — mas a regra vale de qualquer
// forma.
//
// Trajeto: Campanhas → aba WhatsApp API → Criar campanha → Título → Caixa
// → Mensagem → Público → campo de Horário agendado (só clica, não
// preenche — ver nota na cena).

export const id = '13.03';

export const login = {
  contaId: 9,
  usuarioNome: 'Rafa Admin',
};

export const baseUrl = 'http://localhost:3005';

const CAIXA_NOME = 'WhatsApp Renovações';
const TITULO = 'Renovação de outubro';
const MENSAGEM =
  'Ola {{contact.first_name}}, sua apolice vence em breve. Vamos renovar?';

// Roda antes de gravar: garante a caixa WhatsApp API deste vídeo, marcada
// para campanha — não mexe nas caixas WhatsApp compartilhadas
// (WhatsApp Comercial, WhatsApp Sinistros etc.), usadas por outros vídeos.
// Idempotente: sempre a mesma caixa, nunca apagada entre gravações.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
inbox = conta.inboxes.find_by(name: ${JSON.stringify(CAIXA_NOME)})
unless inbox
  channel = Channel::Api.create!(account: conta, webhook_url: nil)
  inbox = conta.inboxes.create!(name: ${JSON.stringify(CAIXA_NOME)}, channel: channel)
end
inbox.channel.enable_whatsapp_api_campaigns! unless inbox.channel.whatsapp_api_campaign_channel?
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Criar campanha de WhatsApp API',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 900,
  },
  {
    legenda: 'Abra o menu Campanhas',
    acao: 'mover e clicar',
    alvo: { seletor: 'nav a[name="Campaigns"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Abra a aba WhatsApp API',
    acao: 'mover e clicar',
    alvo: { texto: 'WhatsApp API' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Criar campanha',
    acao: 'mover e clicar',
    alvo: { texto: 'Criar campanha' },
    zoom: 1.8,
  },
  {
    legenda: 'Preencha o Título',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Ex: Reativação Junho"]' },
    texto: [TITULO],
    zoom: 1.8,
  },
  {
    legenda: 'Escolha a caixa marcada para campanha',
    acao: 'mover e clicar',
    alvo: { texto: 'Selecione uma caixa' },
    zoom: 1.8,
  },
  {
    legenda: CAIXA_NOME,
    acao: 'mover e clicar',
    alvo: { texto: CAIXA_NOME },
    zoom: 1.6,
  },
  {
    legenda: 'Escreva a mensagem',
    acao: 'digitar',
    alvo: {
      seletor: 'textarea[placeholder="Olá {{contact.first_name}}, tudo bem?"]',
    },
    texto: [MENSAGEM],
    zoom: 1.8,
  },
  {
    legenda: 'Escolha o público pela etiqueta',
    acao: 'mover e clicar',
    alvo: { texto: 'Selecionar etiquetas dos contatos' },
    zoom: 1.8,
  },
  {
    legenda: 'Etiqueta renovação',
    acao: 'mover e clicar',
    alvo: { texto: 'renovacao' },
    zoom: 1.8,
  },
  {
    // Só clica pra revelar o seletor nativo de data/hora — não preenche.
    // O motor digita texto via inserção simples, que não navega pelos
    // segmentos de um campo datetime-local do jeito que um teclado real
    // navegaria; e o formulário já para aqui de qualquer forma, sem
    // clicar em "Criar campanha".
    legenda: 'Marque o Horário agendado',
    acao: 'mover e clicar',
    alvo: { seletor: 'input[type="datetime-local"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Pare aqui — não envie',
    acao: 'parar',
    zoom: 1.8,
    alvo: { seletor: 'input[type="datetime-local"]' },
    duracaoMs: 1200,
  },
];
