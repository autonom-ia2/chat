require 'rails_helper'

# #2067 (decisões do Rodrigo em 21 e 22/10): o ícone "ficar com a conversa ao enviar" do painel. Ligado, quem respondeu
# fica com ela, se o dono ainda é o que a tela viu; desligado, ninguém fica. "Ao enviar" é ao clicar em Enviar: a
# mensagem gravada (se o provedor recusar depois, a conversa continua com quem tentou).
RSpec.describe 'Ficar com a conversa ao enviar' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }
  let(:joao) { create(:user, account: account, role: :agent, name: 'João') }
  let(:bia) { create(:user, account: account, role: :agent, name: 'Bia') }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:bot) { create(:agent_bot, account: account, name: 'Lia') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open).reload }

  before do
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)
    [ana, joao, bia].each { |user| create(:inbox_member, inbox: inbox, user: user) }
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
    Current.user = ana
  end

  after { Current.reset }

  def pedido(fica, visto = { tipo: 'ia' })
    Conversations::FicarAoEnviar::Pedido.new(fica: fica, visto: visto && { id: nil }.merge(visto))
  end

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

    mensagem = reply(ficar: pedido(true))

    expect(conversation.reload).to have_attributes(assignee_id: ana.id, ai_assignee: nil, status: 'open')
    passagem = passagens.sole
    expect([passagem.de_type, passagem.de_id, passagem.para_id]).to eq(['AgentBot', bot.id, ana.id])
    expect(mensagem.ficar_com_a_conversa_nao_deu).to be_nil
  end

  # Pega a passagem sem o porquê: o registro diz que a pessoa ficou ao enviar (e o envio sem pedido segue o de antes).
  it 'o registro de passagens grava o motivo do pedido explícito', :aggregate_failures do
    com_o_robo!
    reply(ficar: pedido(true))
    expect(passagens.sole.motivo).to eq('ficou_ao_enviar')
    expect(Crm::Passagem::MOTIVOS_DA_IA).not_to include('ficou_ao_enviar')

    outra = create(:conversation, account: account, inbox: inbox, status: :open).reload
    outra.update!(ai_assignee: bot, assignee: nil)
    outra.bot_handoff!
    create(:message, account: account, inbox: inbox, conversation: outra, message_type: :outgoing, sender: ana,
                     content: 'Oi', ficar_com_a_conversa: nil)
    expect(outra.reload.assignee_id).to eq(ana.id)
    expect(Crm::Passagem.where(conversation_id: outra.id).last.motivo).to eq('atribuicao')
  end

  it 'ligado, sem ninguém: quem respondeu fica com ela' do
    reply(ficar: pedido(true, tipo: 'ninguem'))

    expect(conversation.reload.assignee_id).to eq(ana.id)
  end

  # Pega o servidor confiando só na tela: tomar de colega só com o pedido explícito e com o colega que a tela viu.
  it 'ligado, na conversa do colega que a tela viu: passa para quem respondeu' do
    conversation.update!(assignee: joao)

    reply(ficar: pedido(true, tipo: 'pessoa', id: joao.id))

    expect(conversation.reload.assignee_id).to eq(ana.id)
  end

  describe 'a tela estava desatualizada (corrida)' do
    # Pega a pessoa tomando de um colega que pegou a conversa enquanto ela escrevia.
    it 'a tela viu a IA, um colega pegou: continua com o colega e a resposta avisa', :aggregate_failures do
      conversation.update!(assignee: joao)

      mensagem = nil
      linhas = capturar_log { mensagem = reply(ficar: pedido(true, tipo: 'ia')) }

      expect(conversation.reload.assignee_id).to eq(joao.id)
      expect(mensagem.ficar_com_a_conversa_nao_deu).to be(true)
      expect(linhas).to include(a_string_including('[conversa][ficar_ao_enviar]', "conversa=#{conversation.id}", 'dono_mudou'))
    end

    it 'a tela viu um colega, outro pegou: continua com o outro' do
      conversation.update!(assignee: bia)

      reply(ficar: pedido(true, tipo: 'pessoa', id: joao.id))

      expect(conversation.reload.assignee_id).to eq(bia.id)
    end

    it 'a tela viu sem ninguém, a IA pegou: fica com quem respondeu (sem ninguém e IA são a mesma situação)' do
      com_o_robo!

      reply(ficar: pedido(true, tipo: 'ninguem'))

      expect(conversation.reload.assignee_id).to eq(ana.id)
    end

    it 'o pedido sem o dono visto (cliente antigo da API) nunca toma de colega' do
      conversation.update!(assignee: joao)

      reply(ficar: pedido(true, nil))

      expect(conversation.reload.assignee_id).to eq(joao.id)
    end
  end

  # Pega o "não deu" calado: trava ocupada por uma entrega com o ícone ligado.
  it 'trava ocupada com o ícone ligado: a mensagem sai, a resposta avisa e o log diz por quê', :aggregate_failures do
    com_o_robo!
    allow(Conversation).to receive(:lock).and_raise(ActiveRecord::LockWaitTimeout)

    mensagem = nil
    linhas = capturar_log { mensagem = reply(ficar: pedido(true)) }

    expect(mensagem).to be_persisted
    expect(mensagem.ficar_com_a_conversa_nao_deu).to be(true)
    expect(linhas).to include(a_string_including('[conversa][ficar_ao_enviar]', 'trava_ocupada'))
  end

  it 'ícone desligado nunca avisa, nem com a trava ocupada' do
    com_o_robo!
    conversation.bot_handoff!
    allow(Conversation).to receive(:lock).and_raise(ActiveRecord::LockWaitTimeout)

    expect(reply(ficar: pedido(false)).ficar_com_a_conversa_nao_deu).to be_nil
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

    reply(ficar: pedido(false))

    conversation.reload
    expect(conversation).to have_attributes(assignee_id: nil, ai_assignee: bot)
    expect(conversation.bot_handoff_waiting?).to be(true)
  end

  it 'desligado, com a IA atendendo: a IA continua' do
    com_o_robo!

    reply(ficar: pedido(false))

    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: bot)
  end

  it 'nota privada nunca fica, nem com o pedido' do
    com_o_robo!

    reply(ficar: pedido(true), private: true)

    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: bot)
  end

  # Pega a dupla atribuição: o #1499 e o pedido explícito no mesmo envio, e as mensagens seguintes do mesmo envio.
  it 'à espera e com o pedido: uma atribuição e uma passagem só, também nas mensagens seguintes', :aggregate_failures do
    com_o_robo!
    conversation.bot_handoff!
    antes = passagens.count

    mensagens = Array.new(3) { reply(ficar: pedido(true)) }

    expect(conversation.reload.assignee_id).to eq(ana.id)
    expect(passagens.count).to eq(antes + 1)
    expect(mensagens.map(&:ficar_com_a_conversa_nao_deu)).to all(be_nil)
  end

  it 'mensagem de robô com o pedido não atribui ninguém' do
    com_o_robo!

    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: bot,
                     content: 'Oi', ficar_com_a_conversa: pedido(true))

    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: bot)
  end

  # Decisão 1 (22/10): "ao enviar" é a mensagem gravada. O provedor recusar depois não devolve a conversa.
  it 'o provedor recusou depois de gravar: a conversa continua com quem tentou' do
    com_o_robo!

    mensagem = reply(ficar: pedido(true))
    mensagem.update!(status: :failed, external_error: 'recusada pelo provedor')

    expect(conversation.reload.assignee_id).to eq(ana.id)
  end

  def capturar_log
    saida = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(saida)
    yield
    saida.string.lines
  ensure
    Rails.logger = original
  end
end
