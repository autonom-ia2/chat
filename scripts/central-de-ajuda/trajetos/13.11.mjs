// Roteiro do vídeo de trajeto do artigo 13.11 — "Analisar uma campanha e
// usar links rastreáveis".
//
// O vídeo foca a seção de Links rastreáveis (não depende de campanha de
// e-mail, só do CRM, já ligado na conta). Criar um link é uma ação real e
// local (Ctwa::TrackedLink, sem chamada externa) — pode clicar de verdade.
// "Excluir" usa `window.confirm` nativo, que o motor não sabe responder;
// o vídeo mostra o botão sem clicar nele.
//
// Precisa de uma caixa de WhatsApp (só elas aparecem no seletor do link) —
// cria a sua própria, no mesmo padrão do 07.05/13.02/13.12 (skip_callback,
// nunca sincroniza com a Meta).

export const id = '13.11';

export const login = {
  contaId: 9,
  usuarioNome: 'Rafa Admin',
};

export const baseUrl = 'http://localhost:3000';

const NOME_CAIXA = 'WhatsApp Loja Centro';
const TELEFONE_CANAL = '5511900000611';
const NOME_LINK = 'QR da loja - Centro';

export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
nome_caixa = ${JSON.stringify(NOME_CAIXA)}
telefone = ${JSON.stringify(TELEFONE_CANAL)}
nome_link = ${JSON.stringify(NOME_LINK)}

existente = conta.inboxes.find_by(name: nome_caixa)
if existente
  Ctwa::TrackedLink.where(account_id: conta.id, inbox_id: existente.id).delete_all
  Conversation.where(inbox_id: existente.id).destroy_all
  ContactInbox.where(inbox_id: existente.id).delete_all
  existente.destroy!
end
Channel::Whatsapp.where(phone_number: telefone).delete_all

Channel::Whatsapp.skip_callback(:create, :after, :sync_templates, raise: false)
canal = Channel::Whatsapp.new(
  account: conta,
  phone_number: telefone,
  provider: "default",
  provider_config: { "api_key" => "chave-fake-video" },
  message_templates: [],
  message_templates_last_updated: Time.now.utc,
  phone_number_health: {}
)
canal.save!(validate: false)
Inbox.create!(account: conta, name: nome_caixa, channel: canal)

# Idempotente: se um link de execução anterior deste roteiro sobrou (nome
# igual), apaga antes — o vídeo sempre cria o link ao vivo.
if defined?(Ctwa::TrackedLink)
  Ctwa::TrackedLink.where(account_id: conta.id, name: nome_link).delete_all
end

puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Analisar campanha e usar links rastreáveis',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/crm/campaign-management`,
    aguardarTexto: 'Links rastreáveis e códigos QR',
    zoom: 1,
    duracaoMs: 1200,
  },
  {
    legenda: 'Role até Links rastreáveis e códigos QR',
    acao: 'parar',
    alvo: { texto: 'Links rastreáveis e códigos QR', blocoRolagem: 'start' },
    zoom: 1.3,
    duracaoMs: 1600,
  },
  {
    legenda: 'Dê um nome ao link',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Ex.: QR da loja — Centro"]' },
    texto: [NOME_LINK],
    zoom: 1.8,
  },
  {
    legenda: 'Escolha a caixa de WhatsApp',
    acao: 'mover e clicar',
    alvo: { seletor: 'label[aria-label="Caixa de entrada do WhatsApp"] button' },
    zoom: 1.8,
  },
  {
    legenda: 'Só caixas de WhatsApp aparecem',
    acao: 'mover e clicar',
    alvo: { texto: NOME_CAIXA },
    zoom: 1.6,
  },
  {
    legenda: 'Preencha a mensagem pré-preenchida',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Ex.: Olá! Quero saber mais"]' },
    texto: ['Ola! Quero saber mais sobre o seguro auto'],
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Novo link',
    acao: 'mover e clicar',
    alvo: { texto: 'Novo link' },
    zoom: 1.6,
    aguardarTextoDepois: NOME_LINK,
  },
  {
    legenda: 'O link e o QR ficam prontos na hora',
    acao: 'parar',
    alvo: { texto: NOME_LINK, dentro: { texto: NOME_LINK, subindoAte: 'tr' } },
    zoom: 1.4,
    duracaoMs: 1600,
  },
  {
    legenda: 'Clique em Copiar link',
    acao: 'mover e clicar',
    alvo: {
      texto: 'Copiar link',
      dentro: { texto: NOME_LINK, subindoAte: 'tr' },
    },
    zoom: 1.8,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    alvo: { texto: NOME_LINK, dentro: { texto: NOME_LINK, subindoAte: 'tr' } },
    zoom: 1.4,
    duracaoMs: 1800,
  },
];
