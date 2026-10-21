require 'rails_helper'

# #2067 (decisão do Rodrigo em 21/10): o ícone "ficar com a conversa ao enviar" do painel. Ligado, quem respondeu fica com
# ela, venha de ninguém, da IA ou de um colega; desligado, ninguém fica. Troca a decisão de 13/10 para o painel.
RSpec.describe 'Ficar com a conversa ao enviar' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }
  let(:joao) { create(:user, account: account, role: :agent, name: 'João') }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:bot) { create(:agent_bot, account: account, name: 'Lia') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open).reload }

  before do
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)
    [ana, joao].each { |user| create(:inbox_member, inbox: inbox, user: user) }
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
    Current.user = ana
  end

  after { Current.reset }

  def reply(ficar:, **attrs)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: ana,
                     content: 'Oi, sou a Ana', ficar_com_a_conversa: ficar, **attrs)
  end

  def com_o_robo!
    conversation.update!(ai_assignee: bot, assignee: nil)
  end

  def passagens
    Crm::Passagem.where(conversation_id: conversation.id)
  end

  # Pega a regra de 13/10 sobrevivendo no painel: com a IA atendendo (sem marca de espera), o ícone ligado tira a IA.
  it 'ligado, com a IA atendendo: quem respondeu fica com ela e a IA sai', :aggregate_failures do
    com_o_robo!

    reply(ficar: true)

    expect(conversation.reload).to have_attributes(assignee_id: ana.id, ai_assignee: nil, status: 'open')
    passagem = passagens.sole
    expect([passagem.de_type, passagem.de_id, passagem.para_id]).to eq(['AgentBot', bot.id, ana.id])
  end

  it 'ligado, sem ninguém: quem respondeu fica com ela' do
    reply(ficar: true)

    expect(conversation.reload.assignee_id).to eq(ana.id)
  end

  # Pega o servidor confiando só na tela: tomar de colega só com o pedido explícito.
  it 'ligado, na conversa de um colega: o pedido explícito passa a conversa para quem respondeu' do
    conversation.update!(assignee: joao)

    reply(ficar: true)

    expect(conversation.reload.assignee_id).to eq(ana.id)
  end

  it 'sem o pedido, a conversa do colega continua com ele' do
    conversation.update!(assignee: joao)

    reply(ficar: nil)

    expect(conversation.reload.assignee_id).to eq(joao.id)
  end

  # Pega o #1499 atribuindo por cima do ícone desligado.
  it 'desligado, na conversa à espera de pessoa: ninguém fica e a espera continua', :aggregate_failures do
    com_o_robo!
    conversation.bot_handoff!

    reply(ficar: false)

    conversation.reload
    expect(conversation).to have_attributes(assignee_id: nil, ai_assignee: bot)
    expect(conversation.bot_handoff_waiting?).to be(true)
  end

  it 'desligado, com a IA atendendo: a IA continua' do
    com_o_robo!

    reply(ficar: false)

    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: bot)
  end

  it 'nota privada nunca fica, nem com o pedido' do
    com_o_robo!

    reply(ficar: true, private: true)

    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: bot)
  end

  # Pega a dupla atribuição: o #1499 e o pedido explícito no mesmo envio, e as mensagens seguintes do mesmo envio.
  it 'à espera e com o pedido: uma atribuição e uma passagem só, também nas mensagens seguintes', :aggregate_failures do
    com_o_robo!
    conversation.bot_handoff!
    antes = passagens.count

    3.times { reply(ficar: true) }

    expect(conversation.reload.assignee_id).to eq(ana.id)
    expect(passagens.count).to eq(antes + 1)
  end

  it 'mensagem de robô com o pedido não atribui ninguém' do
    com_o_robo!

    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: bot,
                     content: 'Oi', ficar_com_a_conversa: true)

    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: bot)
  end
end
