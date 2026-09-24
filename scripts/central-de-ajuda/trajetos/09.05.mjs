// Roteiro do vídeo de trajeto do artigo 09.05 — "Histórico de conversas e
// mídia do contato".
//
// Mesmo contato do 09.04 ("Eduardo Martins") — este `preparar` só cuida de
// histórico e mídia (conversas antigas + um anexo de imagem e um de
// documento), sem tocar em etiqueta/bloqueio/notas (isso é do 09.04).
// Idempotente: apaga e recria só as conversas com a marca deste roteiro.

export const id = '09.05';

export const login = {
  contaId: 9,
  usuarioNome: 'Rafa Admin',
};

export const baseUrl = 'http://localhost:3000';

const NOME_CONTATO = 'Eduardo Martins';
const TELEFONE_CONTATO = '+5511982250701';

export async function preparar({ rodarRails }) {
  await rodarRails(`
require "base64"

conta = Account.find(${login.contaId})
contato = conta.contacts.find_or_initialize_by(phone_number: ${JSON.stringify(TELEFONE_CONTATO)})
contato.name = ${JSON.stringify(NOME_CONTATO)}
contato.save!

inbox = conta.inboxes.find_by(name: "WhatsApp Comercial") || conta.inboxes.first
raise "conta sem nenhuma caixa" unless inbox

# Idempotente: apaga só as conversas deste contato NESTA caixa marcadas
# pelo roteiro (additional_attributes.video0905) antes de recriar.
conta.conversations.where(contact_id: contato.id, inbox_id: inbox.id).find_each do |c|
  next unless c.additional_attributes.to_h["video0905"]
  Message.where(conversation_id: c.id).delete_all
  c.destroy!
end

cid = ContactInbox.find_or_create_by!(contact: contato, inbox: inbox) { |ci| ci.source_id = ${JSON.stringify(TELEFONE_CONTATO)}.delete("+") }.id

def nova_conversa(conta, inbox, contato, cid, resumo, dias_atras)
  conta.conversations.create!(
    inbox: inbox,
    contact: contato,
    contact_inbox_id: cid,
    status: :resolved,
    additional_attributes: { "video0905" => true },
    created_at: dias_atras.days.ago
  ).tap do |c|
    Message.create!(
      account: conta, conversation: c, inbox: inbox,
      message_type: :incoming, content: resumo,
      sender: contato, created_at: dias_atras.days.ago
    )
    Message.create!(
      account: conta, conversation: c, inbox: inbox,
      message_type: :outgoing, content: "Obrigado pelo contato! Vamos analisar e te retornamos em breve.",
      created_at: dias_atras.days.ago + 20.minutes
    )
  end
end

conversa1 = nova_conversa(conta, inbox, contato, cid, "Gostaria de uma cotacao de seguro para meu carro novo", 12)
conversa2 = nova_conversa(conta, inbox, contato, cid, "Poderia reenviar a apolice em PDF?", 5)
nova_conversa(conta, inbox, contato, cid, "Confirmando o pagamento da parcela deste mes", 1)

# Anexo de imagem (PNG 1x1) numa mensagem da conversa 1.
png = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")
msg_imagem = Message.create!(
  account: conta, conversation: conversa1, inbox: inbox,
  message_type: :incoming, content: "", sender: contato, created_at: 12.days.ago + 5.minutes
)
attach_img = msg_imagem.attachments.new(account_id: conta.id, file_type: :image)
attach_img.file.attach(io: StringIO.new(png), filename: "carro.png", content_type: "image/png")
attach_img.save!

# Anexo de documento (txt, tipo aceito) numa mensagem da conversa 2.
msg_doc = Message.create!(
  account: conta, conversation: conversa2, inbox: inbox,
  message_type: :outgoing, content: "", created_at: 5.days.ago + 5.minutes
)
attach_doc = msg_doc.attachments.new(account_id: conta.id, file_type: :file)
attach_doc.file.attach(io: StringIO.new("Apolice fake para o video 09.05."), filename: "apolice.txt", content_type: "text/plain")
attach_doc.save!

puts "preparo-ok contato=#{contato.id}"
`);
}

export const cenas = [
  {
    legenda: 'Histórico de conversas e mídia do contato',
    acao: 'mover e clicar',
    alvo: { seletor: 'nav a[name="Contacts"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Busque o contato',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Pesquisar..."]' },
    texto: [NOME_CONTATO],
    zoom: 1.8,
  },
  {
    legenda: 'Abra o contato',
    acao: 'mover e clicar',
    alvo: { texto: NOME_CONTATO },
    zoom: 1.6,
  },
  {
    legenda: 'Veja os detalhes',
    acao: 'mover e clicar',
    alvo: { texto: 'Ver detalhes' },
    zoom: 1.6,
  },
  {
    legenda: 'Abra a aba Histórico',
    acao: 'mover e clicar',
    alvo: { texto: 'Histórico' },
    zoom: 1.6,
    aguardarTextoDepois: 'Obrigado pelo contato',
  },
  {
    legenda: 'As conversas mais recentes aparecem aqui',
    acao: 'parar',
    alvo: {
      texto: 'Obrigado pelo contato! Vamos analisar e te retornamos em breve.',
    },
    zoom: 1.4,
    duracaoMs: 1800,
  },
  {
    // A aba Mídia fica de fora: o ambiente dev não tem
    // default_url_options[:host] configurado para o ActiveStorage, e a
    // rota de anexos (.../contacts/:id/attachments) quebra com 500
    // ("Missing host to link to!") pra QUALQUER contato com anexo de
    // verdade — confirmado no log do Rails, não é specific dos dados
    // deste vídeo. "precisa de motor" (config do ambiente, não deste
    // roteiro) — ver resposta final.
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 1400,
  },
];
