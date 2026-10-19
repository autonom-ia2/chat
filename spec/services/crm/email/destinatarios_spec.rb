require 'rails_helper'

# #1828: a resposta da IA por e-mail mantém a cópia como o "Responder a todos" do painel; quem pede para sair sai da
# cópia daquela conversa (IA e painel), e o cliente segue recebendo.
RSpec.describe Crm::Email::Destinatarios do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_email, account: account, email: 'corretora@example.com') }
  let(:inbox) { channel.inbox }
  let(:joao) { create(:contact, account: account, email: 'joao@empresa.com.br') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: joao) }
  let(:agent_inbox) do
    agent = Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                             instruction: 'Atenda o cliente.')
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: create(:agent_bot, account: account))
  end

  before { account.enable_features!(Crm::Email::Autoria::FLAG) }

  def recebido!(from:, cc: [], content: 'Oi')
    create(:message, account: account, inbox: inbox, conversation: conversation, sender: joao, message_type: :incoming,
                     content_type: :incoming_email, content: content,
                     content_attributes: { 'email' => { 'from' => [from], 'cc' => cc, 'text_content' => { 'reply' => content } } })
  end

  def resposta_da_ia
    responder = Autonomia::Agents::Operate::Responder.new(conversation: conversation.reload, agent_inbox: agent_inbox)
    responder.send(:post_reply!, 'Segue a cotação.')
    conversation.messages.outgoing.reorder(:id).last.content_attributes
  end

  # Pega: a Ana em cópia sumir da resposta da IA; a caixa, o endereço de resposta ou o cliente se repetirem.
  it 'a IA responde ao João mantendo a Ana em cópia, sem a caixa e sem repetir o cliente', :aggregate_failures do
    recebido!(from: 'joao@empresa.com.br', cc: ['Ana@Familia.com.br', 'corretora@example.com', channel.forward_to_email,
                                                'reply+6bdc3f4d-0bec-4515-a284-5d916fd18070@example.com', 'joao@empresa.com.br'])

    atributos = resposta_da_ia
    expect(atributos[:to_emails]).to eq(['joao@empresa.com.br'])
    expect(atributos[:cc_emails]).to eq(['ana@familia.com.br'])
    expect(atributos[:bcc_emails]).to eq([])
  end

  # Pega: a regra divergir do painel quando foi a Ana quem escreveu por último (Para = ela, o João em cópia); e a IA
  # responder só à Ana (o Para da IA é sempre o cliente; a Ana vai em cópia).
  it 'quando a Ana escreveu por último: o painel como hoje; a IA ao João com a Ana em cópia', :aggregate_failures do
    recebido!(from: 'ana@familia.com.br', cc: ['joao@empresa.com.br'])

    expect(described_class.new(conversation).perform).to eq(to: ['ana@familia.com.br'], cc: ['joao@empresa.com.br'], bcc: [])
    expect(resposta_da_ia).to include(to_emails: ['joao@empresa.com.br'], cc_emails: ['ana@familia.com.br'])
  end

  # Pega: a caixa no Cco (a resposta voltaria à caixa) e um cliente de verdade com "reply+" no endereço sumir.
  it 'o Cco sai sem a caixa e sem o cliente; "reply+" só sai quando é o endereço de resposta da plataforma', :aggregate_failures do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     content_attributes: { 'to_emails' => ['joao@empresa.com.br'], 'cc_emails' => ['reply+promo@loja.com'],
                                           'bcc_emails' => ['corretora@example.com', 'joao@empresa.com.br', 'gerente@corretora.com'] })

    expect(described_class.new(conversation).perform)
      .to eq(to: ['joao@empresa.com.br'], cc: ['reply+promo@loja.com'], bcc: ['gerente@corretora.com'])
  end

  # Pega: "parem de me copiar" da Ana não tirar ela da cópia (IA e painel), ou tirar o João.
  it 'a Ana pede para sair e some da cópia; o João segue recebendo', :aggregate_failures do
    ana = recebido!(from: 'ana@familia.com.br', cc: ['joao@empresa.com.br'], content: 'parem de me copiar')
    card = create_card_para(ana)
    allow(Rails.cache).to receive(:fetch).and_return({ decision: 'sim', motivo: 'pedido_explicito_de_parar' })

    Crm::FollowUps::OptOutDecision.new(card: card, message: ana).perform
    recebido!(from: 'joao@empresa.com.br', cc: ['ana@familia.com.br', 'rh@empresa.com.br'])

    expect(conversation.reload.additional_attributes[described_class::CHAVE]).to eq(['ana@familia.com.br'])
    expect(resposta_da_ia).to include(to_emails: ['joao@empresa.com.br'], cc_emails: ['rh@empresa.com.br'])
    expect(joao.reload).not_to be_opted_out
  end

  # Pega: o pedido do próprio cliente o tirar da cópia (ele é o destinatário, nunca sai).
  it 'o cliente nunca entra na lista de quem saiu' do
    described_class.registrar_saida!(conversation, 'JOAO@empresa.com.br')

    expect(conversation.reload.additional_attributes.to_h).not_to have_key(described_class::CHAVE)
  end

  # Pega: e-mail sem ninguém em cópia mudar a resposta (vai só ao cliente, como hoje).
  it 'e-mail sem cópia: a resposta vai só ao cliente' do
    recebido!(from: 'joao@empresa.com.br')

    expect(resposta_da_ia).to include(to_emails: ['joao@empresa.com.br'], cc_emails: [], bcc_emails: [])
  end

  # Pega: a resposta do turno da passagem (post_reply! próprio, fora do Responder) derrubar a cópia; e a chave da
  # passagem sumir com os destinatários.
  it 'a resposta da IA na passagem também mantém a Ana em cópia', :aggregate_failures do
    recebido!(from: 'joao@empresa.com.br', cc: ['ana@familia.com.br'])
    passagem = instance_double(Crm::Passagem, id: 7)
    responder = Autonomia::Agents::Operate::ResponderAPassagem.new(conversation: conversation.reload, agent_inbox: agent_inbox,
                                                                   passagem: passagem)

    responder.send(:post_reply!, 'Sigo daqui.')
    atributos = conversation.messages.outgoing.reorder(:id).last.content_attributes
    expect(atributos).to include(to_emails: ['joao@empresa.com.br'], cc_emails: ['ana@familia.com.br'])
    expect(atributos['autonomia_passagem_id']).to eq(7)
  end

  # Pega: a resposta da passagem levar cópia com a flag desligada.
  it 'sem a flag, a resposta da passagem não leva cópia, como antes' do
    account.disable_features!(Crm::Email::Autoria::FLAG)
    recebido!(from: 'joao@empresa.com.br', cc: ['ana@familia.com.br'])
    responder = Autonomia::Agents::Operate::ResponderAPassagem.new(conversation: conversation.reload, agent_inbox: agent_inbox,
                                                                   passagem: instance_double(Crm::Passagem, id: 7))

    responder.send(:post_reply!, 'Sigo daqui.')
    expect(conversation.messages.outgoing.reorder(:id).last.content_attributes).to include(to_emails: [], cc_emails: [], bcc_emails: [])
  end

  # Pega: a flag desligada mudar a resposta da IA.
  it 'sem a flag, a resposta da IA não leva cópia, como antes' do
    account.disable_features!(Crm::Email::Autoria::FLAG)
    recebido!(from: 'joao@empresa.com.br', cc: ['ana@familia.com.br'])
    expect(described_class).not_to receive(:new)

    expect(resposta_da_ia).to include(to_emails: [], cc_emails: [], bcc_emails: [])
  end

  def create_card_para(message)
    admin = create(:user, account: account, role: :administrator)
    pipeline = create_crm_pipeline(account: account, user: admin).first
    account.crm_cards.create!(pipeline: pipeline, stage: pipeline.stages.first, title: 'Seguro', contact: joao, primary_conversation: conversation,
                              inbox: inbox, currency: 'BRL',
                              metadata: { 'ai' => { 'auto_followup_state' => { 'opt_out_decision' => 'pendente',
                                                                               'stopped_message_id' => message.id } } })
  end
end
