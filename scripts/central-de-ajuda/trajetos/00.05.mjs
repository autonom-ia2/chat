// Roteiro do vídeo de trajeto do artigo 00.05 — "Passo 4 — Responder a
// primeira conversa". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/conversation.json.
//
// Trajeto: Conversas → abra a conversa → escreva na aba Responder → Enviar.
//
// Isolamento entre agentes: em vez de reaproveitar uma conversa existente
// (ex. a conversa 1, usada pelo vídeo 02.04), o `preparar` cria uma
// conversa dedicada a este vídeo, com contato fictício próprio — outro
// agente gravando em paralelo na mesma conta não é afetado, e este vídeo
// não depende do estado que outro vídeo deixou.

export const id = '00.05';

export const login = {
  contaId: 9,
  usuarioNome: 'Rita Admin',
};

export const baseUrl = 'http://localhost:3000';

const EMAIL_CONTATO = 'cliente-00.05@desnorteada.test';
const NOME_CONTATO = 'Marcos Ferreira';
const PERGUNTA_CLIENTE = 'Qual o horário de atendimento de vocês?';
const RESPOSTA = 'Atendemos de segunda a sábado, das 8h às 18h.';

export async function preparar({ rodarRails }) {
  await rodarRails(`
account = Account.find(${login.contaId})
usuaria = account.users.find_by(name: ${JSON.stringify(login.usuarioNome)})
raise "usuária não encontrada" unless usuaria
inbox = account.inboxes.find_by(name: 'WhatsApp Comercial')
raise "inbox WhatsApp Comercial não encontrada" unless inbox

email = ${JSON.stringify(EMAIL_CONTATO)}
antigo = account.contacts.find_by(email: email)
if antigo
  antigo.conversations.destroy_all
  antigo.destroy
end

contato = account.contacts.create!(
  name: ${JSON.stringify(NOME_CONTATO)},
  email: email,
  phone_number: '+5511950000105'
)

# Sem isso, a caixa de resposta já vem com a assinatura pré-preenchida (o
# separador "-- " de e-mail) e o texto digitado neste vídeo entra colado
# nessa mesma linha, em vez de aparecer sozinho. Mesma chave que o
# preparar do 02.04 usa.
config = (usuaria.ui_settings || {}).merge("channel_api_signature_enabled" => false)
usuaria.update!(ui_settings: config)
contact_inbox = ContactInboxBuilder.new(contact: contato, inbox: inbox, source_id: SecureRandom.uuid).perform
conversation = contact_inbox.conversations.create!(account: account, contact: contato, inbox: inbox, assignee: usuaria)
conversation.messages.create!(
  content: ${JSON.stringify(PERGUNTA_CLIENTE)},
  message_type: 'incoming',
  account: account,
  sender: contato,
  inbox: inbox
)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Responder a primeira conversa',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
  },
  {
    legenda: 'Abra Conversas',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/dashboard`,
    aguardarTexto: NOME_CONTATO,
    zoom: 1,
    duracaoMs: 1200,
  },
  {
    legenda: 'Abra a conversa que chegou',
    acao: 'mover e clicar',
    alvo: { texto: NOME_CONTATO },
    aguardarTextoDepois: PERGUNTA_CLIENTE,
    zoom: 1.6,
  },
  {
    legenda: 'Escreva a resposta em Responder',
    acao: 'digitar',
    alvo: { seletor: '.reply-box .ProseMirror' },
    texto: [RESPOSTA],
    zoom: 1.8,
  },
  {
    legenda: 'Clique no botão de enviar',
    acao: 'mover e clicar',
    alvo: { seletor: '.right-wrap button[type="submit"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 2400,
  },
];
