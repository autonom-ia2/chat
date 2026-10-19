require 'rails_helper'

# #1807: o agente de IA, o copiloto e o Decisor também leem quem escreveu cada e-mail e só o que foi escrito nele.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_email, account: account).inbox }
  let(:joao) { create(:contact, account: account, email: 'joao@empresa.com.br') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: joao, assignee: nil) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.')
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: create(:agent_bot, account: account))
  end
  let(:responder) { described_class.new(conversation: conversation.reload, agent_inbox: agent_inbox) }
  let(:citado) { "Ok, pode seguir.\n\n> meu CPF é 987.654.321-00" }

  before { account.enable_features!(Crm::Email::Autoria::FLAG) }

  def email!(from:, content:, quoted:)
    create(:message, account: account, inbox: inbox, conversation: conversation, sender: joao, message_type: :incoming,
                     content_type: :incoming_email, content: content,
                     content_attributes: { 'email' => { 'from' => [from], 'text_content' => { 'reply' => content, 'quoted' => quoted } } })
  end

  def cenario!
    email!(from: 'ana@familia.com.br', content: 'parem de me copiar', quoted: 'parem de me copiar')
    email!(from: 'joao@empresa.com.br', content: citado, quoted: 'Ok, pode seguir.')
  end

  # Pega: o agente ler a Ana como o cliente, ou o CPF citado embaixo da resposta do João; o aviso ir como voz da IA.
  it 'o histórico e a pergunta do agente levam o aviso da Ana e o texto do João sem o histórico', :aggregate_failures do
    cenario!

    da_ana, do_joao = responder.send(:history)
    expect(da_ana).to include(role: 'user', content: start_with('[E-mail de ana@familia.com.br, endereço que não é do cliente'))
    expect(do_joao).to eq(role: 'user', content: 'Ok, pode seguir.')
    expect(responder.send(:query)).to eq('Ok, pode seguir.')
    expect(responder.send(:contexto_do_turno)).to eq(Crm::Email::Autoria::LEGENDA)
  end

  # Pega: a Fase 2 (moldura da equipe) perder o aviso ou neutralizá-lo como se fosse texto do cliente.
  it 'com a Fase 2, o aviso vem depois da segunda camada e a legenda junto da regra do turno', :aggregate_failures do
    Autonomia::Agents::Fase2.ligar!(account)
    cenario!

    da_ana, do_joao = responder.send(:history)
    expect(da_ana[:content]).to start_with('[E-mail de ana@familia.com.br').and end_with('] parem de me copiar')
    expect(do_joao[:content]).to eq('Ok, pode seguir.')
    expect(responder.send(:contexto_do_turno)).to include(Crm::Email::Autoria::LEGENDA)
  end

  # Pega: a flag desligada mudar o histórico, a pergunta ou o contexto do turno do agente.
  it 'sem a flag, o agente lê como antes', :aggregate_failures do
    account.disable_features!(Crm::Email::Autoria::FLAG)
    cenario!

    expect(responder.send(:history).pluck(:content)).to eq(['parem de me copiar', citado])
    expect(responder.send(:query)).to eq(citado)
    expect(responder.send(:contexto_do_turno)).to be_nil
  end

  # Pega: o copiloto e o Decisor seguirem chamando a Ana de "Cliente"; o Decisor mandar endereço de e-mail ao Jev.
  it 'o copiloto e o Decisor dizem quem escreveu, e o Decisor sem o endereço', :aggregate_failures do
    cenario!
    copiloto = Autonomia::Copilot::ConversationCopilot.new(conversation: conversation.reload, task: 'summarize')
    estado = Autonomia::Decisores::Estado.new(conversation: conversation, leituras: %w[mensagens_recentes])

    expect(copiloto.send(:transcript).lines.map(&:chomp)).to match([start_with('[E-mail de ana@familia.com.br'), 'Cliente: Ok, pode seguir.'])
    ana, joao_texto = estado.conversa[:messages]
    expect(ana).to start_with('Someone else by e-mail').and end_with(': parem de me copiar')
    expect(ana).not_to include('@')
    expect(joao_texto).to eq('Ok, pode seguir.')
  end
end
