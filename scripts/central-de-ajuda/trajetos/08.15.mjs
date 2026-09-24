// Roteiro do vídeo de trajeto do artigo 08.15 — "Ver o histórico de
// chamadas e ouvir gravações". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/calls.json e nos componentes
// components-next/Calls/{CallsIndex,CallsFilterBar,CallListItem}.vue.
//
// Trajeto: Chamadas (menu lateral) → ver a chamada atendida e a perdida →
// filtrar por Perdidas → Mais filtros → escolher a Caixa de Entrada → tela
// final já filtrada.
//
// PARCIAL (não dá pra mostrar o play da gravação) — bug de ambiente, não
// desta gravação: uma Call com recording.attach faz TODA a listagem de
// /calls responder 500. Call#recording_url (enterprise/app/models/call.rb)
// chama `rails_blob_url(recording)` sem `host:`/`only_path: true`, e
// depende de `Rails.application.routes.default_url_options[:host]`
// (config/environments/development.rb: `{ host: ENV['FRONTEND_URL'] }`).
// Confirmado por rails runner: nos 3 servidores (3000/3005/3007)
// `ENV['FRONTEND_URL']` é nil — não é só o meu; é dos três. Sem host, o
// jbuilder de api/v1/accounts/calls#index levanta ArgumentError ("Missing
// host to link to!") ao serializar QUALQUER call com gravação, e a tela
// inteira cai pro estado de erro (a lista via zero calls, inclusive a que
// não tem gravação nenhuma — é uma querry só pra tudo). Setar FRONTEND_URL
// exigiria reiniciar os 3 servidores, proibido pelo lote. Cheguei a
// confirmar isolado (rails runner) que dá pra criar e anexar a gravação no
// banco/ActiveStorage sem tocar serviço externo nenhum — o preparar deste
// roteiro NÃO anexa recording (deixaria a tela de Chamadas quebrada pros
// próximos agentes); ele só cria as duas Call sem áudio, pra pelo menos o
// histórico e os filtros ficarem demonstráveis.
//
// Achado de produto (registrado na entrega, não corrigido aqui): o artigo
// diz "Clique em Mais filtros para ver também Recebidas, Efetuadas ou Em
// andamento" — mas no código atual (CallsFilterBar.vue) essas três opções
// ficam no botão "Outra atividade"; "Mais filtros" só tem a seção "Caixa
// de Entrada". O roteiro segue a TELA de verdade (não o texto do artigo).
//
// Sem Sidekiq/serviço de fora: "chamada" normalmente vem do provedor de
// voz (Twilio) via webhook — não existe no dev. O preparar grava direto no
// Postgres (sem rede) um Channel::TwilioSms com voice_enabled e duas Call.

export const id = '08.15';

export const login = {
  contaId: 9,
  usuarioNome: 'Bia Admin',
};

export const baseUrl = 'http://localhost:3005';

const NOME_CAIXA = 'Central de Voz Sul';
const TELEFONE_CAIXA = '+5511930000015';
const NOME_CONTATO = 'Marcos Pereira';
const TELEFONE_CONTATO = '+5511987654321';

// Idempotente: apaga qualquer sobra de uma gravação anterior deste vídeo
// (mesma caixa, mesmo contato) antes de recriar do zero. Só mexe no que
// este vídeo cria.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})

canal = Channel::TwilioSms.find_by(phone_number: ${JSON.stringify(TELEFONE_CAIXA)})
if canal
  inbox = Inbox.find_by(channel: canal)
  if inbox
    Call.where(inbox: inbox).find_each { |c| c.recording.purge if c.recording.attached?; c.destroy! }
    ContactInbox.where(inbox: inbox).destroy_all
    Conversation.where(inbox: inbox).find_each do |conv|
      Message.where(conversation: conv).delete_all
      conv.destroy!
    end
    inbox.destroy!
  end
  canal.destroy!
end

contato_antigo = conta.contacts.find_by(phone_number: ${JSON.stringify(TELEFONE_CONTATO)})
contato_antigo&.destroy!

# voice_enabled começa false na criação — com true, o before_validation da
# Enterprise (provision_twiml_app) liga de verdade pra API do Twilio pra
# configurar o TwiML app (serviço de fora, proibido até no preparar).
# update_column depois pula validação/callback e só grava a coluna: o
# front lê voice_enabled do banco, não importa como ela chegou lá.
canal = Channel::TwilioSms.create!(
  account: conta,
  account_sid: 'AC_DESNORTEADA_TESTE_0000000000',
  auth_token: 'token-exemplo-desnorteada',
  phone_number: ${JSON.stringify(TELEFONE_CAIXA)},
  voice_enabled: false
)
canal.update_column(:voice_enabled, true)
inbox = Inbox.create!(account: conta, name: ${JSON.stringify(NOME_CAIXA)}, channel: canal)

contato = Contact.create!(
  account: conta,
  name: ${JSON.stringify(NOME_CONTATO)},
  phone_number: ${JSON.stringify(TELEFONE_CONTATO)}
)
# source_id de uma inbox Channel::TwilioSms precisa ser o telefone em E.164
# (validação do model) — não um uuid qualquer.
contato_inbox = ContactInbox.create!(contact: contato, inbox: inbox, source_id: ${JSON.stringify(TELEFONE_CONTATO)})
conversa = Conversation.create!(account: conta, inbox: inbox, contact: contato, contact_inbox: contato_inbox)

atendente = conta.users.find_by(name: ${JSON.stringify(login.usuarioNome)})

# SEM recording.attach de propósito: anexar áudio a uma Call faz a tela
# inteira de Chamadas responder 500 neste ambiente (ver comentário no topo
# do arquivo — FRONTEND_URL ausente nos 3 servidores dev). Isso quebraria a
# tela pros próximos agentes que passarem por aqui.
Call.create!(
  account: conta,
  inbox: inbox,
  conversation: conversa,
  contact: contato,
  accepted_by_agent: atendente,
  provider: :twilio,
  provider_call_id: 'CA_DESNORTEADA_TESTE_0001',
  direction: :incoming,
  status: 'completed',
  started_at: 2.hours.ago,
  duration_seconds: 47
)

Call.create!(
  account: conta,
  inbox: inbox,
  conversation: conversa,
  contact: contato,
  provider: :twilio,
  provider_call_id: 'CA_DESNORTEADA_TESTE_0002',
  direction: :incoming,
  status: 'no_answer',
  started_at: 20.minutes.ago
)

puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Ver o histórico de chamadas',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
  {
    legenda: 'Clique em Chamadas',
    acao: 'mover e clicar',
    alvo: { texto: 'Chamadas' },
    zoom: 1.8,
    aguardarTextoDepois: NOME_CONTATO,
  },
  {
    legenda: 'Veja quem ligou e quem atendeu',
    acao: 'parar',
    alvo: { texto: NOME_CONTATO },
    zoom: 1.6,
    duracaoMs: 2200,
  },
  {
    legenda: 'Clique no filtro Perdidas',
    acao: 'mover e clicar',
    alvo: { texto: 'Perdidas' },
    zoom: 1.6,
  },
  {
    legenda: 'Clique em Mais filtros',
    acao: 'mover e clicar',
    alvo: { texto: 'Mais filtros' },
    zoom: 1.6,
    aguardarTextoDepois: 'Caixa de Entrada',
  },
  {
    legenda: 'Escolha uma Caixa de Entrada',
    acao: 'mover e clicar',
    alvo: { texto: NOME_CAIXA },
    zoom: 1.6,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2600,
  },
];
